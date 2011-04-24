module MIProtocol
  state do
    # schema templates
    scratch :cd_template, [:@directory_id, :cache_id, :line_id]
    scratch :dc_template, [:@cache_id, :directory_id, :line_id]

    # channels shared by agents
    channel :cdq_REX, cd_template.schema
    # really, want to make :payload functionally dependent on the other 3 cols.
    channel :cdq_WBD, cd_template.schema.clone.push(:payload)
    channel :dcp_REXD, dc_template.schema.clone.push(:payload)
    channel :dcp_WBAK, dc_template.schema
    channel :dcp_NAK, dc_template.schema
    channel :dcq_INV, dc_template.schema
    channel :cdp_INVD, cd_template.schema.clone.push(:payload)

    # EDB/a priori truth
    # necessary for bootstrapping states of lines, caches.
    table :lines, [:line]
    table :caches, [:cache_id]
    table :directory, [:directory_id]
  end

  bootstrap do
    lines <= [
      [1],
      [2],
      [3],
      [4],
      [5],
      [6],
      [7]
    ];
    caches <= [
      ['a'],
      ['b'],
      ['c'],
      ['d'],
    ];
  end
end
