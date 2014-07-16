require 'socket'

module IsolatedServer
  class Base
    attr_reader :pid, :base, :port
    attr_accessor :params

    def locate_executable(*candidates)
      output = `which #{candidates.join(' ')}`
      raise "I couldn't find any of these: #{candidates.join(',')} in $PATH" if output.chomp.empty?
      output.split("\n").first
    end

    def down!
      Process.kill("TERM", @pid)
      while (Process.kill 0, @pid rescue false)
        sleep 1
      end
      @cx = nil
    end

    def kill!
      return unless @pid
      system("kill -TERM #{@pid}")
    end

    def cleanup!
      system("rm -Rf #{base}")
    end

    include Socket::Constants
    def grab_free_port
      while true
        candidate=9000 + rand(50_000)

        begin
          socket = Socket.new(AF_INET, SOCK_STREAM, 0)
          socket.bind(Socket.pack_sockaddr_in(candidate, '127.0.0.1'))
          socket.close
          return candidate
        rescue Exception => e
        end
      end
    end

    def self.exec_wait(cmd, options = {})
      allow_output = options[:allow_output] # default false
      parent_pid = options[:parent_pid] || $$

      fork do
        exec_pid = fork do
          if !allow_output
            devnull = File.open("/dev/null", "w")
            STDOUT.reopen(devnull)
            STDERR.reopen(devnull)
          end

          exec(cmd)
        end

        # begin waiting for the parent (or mysql) to die; at_exit is hard to control when interacting with test/unit
        # we can also be killed by our parent with down! and up!
        #
        ["TERM", "INT"].each do |sig|
          trap(sig) do
            if block_given?
              yield(exec_pid)
            else
              Process.kill("KILL", exec_pid)
            end

            exit!
          end
        end

        while true
          begin
            Process.kill(0, parent_pid)
            Process.kill(0, exec_pid)
          rescue Exception => e
            if block_given?
              yield(exec_pid)
            else
              Process.kill("KILL", exec_pid)
            end

            exit!
          end

          sleep 1
        end
      end
    end

    def exec_server(cmd)
      cmd.strip!
      cmd.gsub!(/\\\n/, ' ')

      @pid = self.class.exec_wait(cmd, allow_output: @allow_output, parent_pid: @parent_pid) do |child_pid|
        Process.kill("KILL", child_pid)
        cleanup!
      end
    end
  end
end
