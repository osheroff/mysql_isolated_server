require 'tmpdir'
require 'socket'

if RUBY_PLATFORM == "java"
  require 'mysql_isolated_server/jdbc_connection'
else
  require 'mysql_isolated_server/mysql2_connection'
end

class MysqlIsolatedServer
  include DBConnection
  attr_reader :pid, :base, :port, :initial_binlog_file, :initial_binlog_pos
  attr_accessor :params
  MYSQL_BASE_DIR="/usr"

  def initialize(options = {})
    @base = options[:base] || Dir.mktmpdir("mysql_isolated", "/tmp")
    @mysql_data_dir="#{@base}/mysqld"
    @mysql_socket="#{@mysql_data_dir}/mysqld.sock"
    @params = options[:params]
    @load_data_path = options[:data_path]
    @port = options[:port]
    @allow_output = options[:allow_output]
    @log_bin = options[:log_bin] || "--log-bin"
    @parent_pid = options[:pid]
    @server_id = rand(2**31)
  end

  def self.thread_boot(*params)
    bin = [File.dirname(__FILE__) + "/../bin/boot_isolated_server"]
    mysql_dir, mysql_port = nil, nil
    restore_env = {}

    if `which ruby` =~ (/rvm/)
      bin = ["rvm", "1.8.7", "do", "ruby"] + bin
    end

    params = ["--pid", $$.to_s] + params

    Thread.abort_on_exception = true
    Thread.new do
      ENV.keys.grep(/GEM|BUNDLE|RUBYOPT/).each do |k|
        restore_env[k] = ENV.delete(k)
      end
      pipe = IO.popen(bin + params, "r") do |pipe|
        mysql_dir = pipe.readline.split(' ').last
        mysql_port = pipe.readline.split(' ').last.to_i
        sleep
      end
    end

    while mysql_port.nil?
      sleep 1
    end
    new(:port => mysql_port, :base => mysql_dir)
  end

  def make_slave_of(master)
    binlog_file = master.initial_binlog_file || (@log_bin.split('/').last + ".000001")
    binlog_pos = master.initial_binlog_pos || 4

    connection.query(<<-EOL
      change master to master_host='127.0.0.1',
                       master_port=#{master.port},
                       master_user='root', master_password='',
                       master_log_file='#{binlog_file}',
                       master_log_pos=#{binlog_pos}
      EOL
    )
    connection.query("START SLAVE")
    connection.query("SET GLOBAL READ_ONLY=1")
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
                #{@params} --socket=#{@mysql_data_dir}/mysql.sock #{@log_bin} --log-slave-updates
    EOL

    while !system("mysql -h127.0.0.1 --port=#{@port} --database=mysql -u root -e 'select 1' >/dev/null 2>&1")
      sleep(0.1)
    end
  end

  def down!
    Process.kill("HUP", @pid)
    while (Process.kill 0, @pid rescue false)
      Process.waitpid(@pid)
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

    if !@log_bin
      @log_bin = "--log-bin"
    else
      if @log_bin[0] != '/'
        binlog_dir = "#{@mysql_data_dir}/#{@log_bin}"
      else
        binlog_dir = @log_bin
      end

      system("mkdir -p #{binlog_dir}")
      @log_bin = "--log-bin=#{binlog_dir}"
    end

    up!

    master_binlog_info = connection.query("show master status").first
    @initial_binlog_file, @initial_binlog_pos = master_binlog_info.values_at('File', 'Position')

    tzinfo_to_sql = locate_executable("mysql_tzinfo_to_sql5", "mysql_tzinfo_to_sql")
    raise "could not find mysql_tzinfo_to_sql" unless tzinfo_to_sql
    system("#{tzinfo_to_sql} /usr/share/zoneinfo 2>/dev/null| mysql -h127.0.0.1 --database=mysql --port=#{@port} -u root mysql ")

    begin
      connection.query("SET GLOBAL time_zone='UTC'")
    rescue Mysql2::Error
      connection.query("SET GLOBAL time_zone='UTC'")
    end

    connection.query("SET GLOBAL server_id=#{@server_id}")
  end

  include Socket::Constants
  def grab_free_port
    while true
      candidate=9000 + rand(50_000)

      begin
        socket = Socket.new(AF_INET, SOCK_STREAM, 0)
        socket.bind(Socket.pack_sockaddr_in(candidate, '127.0.0.1'))
        socket.close
        return candidate
      rescue Exception => e
      end
    end
  end

  attr_reader :pid
  def self.exec_wait(cmd, options = {})
    allow_output = options[:allow_output] # default false
    parent_pid = options[:parent_pid] || $$

    fork do
      exec_pid = fork do
        if !allow_output
          devnull = File.open("/dev/null", "w")
          STDOUT.reopen(devnull)
          STDERR.reopen(devnull)
        end

        exec(cmd)
      end

      # begin waiting for the parent (or mysql) to die; at_exit is hard to control when interacting with test/unit
      # we can also be killed by our parent with down! and up!
      #
      ["TERM", "INT"].each do |sig|
        trap(sig) do
          if block_given?
            yield(exec_pid)
          else
            Process.kill("KILL", exec_pid)
          end

          exit!
        end
      end

      # HUP == don't cleanup.
      trap("HUP") do
        Process.kill("KILL", exec_pid)
        exit!
      end

      while true
        begin
          Process.kill(0, parent_pid)
          Process.kill(0, exec_pid)
        rescue Exception => e
          if block_given?
            yield(exec_pid)
          else
            Process.kill("KILL", exec_pid)
          end

          exit!
        end

        sleep 1
      end
    end
  end

  def exec_server(cmd)
    cmd.strip!
    cmd.gsub!(/\\\n/, ' ')
    system("mkdir -p #{base}/tmp")
    system("chmod 0777 #{base}/tmp")

    parent_pid = @parent_pid || $$
    mysql_pid = nil

    ENV["TMPDIR"] = "#{base}/tmp"
    @pid = MysqlIsolatedServer.exec_wait(cmd, allow_output: @allow_output, parent_pid: @parent_pid) do |mysql_pid|
      Process.kill("KILL", mysql_pid)
      cleanup!
    end
  end

  def mysql_shell
    system("mysql -uroot --port #{@port} mysql --host 127.0.0.1")
  end
  def cleanup!
    system("rm -Rf #{base}")
  end

  def kill!
    return unless @pid
    system("kill -TERM #{@pid}")
  end

  def reconnect!
    @cx = nil
    connection
  end
end
