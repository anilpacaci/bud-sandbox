require 'rubygems'
require 'bud'

require 'cart/cart_lattice'

module MonotoneCartProtocol
  state do
    channel :action_msg,
      [:@server, :client, :session, :reqid] => [:item, :action]
    channel :checkout_msg,
      [:@server, :client, :session, :reqid] => [:lbound]
    channel :response_msg,
      [:@client, :server, :session] => [:items]
  end
end

module MonotoneCart
  include MonotoneCartProtocol

  state do
    lmap :sessions
  end

  bloom :on_action do
    sessions <= action_msg {|c| { c.session => CartLattice.new({c.reqid => [ACTION_OP, c.item, c.action]}) } }
  end

  bloom :on_checkout do
    sessions <= checkout_msg {|c| { c.session => CartLattice.new({c.reqid => [CHECKOUT_OP, c.lbound, c.client]}) } }
    response_msg <~ sessions {|s_id, c|
      c.sealed.when_true { [c.checkout_addr, ip_port, s_id, c.summary] }
    }
  end
end

class MonotoneReplica
  include Bud
  include MonotoneCart
end

class MonotoneClient
  include Bud
  include MonotoneCartProtocol

  state do
    table :serv, [] => [:addr]
    scratch :do_action, [:reqid] => [:item, :action]
    scratch :do_checkout, [:reqid] => [:lbound]
  end

  bloom do
    action_msg <~ (do_action * serv).pairs {|a,s| [s.addr, ip_port, 1, a.reqid, a.item, a.action]}
    checkout_msg <~ (do_checkout * serv).pairs {|c,s| [s.addr, ip_port, 1, c.reqid, c.lbound]}
    stdio <~ response_msg {|m| ["Response: #{m.inspect}"] }
  end
end

s = MonotoneReplica.new
s.run_bg
c = MonotoneClient.new
c.run_bg

c.sync_do {
  c.serv <+ [[s.ip_port]]
  c.do_checkout <+ [[7, 5]]
}

c.sync_do {
  c.do_action <+ [[5, 1, 1], [6, 2, 7]]
}

c.delta(:response_msg)
s.stop
c.stop
