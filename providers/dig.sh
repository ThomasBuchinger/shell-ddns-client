# DNS Query Provider using dig

# Query DNS using dig
#
# Arguments:
#   FQDN fqdn to query
#   REC_TYPE query only A or AAAA records
# Outputs: ip address
function query_dig {
  local fqdn=$1
  local rec_type=${2:-A}
  echo $(dig +short -t $rec_type $fqdn)
}

