if RUBY_PLATFORM == "java"
  require 'isolated_server/mysql/jdbc_connection'
else
  require 'isolated_server/mysql/mysql2_connection'
end

require 'tmpdir'

module IsolatedServer
  class Mysql < Base

    include DBConnection

    attr_reader :server_id, :mysql_data_dir, :initial_binlog_file, :initial_binlog_pos

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
        IO.popen(bin + params, "r") do |pipe|
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

      setup_data_dir
      setup_binlog
      setup_tmp_dir

      up!

      record_initial_master_position

      setup_time_zone
      setup_server_id
    end

    def up!
      exec_server([
        locate_executable("mysqld"),
        '--no-defaults',
        '--default-storage-engine=innodb',
        "--datadir=#{@mysql_data_dir}",
        "--pid-file=#{@base}/mysqld.pid",
        "--port=#{@port}",
        "--socket=#{@mysql_data_dir}/mysql.sock",
        @log_bin,
        '--log-slave-updates',
        *@params
      ].shelljoin)

      sleep(0.1) until up?
    end

    def up?
      system("mysql -h127.0.0.1 --port=#{@port.to_s.shellescape} --database=mysql -u root -e 'select 1' >/dev/null 2>&1")
    end

    def console
      system("mysql -uroot --port #{@port.to_s.shellescape} mysql --host 127.0.0.1")
    end

    def make_slave_of(master)
      binlog_file = master.initial_binlog_file || (@log_bin.split('/').last + ".000001")
      binlog_pos = master.initial_binlog_pos || 106

      connection.query(<<-EOL
        CHANGE MASTER TO MASTER_HOST='127.0.0.1',
                         MASTER_PORT=#{master.port},
                         MASTER_USER='root', MASTER_PASSWORD='',
                         MASTER_LOG_FILE='#{binlog_file}',
                         MASTER_LOG_POS=#{binlog_pos}
        EOL
      )
      connection.query("SLAVE START")
      connection.query("SET GLOBAL READ_ONLY=1")
    end

    def set_rw(rw)
      ro = rw ? 0 : 1
      connection.query("SET GLOBAL READ_ONLY=#{ro}")
    end

    private

    def setup_data_dir
      system("rm -Rf #{@mysql_data_dir.shellescape}")
      system("mkdir #{@mysql_data_dir.shellescape}")
      if @load_data_path
        system("cp -a #{@load_data_path.shellescape}/* #{@mysql_data_dir.shellescape}")
        system("rm -f #{@mysql_data_dir.shellescape}/relay-log.info")
      else
        mysql_install_db = locate_executable("mysql_install_db")

        idb_path = File.dirname(mysql_install_db)
        system("(cd #{idb_path.shellescape}/..; mysql_install_db --datadir=#{@mysql_data_dir.shellescape} --user=`whoami`) >/dev/null 2>&1")
        system("cp #{File.expand_path(File.dirname(__FILE__)).shellescape}/mysql/tables/user.* #{@mysql_data_dir.shellescape}/mysql")
      end
    end

    def setup_binlog
      if !@log_bin
        @log_bin = "--log-bin"
      else
        if @log_bin[0] != '/'
          binlog_dir = "#{@mysql_data_dir}/#{@log_bin}"
        else
          binlog_dir = @log_bin
        end

        system("mkdir -p #{binlog_dir.shellescape}")
        @log_bin = "--log-bin=#{binlog_dir}"
      end
    end

    # http://dev.mysql.com/doc/refman/5.0/en/temporary-files.html
    def setup_tmp_dir
      system("mkdir -p #{base.shellescape}/tmp")
      system("chmod 0777 #{base.shellescape}/tmp")
      ENV["TMPDIR"] = "#{base.shellescape}/tmp"
    end

    # http://dev.mysql.com/doc/refman/5.5/en/mysql-tzinfo-to-sql.html
    def setup_time_zone
      tzinfo_to_sql = locate_executable("mysql_tzinfo_to_sql5", "mysql_tzinfo_to_sql")
      raise "could not find mysql_tzinfo_to_sql" unless tzinfo_to_sql
      system("#{tzinfo_to_sql.shellescape} /usr/share/zoneinfo 2>/dev/null | mysql -h127.0.0.1 --database=mysql --port=#{@port.to_s.shellescape} -u root mysql")

      begin
        connection.query("SET GLOBAL time_zone='UTC'")
      rescue Mysql2::Error
        connection.query("SET GLOBAL time_zone='UTC'")
      end
    end

    def setup_server_id
      connection.query("SET GLOBAL server_id=#{@server_id}")
    end

    def record_initial_master_position
      master_binlog_info = connection.query("show master status").first
      @initial_binlog_file, @initial_binlog_pos = master_binlog_info.values_at('File', 'Position')
    end
  end
end
