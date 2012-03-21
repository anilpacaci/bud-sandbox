module CartWorkloads
  def simple_workload(program, client, nbeers=12)
    workload = [['meat', 1],
                ['books', -1],
                ['beer', 1],
                ['diapers', 1],
                ['meat', -1]]
    nbeers.times do |i|
      workload << ['beer', 1]
    end

    addr = program.ip_port
    workload.each do |w|
      client.sync_do {
        client.client_action <+ [[addr, 1234, gen_seq] + w]
      }
    end

    do_checkout(program, client, 1234, [["beer", nbeers + 1], ["diapers", 1]])
  end

  def multi_session_workload(program, client)
    cart1 = [['remedy', 1], ['sightglass', 2], ['cole', -1]]
    cart2 = [['blue bottle', 1], ['cole', 1]]

    addr = program.ip_port
    cart1 = cart1.map {|c| [addr, 555, gen_seq] + c}
    cart2 = cart2.map {|c| [addr, 666, gen_seq] + c}
    (cart1 + cart2).each do |c|
      client.sync_do {
        client.client_action <+ [c]
      }
    end

    do_checkout(program, client, 666, [["blue bottle", 1], ["cole", 1]])
    do_checkout(program, client, 555, [["remedy", 1], ["sightglass", 2]])
  end

  def do_checkout(program, client, session_id, expected)
    client.sync_callback(:client_checkout, [[program.ip_port, session_id, gen_seq]],
                         :client_response)

    client.sync_do {
      assert_equal([[client.ip_port, program.ip_port, session_id, expected]],
                   client.memo.reject {|m| m.session != session_id}.to_a)
    }
  end

  def gen_seq
    @seq ||= 0
    @seq += 1
  end
end
