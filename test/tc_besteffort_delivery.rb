require 'rubygems'
require 'test/unit'
require 'bud'
require 'delivery/delivery'

class BED < Bud
  include BestEffortDelivery
  
  def state
    super
    table :pipe_chan_perm, [:dst, :src, :ident, :payload]
    table :pipe_sent_perm, [:dst, :src, :ident, :payload]
  end 

  declare
  def lcl_process
    pipe_sent_perm <= pipe_sent
    pipe_chan_perm <= pipe_chan
  end
end

class TestBEDelivery < Test::Unit::TestCase

  def test_besteffort_delivery
    rd = BED.new(:visualize => 3)
    sendtup = ['localhost:11116', 'localhost:11115', 1, 'foobar']
    rd.run_bg
    rd.sync_do{ rd.pipe_in <+ [ sendtup ] }
    sleep 1
    rd.sync_do {
      assert_equal(1, rd.pipe_sent_perm.length)
      assert_equal(sendtup, rd.pipe_sent_perm.first)
    }
    rd.stop_bg
  end
    
  def test_delivery
    bd = BED.new
    rcv = BED.new(:port => 12345)
    bd.run_bg
    rcv.run_bg
    bd.sync_do { bd.pipe_in <+  [['localhost:12345', nil, 1, 'foobar']] }
    sleep 2

    rcv.sync_do {
      assert_equal(1, rcv.pipe_chan_perm.length)
      assert_equal(sendtup, rd.pipe_chan_perm.first)
    }
    rd.stop_bg
    rcv.stop_bg
  end
end
