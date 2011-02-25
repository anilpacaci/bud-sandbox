require 'rubygems'
require 'test/unit'
require 'digest/md5'
require 'bfs/fs_master'
require 'bfs/datanode'
require 'bfs/hb_master'
require 'bfs/chunking'
require 'bfs/bfs_master'
require 'bfs/bfs_client'
require 'bfs/background'

TEST_FILE='/usr/share/dict/words'
#TEST_FILE="HBA_rewritten.txt"

module FSUtil
  include FSProtocol

  state {
    table :remember_resp, fsret.key_cols => fsret.cols
  }

  declare
  def remz
    remember_resp <= fsret
    #rem_av <= available
  end
end

class FSC
  include Bud
  include KVSFS
  include FSUtil
end

class CFSC

  # the completely composed BFS
  include Bud
  include ChunkedKVSFS
  include HBMaster
  include BFSMasterServer
  include BFSBackgroundTasks
  include StaticMembership
  include FSUtil
end


class DN
  include Bud
  include BFSDatanode
end

class HBA
  include Bud
  #include HeartbeatAgent
  include HBMaster
  include StaticMembership
  # PAA
  #include FSUtil
  #include ChunkedKVSFS
  #include BFSMasterServer
end

class TestBFS < Test::Unit::TestCase
  def ntest_directorystuff1
    b = CFSC.new(:port => "65432", :visualize => 3)
    b.run_bg
    s = BFSShell.new("localhost:65432")
    s.run_bg

    s.dispatch_command(["mkdir", "/foo"])
    s.dispatch_command(["mkdir", "/bar"])
    s.dispatch_command(["mkdir", "/baz"])


    s.dispatch_command(["mkdir", "/foo/1"])
    s.dispatch_command(["mkdir", "/foo/1/2"])
    s.dispatch_command(["mkdir", "/foo/1/2/3"])


    s.dispatch_command(["create", "/bar/f1"])
    s.dispatch_command(["create", "/bar/f2"])
    s.dispatch_command(["create", "/bar/f3"])
    s.dispatch_command(["create", "/bar/f4"])
    s.dispatch_command(["create", "/bar/f5"])
    s.dispatch_command(["create", "/foo/1/2/3/nugget"])

    b.sync_do { b.kvstate.each {|k| puts "BACKEDN: #{k.inspect}" } }


    one = s.dispatch_command(["ls", "/"])
    assert_equal(["foo", "bar", "baz"], one)
    two = s.dispatch_command(["ls", "/foo"])
    puts "two is #{two.inspect}"
    assert_equal(["1"], two)
    three = s.dispatch_command(["ls", "/bar"])
    puts "TIME IS #{b.budtime}"
    assert_equal(["f1", "f2", "f3", "f4", "f5"], three)
    four = s.dispatch_command(["ls", "/foo/1/2"])
    assert_equal(["3"], four)

    dump_internal_state(b)
    b.stop_bg
    s.stop_bg
  end

  def md5_of(name)
    Digest::MD5.hexdigest(File.read(name))
  end
    
  def test_client
    b = CFSC.new(:port => "65433")#, :visualize => 3)
    b.run_bg
    dn = new_datanode(11117, 65433)
    dn2= new_datanode(11118, 65433)
    sleep 2


    s = BFSShell.new("localhost:65433")
    s.run_bg

    s.dispatch_command(["mkdir", "/foo"])
    s.dispatch_command(["mkdir", "/bar"])
    s.dispatch_command(["mkdir", "/baz"])
    s.sync_do{}
    s.dispatch_command(["mkdir", "/foo/bam"])
    s.dispatch_command(["create", "/peter"])

    s.sync_do{}
    rd = File.open(TEST_FILE, "r")
    s.dispatch_command(["append", "/peter"], rd)
    rd.close  

    s.sync_do{}

    s.dispatch_command(["ls", "/"])
    file = "/tmp/bfstest_"  + (1 + rand(1000)).to_s
    fp = File.open(file, "w")
    s.dispatch_command(["read", "/peter"], fp)
    fp.close
   
    assert_equal(md5_of(TEST_FILE), md5_of(file)) 
    
    #dump_internal_state(b)
    dn.stop_datanode

    # failover
    file = "/tmp/bfstest_"  + (1 + rand(1000)).to_s
    fp = File.open(file, "w")
    s.dispatch_command(["read", "/peter"], fp)
    fp.close
    assert_equal(md5_of(TEST_FILE), md5_of(file)) 

    dn2.stop_datanode


    assert_raise(RuntimeError) {s.dispatch_command(["read", "/peter"], fp)}

    # resurrect a datanode and its state
    dn3 = new_datanode(11117, 65433)
    # and an amnesiac
    dn4 = new_datanode(11119, 65433)
    sleep 3

    file = "/tmp/bfstest_"  + (1 + rand(1000)).to_s
    fp = File.open(file, "w")
    s.dispatch_command(["read", "/peter"], fp)
    fp.close
    assert_equal(md5_of(TEST_FILE), md5_of(file)) 

    # kill the memory node
    dn3.stop_datanode

    # and run off the replica
    
    
    file = "/tmp/bfstest_"  + (1 + rand(1000)).to_s
    fp = File.open(file, "w")
    s.dispatch_command(["read", "/peter"], fp)
    fp.close
    assert_equal(md5_of(TEST_FILE), md5_of(file)) 


    s.stop_bg
    b.stop_bg
  
  end
  
  def dump_internal_state(rt)
    rt.sync_do {
      rt.remember_resp.each do |r|
        puts "REM: #{r.inspect}"
      end
      
      rt.kvstate.each{ |k| puts "kvstate: #{k.inspect}" }
    }
  end

  def ntest_fsmaster
    b = FSC.new(:dump => true)
    b.run_bg
    do_basic_fs_tests(b)
    b.stop_bg
  end
  
  def new_datanode(dp, master_port)
    dn = DN.new(dp, {:visualize => 3})
    dn.add_member <+ [["localhost:#{master_port}", 1]]
    dn.run_bg
    return dn
  end

  def ntest_addchunks
    dn = new_datanode(11112, 65432)
    #dn2 = new_datanode(11113, 65432)

    b = CFSC.new(:port => "65432")#, :visualize => 3)
    b.run_bg
    #sleep 5
    do_basic_fs_tests(b)
    do_addchunks(b)

    b.chunk.each do |a|
      puts "CC: #{a.inspect}"
    end 
    dn.stop_datanode
    #dn2.stop_bg
    b.stop_bg
  end

  def nnnnnntest_chunked_fsmaster
    dn = new_datanode(11114, 65432)
    dn2 = new_datanode(11115, 65432)
    b = CFSC.new(:port => 65432, :dump => true)
    b.run_bg
    sleep 3
    do_basic_fs_tests(b)
    b.sync_do {  b.fschunklocations <+ [[654, 1, 1]] }
    sleep 1
    b.sync_do { 
      b.chunk_cache.each{|c| puts "CHUNK: #{c.inspect}" } 
      b.remember_resp.each do |r| 
        puts "CHYBKRET: #{r.inspect}" 
        if r.reqid == 654
          assert(r.status, "command failed")
          assert_equal(2, r.data.length)
        end
      end
    }
    b.stop_bg
    dn.stop_datanode
    dn2.stop_bg
  end

  def assert_resp(inst, reqid, data)
    inst.sync_do {
      inst.remember_resp.each do |r|
        if r.reqid == reqid
          assert(r.status, "call #{reqid} should have succeeded with #{data}.  Instead: #{r.inspect}")
          assert_equal(data, r.data)
        end
      end
    }
  end

  def do_addchunks(b)
    c1 = addchunk(b, "/foo", 5678)
    c2 = addchunk(b, "/foo", 6789)
    c3 = addchunk(b, "/foo", 67891)
    c4 = addchunk(b, "/foo", 67892)
    puts "I got #{c1.inspect}, #{c2.inspect}, #{c3.inspect}, #{c4.inspect} "
  end

  def addchunk(b, name, id)
    b.sync_do{ b.fsaddchunk <+ [[id, name]] }
   
    chunkid = nil
    b.sync_do {
      b.remember_resp.each do |r|
        if r.reqid == id
          chunkid = r.data
        end
      end
    }
    return chunkid
  end     

  def do_basic_fs_tests(b)

    b.sync_do{ b.fscreate <+ [[3425, 'foo', '/']] } 
    puts "UM"
    assert_resp(b, 3425, nil)

    puts "YAY"
    b.sync_do{ b.fsls <+ [[123, '/']] }
    assert_resp(b, 123, ["foo"])

    b.sync_do{ b.fscreate <+ [[3426, 'bar', '/']] } 
    assert_resp(b, 3426, nil)

    b.sync_do{ b.fsls <+ [[124, '/']] }
    assert_resp(b, 124, ["foo", "bar"])


    b.sync_do{ b.fsmkdir <+ [[234, 'sub1', '/']] }
    assert_resp(b, 234, nil)
    b.sync_do{ b.fsmkdir <+ [[235, 'sub2', '/']] }
    assert_resp(b, 235, nil)
    
    b.sync_do{ b.fsmkdir <+ [[236, 'subsub1', '/sub1']] }
    assert_resp(b, 236, nil)
    b.sync_do{ b.fsmkdir <+ [[237, 'subsub2', '/sub2']] }
    assert_resp(b, 237, nil)

    b.sync_do{ b.fsls <+ [[125, '/']] }
    assert_resp(b, 125, ["foo", "bar", "sub1", "sub2"])
    b.sync_do{ b.fsls <+ [[126, '/sub1']] }
    assert_resp(b, 126, ["subsub1"])
  end

  def ntest_datanode
    dn = new_datanode(11116, 45637)

    dn.run_bg

    hbc = HBA.new(:port => 45637, :dump => true)
    hbc.run_bg
    hbc.sync_do {} 


    sleep 5
  
    puts "OK"
    
    #dn.sync_do  {
    #  dn.payload.each{|p| puts "PL: #{p.inspect}" }
    #  dn.member.each{|m| puts "DNM: #{m.inspect}" } 
    #}

    hbc.sync_do {
      hbc.chunk_cache.each{|c| puts "CC: #{c.inspect}" } 
      assert_equal(1, hbc.chunk_cache.length)
      #hbc.last_heartbeat.each{|l| puts "LHB: #{l.inspect}" }
      #hbc.chunk_cache.each{|l| puts "CH: #{l.inspect}" }
    }

    hbc.stop_bg
    dn.stop_datanode
  end
end

