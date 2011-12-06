require 'rubygems'
require 'bud'
require 'chat_protocol'

class ChatServer
  include Bud
  include ChatProtocol

  state { table :nodelist }

  bloom do
    nodelist <= connect.payloads
    recieved <~ (sent * nodelist).pairs { |s,n| [n.key, s.val] }
  end
end

# ruby command-line wrangling
addr = ARGV.first ? ARGV.first : ChatProtocol::DEFAULT_ADDR
ip, port = addr.split(":")
puts "Server address: #{ip}:#{port}"
program = ChatServer.new(:ip => ip, :port => port.to_i)
program.run_fg
