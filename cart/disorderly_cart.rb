require 'rubygems'
require 'bud'

require 'delivery/multicast'
require 'cart/cart_protocol'

module DisorderlyCart
  include CartProtocol

  state do
    table :cart_action, [:session, :reqid] => [:item, :action]
    scratch :action_cnt, [:session, :item, :action] => [:cnt]
    scratch :status, [:server, :client, :session, :item] => [:cnt]
  end

  bloom :saved do
    # store actions against the "cart;" that is, the session.
    cart_action <= action_msg { |c| [c.session, c.reqid, c.item, c.action] }
    temp :checkout_actions <= (checkout_msg * cart_action).rights
    action_cnt <= checkout_actions.group([cart_action.session, cart_action.item, cart_action.action], count(cart_action.reqid))
  end

  bloom :consider do
    status <= (action_cnt * action_cnt * checkout_msg).combos do |a1, a2, c|
      if a1.session == a2.session and a1.item == a2.item and a1.session == c.session and a1.action == "Add" and a2.action == "Del"
        if (a1.cnt - a2.cnt) > 0
          [c.client, c.server, a1.session, a1.item, a1.cnt - a2.cnt]
        end
      end
    end
    status <= (action_cnt * checkout_msg).pairs do |a, c|
      if a.action == "Add" and not action_cnt.map{|d| d.item if d.action == "Del"}.include? a.item
        [c.client, c.server, a.session, a.item, a.cnt]
      end
    end

    temp :out <= (status.reduce({}) do |memo, i|
      memo[[i[0],i[1],i[2]]] ||= []
      i[4].times do
        memo[[i[0],i[1],i[2]]] << i[3]
      end
      memo
    end).to_a

    response_msg <~ out do |k, v|
      k << v
    end
  end
end

module ReplicatedDisorderlyCart
  include DisorderlyCart
  include Multicast

  bloom :replicate do
    send_mcast <= action_msg {|a| [a.reqid, [a.session, a.reqid, a.item, a.action]]}
    cart_action <= mcast_done {|m| m.payload}
    cart_action <= pipe_out {|c| c.payload}
  end
end
