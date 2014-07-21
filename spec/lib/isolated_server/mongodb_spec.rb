require_relative '../../spec_helper'

describe IsolatedServer::Mongodb do
  subject { IsolatedServer::Mongodb.new }
  let(:collection) { subject.connection['test_db']['test_col'] }
  describe "#boot!" do
    it "starts up a new server" do
      subject.boot!
      expect(subject.pid).to be_a_running_process

      id = nil
      expect { id = collection.insert(name: 'Bob') }.
        to change { collection.count }.
        from(0).
        to(1)

      result = collection.find_one(id)
      expect(result['name']).to eq('Bob')

      subject.down!
      expect(subject.pid).not_to be_a_running_process
      expect(subject).not_to be_up
    end
  end
end
