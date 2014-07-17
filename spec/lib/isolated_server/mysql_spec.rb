require_relative '../../spec_helper'

describe IsolatedServer::Mysql do
  subject { IsolatedServer::Mysql.new }
  describe "#boot!" do
    it "starts up a new server" do
      subject.boot!
      expect(subject.pid).to be_a_running_process

      # Make sure we are connected, queryable, and reasonably confident that global variables match our expectations
      expect(query_mysql_global_variable(subject, 'port').to_i).to          eq(subject.port)
      expect(query_mysql_global_variable(subject, 'server_id').to_i).to     eq(subject.server_id)
      expect(query_mysql_global_variable(subject, 'datadir').chomp('/')).to eq(subject.mysql_data_dir)
      expect(query_mysql_global_variable(subject, 'time_zone')).to          eq('UTC')

      expect { subject.set_rw(false) }.
        to change { query_mysql_global_variable(subject, 'read_only') }.
        from('OFF').
        to('ON')

      subject.down!
      expect(subject.pid).not_to be_a_running_process
    end
  end

  describe "#make_slave_of" do
    let(:master) { IsolatedServer::Mysql.new }
    let(:slave)  { IsolatedServer::Mysql.new }
    let(:db_name) { 'integration_test' }
    let(:person_name) { 'Bob' }

    it "sets establishes the relationship" do
      master.boot!
      slave.boot!

      slave.make_slave_of(master)
      sleep 0.1
      expect(slave_status(slave)['Slave_IO_State']).to eq("Waiting for master to send event")

      master.connection.query("CREATE DATABASE #{db_name}")
      master.connection.select_db(db_name)
      master.connection.query(create_table_sql)
      master.connection.query("INSERT INTO people SET name = '#{person_name}'")
      sleep 0.1

      slave.connection.select_db(db_name)
      slave_result = slave.connection.query('SELECT name FROM people').first
      expect(slave_result['name']).to eq person_name

      master.down!
      slave.down!

    end
  end

  def query_mysql_global_variable(isolated_database, key)
    isolated_database.
      connection.
      query("SHOW GLOBAL VARIABLES LIKE '#{key}'").
      first["Value"]
  end

  def slave_status(isolated_database)
    isolated_database.connection.query('SHOW SLAVE STATUS').first
  end

    def create_table_sql
      <<-eos
CREATE TABLE `people` (
  `id` int(11) NOT NULL AUTO_INCREMENT,
  `name` varchar(255) DEFAULT NULL,
  PRIMARY KEY (`id`)
) ENGINE=InnoDB;
eos
    end

end
