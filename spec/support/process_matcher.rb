require 'rspec/expectations'

RSpec::Matchers.define :be_a_running_process do
  match do |pid|
    begin
      Process.kill 0, pid
      true
    rescue Errno::EPERM, Errno::ESRCH
      false
    end
  end
end
