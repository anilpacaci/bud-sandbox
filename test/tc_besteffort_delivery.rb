require 'rubygems'
require 'test/unit'
require 'bud'
require 'delivery/delivery'

class BED < Bud
  include BestEffortDelivery
  
  def state
    super
    table :pipe_perm, ['dst', 'src', 'ident', 'payload']
  end 

  declare
  def lcl_process
    pipe_perm <= pipe_sent
  end
end

class TestBEDelivery < Test::Unit::TestCase

  def test_besteffort_delivery
    rd = BED.new("localhost", 11116, {'dump' => true})
    sendtup = ['localhost:11116', 'localhost:11115', 1, 'foobar']
    rd.pipe_in <+ [ sendtup ]
    rd.run_bg
    sleep 1
    assert_equal(1, rd.pipe_perm.length)
    assert_equal(sendtup, rd.pipe_perm.first)
  end
end
