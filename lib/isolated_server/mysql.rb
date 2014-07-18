if RUBY_PLATFORM == "java"
  require 'isolated_server/mysql/jdbc_connection'
else
  require 'isolated_server/mysql/mysql2_connection'
end

require 'tmpdir'

module IsolatedServer
  class Mysql < Base

    include DBConnection

    attr_reader :server_id, :mysql_data_dir

    def initialize(options = {})
      super options
      @mysql_data_dir = "#{@base}/mysqld"
      @mysql_socket   = "#{@mysql_data_dir}/mysqld.sock"
      @load_data_path = options[:data_path]
      @log_bin        = options[:log_bin] || "--log-bin"
      @server_id      = rand(2**31)
    end

    # For JRuby
    # @todo Extract and genericize more of this into `Base`
    def self.thread_boot(*params)
      bin = [File.dirname(__FILE__) + "/../bin/boot_isolated_mysql_server"]
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
        system("cp #{File.expand_path(File.dirname(__FILE__))}/mysql/tables/user.* #{@mysql_data_dir}/mysql")
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

    def up!
      system("mkdir -p #{base}/tmp")
      system("chmod 0777 #{base}/tmp")
      # http://dev.mysql.com/doc/refman/5.0/en/temporary-files.html
      ENV["TMPDIR"] = "#{base}/tmp"

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

    def console
      system("mysql -uroot --port #{@port} mysql --host 127.0.0.1")
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

    def set_rw(rw)
      ro = rw ? 0 : 1
      connection.query("SET GLOBAL READ_ONLY=#{ro}")
    end

  end
end
