require 'tmpdir'

module IsolatedServer
  class Mongodb < Base

    attr_reader :dbpath, :port, :repl_set

    def initialize(options = {})
      super options
      @dbpath         = FileUtils.mkdir("#{@base}/data").first
    end

    def boot!
      @port ||= grab_free_port

      up!
    end

    def up!
      mongod = locate_executable("mongod")

      exec_server([
        mongod,
        '--dbpath', @dbpath,
        '--port', @port,
        *@params
      ])

      until up?
        sleep(0.1)
      end
    end

    def up?
      begin
        connection.ping
        true
      rescue Mongo::ConnectionFailure
        false
      end
    end

    def connection
      @connection ||= connection_klass.new('localhost', @port)
    end

    def connection_klass
      if Kernel.const_defined?("Mongo::MongoClient")
        # 1.8.0+
        Mongo::MongoClient
      else
        # < 1.8.0
        Mongo::Connection
      end
    end

    def console
      system(['mongo', '--port', @port].shelljoin)
    end
  end
end
