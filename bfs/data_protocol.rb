CHUNKSIZE = 100000
DATADIR = '/tmp/bloomfs'


class DataProtocolClient
  # useful things:
  # get a chunk (memory) from a filehandle
  # create / continue a pipeline
  # fetch a chunk from the local fs.
  
  def DataProtocolClient::chunk_from_fh(fh)
    return fh.read(CHUNKSIZE)
  end

  def DataProtocolClient::send_replicate(chunkid, target, owner)
    args = ["replicate", chunkid, target]
    host, port = owner.split(":")
    begin
      s = TCPSocket.open(host, port)
      s.puts(args.join(","))
      s.close
      return
    rescue
      puts "(connect #{host}:#{port})EXCEPTION ON READ: #{$!}"
    end 
    raise "No datanodes"   
  end

  def DataProtocolClient::read_chunk(chunkid, nodelist)
    nodelist.each do |node|
      args = ["read", chunkid]
      host, port = node.split(":")
      begin
        s = TCPSocket.open(host, port)
        s.puts(args.join(","))
        ret = s.read(CHUNKSIZE)
        s.close
        return ret
      rescue
        puts "(connect #{host}:#{port})EXCEPTION ON READ: #{$!}"
        # go around the loop again.
      end
    end 
    raise "No datanodes"   
  end

  def DataProtocolClient::send_stream(chunkid, prefs, chunk)
    copy = prefs.clone
    first = copy.shift
    host, port = first.split(":")
    copy.unshift(chunkid)
    copy.unshift "pipeline"
    s = TCPSocket.open(host, port)
    s.puts(copy.join(","))
    if chunk.nil?
      s.close
      return false
    else
      s.write(chunk)
      s.close
      return true
    end
  end
end


class DataProtocolServer
  # request types:
  # 1: pipeline.  chunkid, preflist, stream, to_go
  #   - the idea behind to_go is that |preflist| > necessary copies,
  #     but to_go decremements at each successful hop
  # 2: read. chunkid.  send back chunk data from local FS.
  # 3: replicate.  chunkid, preflist. be a client, send local data to another datanode.

  def initialize(port)
    @dir = "#{DATADIR}/#{port}"
    @q = Queue.new
    @q.push false
    Dir.mkdir(DATADIR) unless File.directory? DATADIR
    Dir.mkdir(@dir) unless File.directory? @dir
    start_datanode_server(port)
  end

  def start_datanode_server(port)
    Thread.new do
      @dn_server = TCPServer.open(port)
      loop {
        client = @dn_server.accept
        Thread.new do
          header = dispatch_dn(client)
          client.close
        end
        next if conditional_continue
      }
      puts "OUT OF LOOP"
    end
  end
  
  def conditional_continue
    ret = @q.pop
    if ret
      begin
        @dn_server.close
      rescue
        puts "STOP FAILURE #{$!}"
      end
    end
    @q.push false
    return ret
  end

  def dispatch_dn(cli)
    header = cli.gets.chomp
    elems = header.split(",")
    type = elems.shift
    chunkid = elems.shift
    case type
      when "pipeline" 
        do_pipeline(chunkid, elems, cli)
      when "read"
        do_read(chunkid, cli)
      when "replicate"
        do_replicate(chunkid, elems, cli)
    end
  end

  def do_pipeline(chunkid, preflist, cli)
    chunkfile = File.open("#{@dir}/#{chunkid.to_i.to_s}", "w")
    data = cli.read(CHUNKSIZE)
    chunkfile.write data
    chunkfile.close
    
    # synchronous for now...
    if preflist.length > 0
      DataProtocolClient.send_stream(chunkid, preflist, data)
    end
    cli.close
  end
  
  def do_read(chunkid, cli)
    begin
      fp = File.open("#{@dir}/#{chunkid.to_s}", "r")
      chunk = fp.read(CHUNKSIZE)
      fp.close
      cli.write(chunk)
      cli.close
    rescue
      puts "FILE NOT FOUND: *#{chunkid}* (error #{$!})"
      puts "try to ls #{@dir}"
      cli.close
    end
  end

  def do_replicate(chunk, target, cli)
    cli.close
    begin
      fp = File.open("#{@dir}/#{chunk}", "r")
      DataProtocolClient.send_stream(chunk, target, DataProtocolClient.chunk_from_fh(fp))
      fp.close
    rescue
      puts "FAIL: #{$!}"
    end
  end

  def stop_server
    @q.pop
    @q.push true
  end
end
