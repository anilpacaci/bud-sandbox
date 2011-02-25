require 'rubygems'
require 'bud'
require 'time'
#require 'lib/bfs_client'
require 'membership/membership'

HB_EXPIRE = 4.0

module HeartbeatProtocol
  include MembershipProto

  state {
    interface input, :payload, [] => [:payload]
    interface input, :return_address, [] => [:addy]
    interface output, :last_heartbeat, [:peer] => [:peer_time, :time, :payload]
  }
end

module HeartbeatAgent
  include HeartbeatProtocol

  state {
    channel :heartbeat, [:@dst, :src, :peer_time, :payload]
    table :heartbeat_buffer, [:peer, :peer_time, :payload]
    table :heartbeat_log, [:peer, :peer_time, :time, :payload]
    table :payload_buffer, [:payload]
    table :my_address, [] => [:addy]
    periodic :hb_timer, 1

    scratch :to_del, heartbeat_log.schema
  }

  declare
  def selfness
    my_address <+ return_address
    my_address <- join([my_address, return_address]).map{ |m, r| puts "update my addresss" or m }
  end

  declare 
  def announce
    heartbeat <~ join([hb_timer, member, payload_buffer, my_address]).map do |t, m, p, r|
      unless m.host == r.addy 
       [m.host, r.addy, Time.parse(t.val).to_f, p.payload]
      end
    end

    heartbeat <~ join([hb_timer, member, payload_buffer]).map do |t, m, p|
      if my_address.empty?
        unless m.host == ip_port
          [m.host, ip_port, Time.parse(t.val).to_f, p.payload]
        end
      end
    end
  end
  
  declare
  def buffer
    payload_buffer <+ payload
    payload_buffer <- join([payload_buffer, payload]).map{|b, p| b }
  end 

  declare 
  def reckon
    heartbeat_buffer <= heartbeat.map{|h| [h.src, h.peer_time, h.payload] }
    duty_cycle = join [hb_timer, heartbeat_buffer]
    # what's the point of 'peer time' ?
    heartbeat_log <+ duty_cycle.map{|t, h| [h.peer, nil, Time.parse(t.val).to_f, h.payload] }
    heartbeat_buffer <- duty_cycle.map{|t, h| h } 
  end

  declare 
  def current_output
    last_heartbeat <= heartbeat_log.argagg(:max, [heartbeat_log.peer], heartbeat_log.time)
    to_del <= join([heartbeat_log, hb_timer]).map do |log, t|
      if ((Time.parse(t.val).to_f) - log.time) > HB_EXPIRE
        log
      end
    end
    heartbeat_log <- to_del
  end 
end
