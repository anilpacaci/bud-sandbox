require 'rubygems'
require 'test/unit'
require 'bfs/fs_master'
require 'bfs/datanode'
require 'bfs/hb_master'
require 'bfs/chunking'
require 'bfs/bfs_master'
require 'bfs/bfs_client'

module FSUtil
  include FSProtocol

  state {
    #table :remember_resp, fsret.keys => fsret.cols
    table :remember_resp, fsret.schema
    #table :rem_av, available.keys => available.cols
  }

  declare
  def remz
    remember_resp <= fsret.map{|r| puts "RET" or r}
    #rem_av <= available
  end
end

class FSC
  include Bud
  include KVSFS
  include FSUtil
end

class CFSC 
  include Bud
  include ChunkedKVSFS
  include HBMaster
  include BFSMasterServer
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
  def ntest_client
    dn = new_datanode(65432)
    dn2= new_datanode(65432)
    b = CFSC.new(:port => "65432", :visualize => 3)
    b.run_bg

    sleep 3

    s = BFSShell.new("localhost:65432")
    s.run_bg
    s.dispatch_command(["mkdir", "/foo"])
    s.dispatch_command(["mkdir", "/bar"])
    s.dispatch_command(["mkdir", "/baz"])
    s.dispatch_command(["mkdir", "/foo/bam"])
    s.dispatch_command(["create", "/peter"])

    s.dispatch_command(["append", "/peter"])
    s.dispatch_command(["ls", "/"])

    sleep 4

    b.sync_do {
      b.remember_resp.each do |r|
        puts "REM: #{r.inspect}"
      end
      
      b.kvstate.each{ |k| puts "kvstate: #{k.inspect}" }
    }

    sleep  4
  
  end

  def test_fsmaster
    b = FSC.new(:dump => true)
    b.run_bg
    do_basic_fs_tests(b)
    b.stop_bg
  end
  
  def new_datanode(master_port)
    dn = DN.new(:visualize => 3)
    dn.add_member <+ [["localhost:#{master_port}", 1]]
    dn.run_bg
    return dn
  end

  def ntest_addchunks
    dn = new_datanode(65432)
    dn2 = new_datanode(65432)

    b = CFSC.new(:port => "65432", :visualize => 3)
    b.run_bg
    sleep 5
    do_basic_fs_tests(b)

    puts "AOK"
    do_addchunks(b)

    #b.rem_av.each do |a|
    #  puts "AV: #{a.inspect}"
    #end 

    b.chunk.each do |a|
      puts "CC: #{a.inspect}"
    end 
  end

  def ntest_chunked_fsmaster
    dn = DN.new
    dn.add_member <+ [["localhost:65432"]]
    dn.run_bg

    dn2 = DN.new
    dn2.add_member <+ [["localhost:65432"]]
    dn2.run_bg

    b = CFSC.new(:port => 65432, :dump => true)
    b.run_bg
    sleep 5
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
    dn.stop_bg
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

  def test_datanode
    dn = DN.new(:dump => true)
    # paa
    #dn.add_member <+ [['localhost:45638']]
    #dn.run_bg
    #dn = new_datanode(45637)

    hbc = HBA.new(:port => 45637, :dump => true)
    hbc.run_bg
    hbc.sync_do {} 
    sleep 1

    puts "ahem, about to run datanode"
    dn.run_bg
    
    #dn.sync_do  {
    #  dn.payload.each{|p| puts "PL: #{p.inspect}" }
    #  dn.member.each{|m| puts "DNM: #{m.inspect}" } 
    #}

    puts "about to sync"
    
    hbc.sync_do {} 
      
    sleep 3

    puts "OK"

    hbc.sync_do {} 

    hbc.sync_do {
      hbc.last_heartbeat.each{|l| puts "LHB: #{l.inspect}" }
      hbc.chunk_cache.each{|l| puts "CH: #{l.inspect}" }
    }

    hbc.stop_bg
    #dn.stop_bg
  end
end

