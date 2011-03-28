require 'rubygems'
require 'backports'
require 'bud'
require 'heartbeat/heartbeat'
require 'bfs/bfs_client_proto'

module HBMaster
  include HeartbeatAgent
  include BFSHBProtocol

  state do
    interface output, :available, [] => [:pref_list]
    table :chunk_cache, [:node, :chunkid, :time]
    scratch :chunk_cache_nodes, [:node]
    # at any given time, :available will contain a list of datanodes in preference order.
    # for now, arbitrary
    periodic :master_duty_cycle, MASTER_DUTY_CYCLE
  end

  bloom :hbmasterlogic do
    #stdio <~ last_heartbeat.inspected
    chunk_cache <= (master_duty_cycle * last_heartbeat).flat_map do |d, l| 
      unless l.payload[1].nil?
        l.payload[1].map do |pay|
          [l.peer, pay, Time.parse(d.val).to_f]
        end 
      end
    end

    hb_ack <~ last_heartbeat do |l|
      [l.sender, l.payload[0]] unless l.payload[1] == [nil]
    end

    chunk_cache <- (master_duty_cycle * chunk_cache).pairs do |t, c|
      c unless last_heartbeat.map{|h| h.peer}.include? c.node
    end

    chunk_cache_nodes <= chunk_cache { |cc| [cc.node] }
    available <= chunk_cache_nodes.group(nil, accum(chunk_cache_nodes.node))
  end
end
