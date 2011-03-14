require 'rubygems'
require 'bud'
require 'backports'
require 'heartbeat/heartbeat'
require 'membership/membership'
require 'bfs/data_protocol'

module BFSDatanode
  include HeartbeatAgent
  include StaticMembership

  state do
    table :local_chunks, [:chunkid, :size]
    table :data_port, [] => [:port]
  end

  declare 
  def hblogic
    payload <= hb_timer.map do |t|
      dir = Dir.new("#{DATADIR}/#{@data_port}")
      #files = dir.to_a.find_all{|d| !(d =~ /^\./)}.map{|d| d.to_i }
      files = dir.to_a.map{|d| d.to_i unless d =~ /^\./}.uniq!
      dir.close
      [files]
    end
  end

  def initialize(dataport=nil, opts={})
    super(opts)
    @data_port = dataport.nil? ? 0 : dataport
    @dp_server = DataProtocolServer.new(dataport)
    return_address <+ [["localhost:#{dataport}"]]
  end

  def stop_datanode
    @dp_server.stop_server
    stop_bg
  end
end
