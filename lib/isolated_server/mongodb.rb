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
      ].shelljoin)

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
      @connection ||= Mongo::MongoClient.new('localhost', @port)
    end

    def console
      system(['mongo', '--port', @port].shelljoin)
    end
  end
end
