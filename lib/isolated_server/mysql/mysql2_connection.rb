module IsolatedServer
  class Mysql < Base
    module DBConnection
      def connection
        require 'mysql2'
        @cx ||= Mysql2::Client.new(:host => "127.0.0.1", :port => @port, :username => "root", :password => "", :database => "mysql")
      end
    end
  end
end
