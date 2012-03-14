# that these unit test batches should succeed individually
# but fail when run together as below is troublesome!

require 'test/tc_heartbeat'
require 'test/tc_ordering'
require 'test/tc_member'
require 'test/tc_voting'
require 'test/tc_timers'
require 'test/tc_assignment'
require 'test/tc_reliable_delivery'
require 'test/tc_besteffort_delivery'
require 'test/tc_kvs'
require 'test/tc_multicast'
require 'test/tc_carts'
require 'test/tc_demonic_delivery'
require 'test/tc_lamport'
require 'test/tc_bfs'
require 'test/tc_dastardly_delivery'

#require 'test/tc_chord'
#require 'test/tc_e2e_bfs'
#require 'test/tc_leader'
