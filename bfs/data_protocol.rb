CHUNKSIZE = 100000
DATADIR = '/tmp/bloomfs'


class DataProtocolClient
  # useful things:
  # get a chunk (memory) from a filehandle
  # create / continue a pipeline
  # fetch a chunk from the local fs.
  
  def chunk_from_fh(fh)
    return fh.read(CHUNKSIZE)
  end

  def send_header()
    
  end

  def DataProtocolClient::read_chunk(chunkid, nodelist)
  
    puts "OH CHUNKID IS *#{chunkid}*"
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
        puts "EXCEPTION ON READ: #{$!}"
        # go around the loop again.
      end
    end 
    raise "No datanodes"   
  end

  
  def DataProtocolClient::send_stream(chunkid, prefs, fh)
    copy = prefs.clone
    first = copy.shift
    host, port = first.split(":")
    copy.unshift(chunkid)
    copy.unshift "pipeline"
    s = TCPSocket.open(host, port)
    s.puts(copy.join(","))
    chunk = fh.read(CHUNKSIZE)
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
    Dir.mkdir(DATADIR) unless File.directory? DATADIR 
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
      }
    end
  end

  def dispatch_dn(cli)
    header = cli.gets.chomp
    elems = header.split(",")
    type = elems.shift
    chunkid = elems.shift
    case type
      when "pipeline" then do_pipeline(chunkid, elems, cli)
      when "read" then do_read(chunkid, cli)
      when "replicate" then do_replicate(chunkid, elems, cli)
    end
  end

  def do_pipeline(chunkid, preflist, cli)
    puts "PIPELINE"
    puts "chunkid is #{chunkid}"
    chunkfile = File.open("#{DATADIR}/#{chunkid.to_i.to_s}", "w")
    data = cli.read(CHUNKSIZE)
    #puts "write data #{data}"
    chunkfile.write data
    chunkfile.close
  end
  
  def do_read(chunkid, cli)
    begin
      fp = File.open("#{DATADIR}/#{chunkid.to_s}", "r")
      chunk = fp.read(CHUNKSIZE)
      fp.close
      cli.write(chunk)
      cli.close
      puts "DONE WRITE"
    rescue
      puts "FILE NOT FOUND: *#{chunkid}* (error #{$!})"
      puts "try to ls #{DATADIR}"
      cli.close
    end
  end

  def stop_server
    # unsafe, unsage
    @dn_server.close
  end
end
