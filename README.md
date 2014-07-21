[![Build Status](https://travis-ci.org/gabetax/isolated_server.svg?branch=master)](https://travis-ci.org/gabetax/isolated_server)

# Mysql Isolated Servers -- a gem for testing mysql stuff

This gem provides functionality to quickly bring up and tear down mysql instances for the 
purposes of testing code against more advanced mysql topologies -- replication, vertical
partitions, etc.

I developed this as part of my testing strategy for implementing http://github.com/osheroff/ar_mysql_flexmaster, but it's 
been useful in developement of a couple of other projects too (http://github.com/osheroff/mmtop).

## Usage

```
$mysql_master = IsolatedServer::Mysql.new(allow_output: false)
$mysql_master.boot!

puts "mysql master booted on port #{$mysql_master.port} -- access with mysql -uroot -h127.0.0.1 --port=#{$mysql_master.port} mysql"

$mysql_slave = IsolatedServer::Mysql.new
$mysql_slave.boot!

puts "mysql slave booted on port #{$mysql_slave.port} -- access with mysql -uroot -h127.0.0.1 --port=#{$mysql_slave.port} mysql"

$mysql_slave_2 = IsolatedServer::Mysql.new
$mysql_slave_2.boot!

puts "mysql chained slave booted on port #{$mysql_slave_2.port} -- access with mysql -uroot -h127.0.0.1 --port=#{$mysql_slave_2.port} mysql"

$mysql_slave.make_slave_of($mysql_master)
$mysql_slave_2.make_slave_of($mysql_slave)

$mysql_slave.set_rw(false)
sleep if __FILE__ == $0
```

