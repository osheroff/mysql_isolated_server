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

  def query_mysql_global_variable(isolated_database, key)
    isolated_database.
      connection.
      query("show global variables like '#{key}'").
      first["Value"]
  end

end
