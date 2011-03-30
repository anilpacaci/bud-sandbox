require 'rubygems'
require 'bud'
require 'bfs/data_protocol'
require 'bfs/bfs_config'

# Background processes for the BFS master.  Right now, this is just firing off
# replication requests for chunks whose replication factor is too low.
module BFSBackgroundTasks
  state do
    interface output, :copy_chunk, [:chunkid, :owner, :newreplica]
    periodic :bg_timer, (MASTER_DUTY_CYCLE * 5)
    scratch :chunk_cnts_chunk, [:chunkid, :replicas]
    scratch :chunk_cnts_host, [:host, :chunks]
    scratch :candidate_nodes, [:chunkid, :host, :chunks]
    scratch :best_dest, [:chunkid, :host]
    scratch :chosen_dest, [:chunkid, :host]
    scratch :sources, [:chunkid, :host]
    scratch :best_src, [:chunkid, :host]

    scratch :cc_demand, chunk_cache.schema
  end

  bloom :replication do
    #cc_demand <= join([bg_timer, chunk_cache]).map {|t, c| puts "DEMAND"; c}
    stdio <~ bg_timer { ["DEMAND OVER #{chunk_cache.length} items"] }

    chunk_cnts_chunk <= cc_demand.group([cc_demand.chunkid], count(cc_demand.node))
    chunk_cnts_host <= cc_demand.group([cc_demand.node], count(cc_demand.chunkid))

    temp :danger <= join([bg_timer, chunk_cnts_chunk, cc_demand, chunk_cnts_host], [cc_demand.node, chunk_cnts_host.host])
    candidate_nodes <= danger.map do |t, ccc, cc, cch|
      if ccc.replicas < REP_FACTOR
        unless cc_demand.map{|c| c.node if c.chunkid == ccc.chunkid}.include?  cc.node
          [ccc.chunkid, cc.node, cch.chunks]
        end
      end
    end

    best_dest <= candidate_nodes.argagg(:min, [candidate_nodes.chunkid], candidate_nodes.chunks)
    chosen_dest <= best_dest.group([best_dest.chunkid], choose(best_dest.host))
    sources <= join([cc_demand, candidate_nodes], [cc_demand.chunkid, candidate_nodes.chunkid]).map{|c, cn| [c.chunkid, c.node]}
    best_src <= sources.group([sources.chunkid], choose(sources.host))
    copy_chunk <= join([chosen_dest, best_src], [chosen_dest.chunkid, best_src.chunkid]).map do |d, s|
      [d.chunkid, s.host, d.host]
    end
  end
end
