require 'pry'
require 'isolated_server/base'
require 'isolated_server/version'

# Load support for databases if their corresponding gem is available
begin
  require 'mongo'
  require 'isolated_server/mongodb'
rescue LoadError
end

begin
  require 'mysql2'
  require 'isolated_server/mysql'
rescue LoadError
end

module IsolatedServer
end
