require 'rubygems'
require 'bud'
require 'bud/rendezvous'
require 'test/unit'
require 'test/cart_workloads'
require 'cart/disorderly_cart'
require 'cart/destructive_cart'


module Remember
  state do
    table :memo, [:client, :server, :session, :array]
  end

  bloom :memm do
    memo <= response_msg
  end
end


class BCS
  include Bud
  include BestEffortMulticast
  include ReplicatedDisorderlyCart
  include CartClient
  include Remember
end


class DCR
  include Bud
  include CartClientProtocol
  include CartClient
  include CartProtocol
  include DestructiveCart
  include ReplicatedKVS
  include BestEffortMulticast
  include Remember
end

class DummyDC
  include Bud
  include CartClientProtocol
  include CartClient
  include CartProtocol
  include DestructiveCart
  include BasicKVS
  include Remember

  state do
    table :members, [:peer]
  end
end

class BCSC
  include Bud
  include CartClient

  state do
    table :cli_resp_mem, [:@client, :server, :session, :item, :cnt]
  end

  bloom :memmy do
    cli_resp_mem <= response_msg
  end
end

class TestCart < Test::Unit::TestCase
  include CartWorkloads

  def test_replicated_destructive_cart
    prog = DCR.new(:port => 53525, :trace => true)
    cart_test(prog)
  end

  def ntest_destructive_cart
    prog = DummyDC.new(:port => 32575)
    cart_test(prog)
  end

  def test_disorderly_cart
    program = BCS.new(:port => 23765)
    cart_test(program)
  end

  def cart_test(program)
    #program = BCS.new(:port => 23765)
    addy = "#{program.ip}:#{program.port}"
    add_members(program, addy)
    program.run_bg
    run_cart(program)
    sleep 1
    program.sync_do{}
    program.sync_do{
      assert_equal(1, program.memo.length)
      #program.memo.each {|m| puts "MEMO: #{m.inspect}" }
      assert_equal(4, program.memo.first.array.length)
    }
    program.stop_bg
  end

  def add_members(b, *hosts)
    hosts.each do |h|
      assert_nothing_raised(RuntimeError) { b.add_member <+ [[h]] }
    end
  end
end
