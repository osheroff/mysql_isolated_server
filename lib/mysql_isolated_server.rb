require 'tmpdir'
require 'socket'
require 'mysql2'

class MysqlIsolatedServer
  attr_reader :pid, :base, :port
  MYSQL_BASE_DIR="/usr"

  def initialize(options = {})
    @base = Dir.mktmpdir("mysql_isolated", "/tmp")
    @mysql_data_dir="#{@base}/mysqld"
    @mysql_socket="#{@mysql_data_dir}/mysqld.sock"
    @params = options[:params]
    @load_data_path = options[:data_path]
    @port = options[:port]
    @allow_output = options[:allow_output]
    @server_id = rand(2**31)
  end

  def make_slave_of(master)
    master_binlog_info = master.connection.query("show master status").first
    connection.query(<<-EOL
      change master to master_host='127.0.0.1',
                       master_port=#{master.port},
                       master_user='root', master_password='',
                       master_log_file='#{master_binlog_info['File']}',
                       master_log_pos=#{master_binlog_info['Position']}
      EOL
    )
    connection.query("SLAVE START")
    connection.query("SET GLOBAL READ_ONLY=1")
  end

  def connection
    @cx ||= Mysql2::Client.new(:host => "127.0.0.1", :port => @port, :username => "root", :password => "", :database => "mysql")
  end

  def set_rw(rw)
    ro = rw ? 0 : 1
    connection.query("SET GLOBAL READ_ONLY=#{ro}")
  end


  def locate_executable(*candidates)
    output = `which #{candidates.join(' ')}`
    raise "I couldn't find any of these: #{candidates.join(',')} in $PATH" if output.chomp.empty?
    output.split("\n").first
  end

  def up!
    mysqld = locate_executable("mysqld")

    exec_server <<-EOL
        #{mysqld} --no-defaults --default-storage-engine=innodb \
                --datadir=#{@mysql_data_dir} --pid-file=#{@base}/mysqld.pid --port=#{@port} \
                #{@params} --socket=#{@mysql_data_dir}/mysql.sock --log-bin --log-slave-updates
    EOL

    while !system("mysql -h127.0.0.1 --port=#{@port} --database=mysql -u root -e 'select 1' >/dev/null 2>&1")
      sleep(0.1)
    end
  end

  def down!
    Process.kill("TERM", @pid)
    while (Process.kill 0, @pid rescue false)
      sleep 1
    end
    @cx = nil
  end

  def boot!
    @port ||= grab_free_port
    system("rm -Rf #{@mysql_data_dir}")
    system("mkdir #{@mysql_data_dir}")
    if @load_data_path
      system("cp -a #{@load_data_path}/* #{@mysql_data_dir}")
      system("rm -f #{@mysql_data_dir}/relay-log.info")
    else
      mysql_install_db = locate_executable("mysql_install_db")

      idb_path = File.dirname(mysql_install_db)
      system("(cd #{idb_path}/..; mysql_install_db --datadir=#{@mysql_data_dir} --user=`whoami`) >/dev/null 2>&1")
      system("cp #{File.expand_path(File.dirname(__FILE__))}/tables/user.* #{@mysql_data_dir}/mysql")
    end

    up!

    tzinfo_to_sql = locate_executable("mysql_tzinfo_to_sql5", "mysql_tzinfo_to_sql")
    raise "could not find mysql_tzinfo_to_sql" unless tzinfo_to_sql
    system("#{tzinfo_to_sql} /usr/share/zoneinfo 2>/dev/null | mysql -h127.0.0.1 --database=mysql --port=#{@port} -u root mysql ")
    connection.query("SET GLOBAL time_zone='UTC'")
    connection.query("SET GLOBAL server_id=#{@server_id}")
  end

  def grab_free_port
    while true
      candidate=9000 + rand(50_000)

      begin
        socket = Socket.new(:INET, :STREAM, 0)
        socket.bind(Addrinfo.tcp("127.0.0.1", candidate))
        socket.close
        return candidate
      rescue Exception => e
        puts e
      end
    end
  end

  attr_reader :pid
  def exec_server(cmd)
    cmd.strip!
    cmd.gsub!(/\\\n/, ' ')
    devnull = File.open("/dev/null", "w")
    system("mkdir -p #{base}/tmp")
    system("chmod 0777 #{base}/tmp")

    original_pid = $$
    mysql_pid = nil

    middle_pid = fork do
      mysql_pid = fork do
        ENV["TMPDIR"] = "#{base}/tmp"
        if !@allow_output
          STDOUT.reopen(devnull)
          STDERR.reopen(devnull)
        end

        exec(cmd)
      end

      # begin waiting for the parent (or mysql) to die; at_exit is hard to control when interacting with test/unit
      # we can also be killed by our parent with down! and up!
      #
      trap("TERM") do
        Process.kill("KILL", mysql_pid) rescue nil
        cleanup!
        exit!
      end

      while true
        begin
          Process.kill(0, original_pid)
          Process.kill(0, mysql_pid)
        rescue Exception => e
          Process.kill("KILL", mysql_pid) rescue nil
          cleanup!
          exit!
        end

        sleep 1
      end

      at
    end

    @pid = middle_pid
  end

  def cleanup!
    system("rm -Rf #{base}")
  end

  def kill!
    return unless @pid
    system("kill -KILL #{@pid}")
  end
end
