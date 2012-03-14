require './test_common'
require 'kvs/mv_kvs'
require 'ordering/vector_clock'

class SingleSiteMVKVS
  include Bud
  include BasicMVKVS
end

class SingleSiteVCMVKVS
  include Bud
  include VC_MVKVS
end

class SingleSiteCausalMVKVS
  include Bud
  include Causal_MVKVS
end

class SingleSiteMR_MVKVS
  include Bud
  include MR_MVKVS
end

class SingleSiteRYW_MVKVS
  include Bud
  include RYW_MVKVS
end

class SingleSiteMW_MVKVS
  include Bud
  include MW_MVKVS
end

class TestMVKVS < Test::Unit::TestCase
  def test_simple
    v = SingleSiteMVKVS.new
    v.run_bg

    v.sync_do { v.kvput <+ [["testclient", "fookey", "v0", "req0", "foo"]] }
    v.sync_do { v.kvput <+ [["testclient", "fookey", "v1", "req1", "bar"]] }

    v.sync_do { v.kvget <+ [["req3", "testclient", "fookey", 2]] }
    v.sync_do {
      assert_equal(2, v.kvget_response.length)
      assert_equal([["req3", "fookey", "v0", "foo"], 
                    ["req3", "fookey", "v1", "bar"]], 
                   v.kvget_response.to_a.sort)
    }

    v.stop
  end

  def test_vector_mvkvs
    v = SingleSiteVCMVKVS.new
    vc = VectorClock.new
    v.run_bg

    v.sync_do { v.kvput <+ [["testclient", "fookey", vc, "req0", "foo"]] }
    v.sync_do { v.kvput <+ [["testclient", "fookey", vc, "req1", "bar"]] }
    v.sync_do { v.kvget <+ [["req3", "testclient", "fookey", vc]] }
    v.sync_do {
      assert_equal(2, v.kvget_response.length)
      resp = v.kvget_response.to_a.sort 
      #check that both values exist
      assert_equal(["bar", "foo"], resp.map { |r| r[3] }.sort)
      #check that vector clock values for testclient are set appropriately
      assert_equal([1,2], resp.map { |r| r[2]["testclient"] }.sort)
    }

    v.stop
  end

  def test_causal_mvkvs
    v = SingleSiteCausalMVKVS.new
    vc0 = VectorClock.new
    vc = VectorClock.new
    v.run_bg

    v.sync_do { v.kvput <+ [["testclient", "fookey", vc, "req0", "foo"]] }
    v.sync_do { v.kvput <+ [["testclient", "fookey", vc, "req1", "bar"]] }
    v.sync_do { v.kvget <+ [["req3", "testclient", "fookey", vc0]] }
    v.sync_do {
      assert_equal(2, v.kvget_response.length)
      resp = v.kvget_response.to_a.sort 
      #check that both values exist
      assert_equal(["bar", "foo"], resp.map { |r| r[3] }.sort)
      #check that vector clock values for testclient are set appropriately
      assert_equal([1,2], resp.map { |r| r[2]["testclient"] }.sort)
    }

    vc1 = VectorClock.new

    #an empty vector clock means every event is ahead of it!
    v.sync_do { v.kvget <+ [["req4", "testclient", "fookey", vc1]] }
    v.sync_do {
      assert_equal(2, v.kvget_response.length)
      resp = v.kvget_response.to_a.sort 
      #check that both values exist
      assert_equal(["bar", "foo"], resp.map { |r| r[3] }.sort)
      #check that vector clock values for testclient are set appropriately
      assert_equal([1,2], resp.map { |r| r[2]["testclient"] }.sort)
    }

    #make sure we obey strict monotonicity
    2.times{ vc1.increment("testclient") }

    v.sync_do { v.kvget <+ [["req6", "testclient", "fookey", vc1]] }
    v.sync_do {
      assert_equal(0, v.kvget_response.length)
    }

    5.times{ vc1.increment("testclient") }

    v.sync_do { v.kvget <+ [["req5", "testclient", "fookey", vc1]] }
    v.sync_do {
      assert_equal(0, v.kvget_response.length)
    }

    v.stop
  end

  def test_mr_mvkvs
    v = SingleSiteMR_MVKVS.new
    wc = VectorClock.new
    rc = VectorClock.new 
    v.run_bg

    #MR should behave like causal...
    v.sync_do { v.kvput <+ [["testclient", "fookey", wc, "req0", "foo"]] }
    v.sync_do { v.kvput <+ [["testclient", "fookey", wc, "req1", "bar"]] }
    v.sync_do { v.kvget <+ [["req3", "testclient", "fookey", rc]] }
    v.sync_do {
      assert_equal(2, v.kvget_response.length)
      resp = v.kvget_response.to_a.sort 
      #check that both values exist
      assert_equal(["bar", "foo"], resp.map { |r| r[3] }.sort)
      #check that vector clock values for testclient are set appropriately
      assert_equal([1,2], resp.map { |r| r[2]["testclient"] }.sort)
    }

    #...but it shouldn't be strictly monotonic (you can return the same value)
    rc1 = VectorClock.new
    2.times{ rc1.increment("testclient") }

    v.sync_do { v.kvget <+ [["req5", "testclient", "fookey", rc1]] }
    v.sync_do {
      assert_equal(1, v.kvget_response.length)
      assert_equal("bar", v.kvget_response.first.to_a[3])
    }

    v.stop
  end

  def test_ryw_mvkvs
    v = SingleSiteRYW_MVKVS.new
    wc = VectorClock.new
    v.run_bg

    v.sync_do { v.kvput <+ [["testclient", "fookey", wc, "req0", "foo"]] }
    v.sync_do { v.kvput <+ [["testclient", "fookey", wc, "req1", "bar"]] }
    v.sync_do { v.kvget <+ [["req3", "testclient", "fookey", wc]] }
    v.sync_do {
      assert_equal(1, v.kvget_response.length)
      resp = v.kvget_response.to_a.sort 
      #check that both values exist
      assert_equal(["bar"], resp.map { |r| r[3] }.sort)
      #check that vector clock values for testclient are set appropriately
      assert_equal([2], resp.map { |r| r[2]["testclient"] }.sort)
    }

    v.stop
  end

  def test_mw_mvkvs
    v = SingleSiteMW_MVKVS.new
    wc = VectorClock.new
    wc2 = VectorClock.new
    rc = VectorClock.new
    v.run_bg

    v.sync_do { v.kvput <+ [["testclient", "fookey", wc, "req0", "foo"]] }
    v.sync_do { v.kvput <+ [["testclient", "fookey", wc, "req1", "bar"]] }

    v.sync_do { v.kvget <+ [["req3", "testclient", "fookey", rc]] }
    v.sync_do {
      assert_equal(2, v.kvget_response.length)
      resp = v.kvget_response.to_a.sort 
      #check that both values exist
      assert_equal(["bar", "foo"], resp.map { |r| r[3] }.sort)
      #check that vector clock values for testclient are set appropriately
      assert_equal([1, 2], resp.map { |r| r[2]["testclient"] }.sort)
    }

    v.sync_do { v.kvput <+ [["testclient2", "fookey", wc2, "req1", "baz"]] }
    v.sync_do { v.kvput <+ [["testclient2", "fookey", wc2, "req1", "qux"]] }
    
    2.times { rc.increment("testclient") }

    v.sync_do { v.kvget <+ [["req4", "testclient", "fookey", rc]] }

    v.sync_do {
      assert_equal(3, v.kvget_response.length)
      resp = v.kvget_response.to_a.sort 
      assert_equal(["bar", "baz", "qux"], resp.map { |r| r[3] }.sort)
      assert_equal([-1, -1, 2], resp.map { |r| r[2]["testclient"] }.sort)
      assert_equal([-1, 1, 2], resp.map { |r| r[2]["testclient2"] }.sort)
    }

    2.times { rc.increment("testclient2") }

    v.sync_do { v.kvget <+ [["req5", "testclient", "fookey", rc]] }

    v.sync_do {
      assert_equal(2, v.kvget_response.length)
      resp = v.kvget_response.to_a.sort 
      assert_equal(["bar", "qux"], resp.map { |r| r[3] }.sort)
      assert_equal([-1, 2], resp.map { |r| r[2]["testclient"] }.sort)
      assert_equal([-1, 2], resp.map { |r| r[2]["testclient2"] }.sort)
    }

    v.stop
  end
end
