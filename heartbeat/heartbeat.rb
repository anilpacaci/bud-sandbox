require 'rubygems'
require 'bud'
require 'time'
#require 'lib/bfs_client'
require 'membership/membership'

HB_EXPIRE = 6.0

module HeartbeatProtocol
  include MembershipProto

  state do
    interface input, :payload, [] => [:payload]
    interface input, :return_address, [] => [:addy]
    interface output, :last_heartbeat, [:peer] => [:time, :payload]
  end
end

module HeartbeatAgent
  include HeartbeatProtocol

  state do
    channel :heartbeat, [:@dst, :src, :payload]
    table :heartbeat_buffer, [:peer, :payload]
    table :heartbeat_log, [:peer, :time, :payload]
    table :payload_buffer, [:payload]
    table :my_address, [] => [:addy]
    periodic :hb_timer, 2

    scratch :to_del, heartbeat_log.schema
  end

  declare
  def selfness
    my_address <+ return_address
    my_address <- join([my_address, return_address]).map{ |m, r| puts "update my addresss" or m }
  end

  declare 
  def announce
    heartbeat <~ join([hb_timer, member, payload_buffer, my_address]).map do |t, m, p, r|
      unless m.host == r.addy 
       [m.host, r.addy, p.payload]
      end
    end

    heartbeat <~ join([hb_timer, member, payload_buffer]).map do |t, m, p|
      if my_address.empty?
        unless m.host == ip_port
          [m.host, ip_port, p.payload]
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
    heartbeat_buffer <= heartbeat.map{|h| [h.src, h.payload] }
    duty_cycle = join [hb_timer, heartbeat_buffer]
    # PAA: <+ ---> <=
    heartbeat_log <= duty_cycle.map{|t, h| [h.peer, Time.parse(t.val).to_f, h.payload] }
    heartbeat_buffer <- duty_cycle.map{|t, h| h } 
  end

  declare 
  def current_output
    #stdio <~ last_heartbeat.inspected
    last_heartbeat <= heartbeat_log.argagg(:max, [heartbeat_log.peer], heartbeat_log.time)
    to_del <= join([heartbeat_log, hb_timer]).map do |log, t|
      if ((Time.parse(t.val).to_f) - log.time) > HB_EXPIRE
        log
      end
    end
    heartbeat_log <- to_del
  end 
end
