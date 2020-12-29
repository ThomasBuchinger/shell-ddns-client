
# Query DNS using dig
#
function query_dig {
  local fqdn=$1
  local rec_type=${2:-A}
  echo $(dig +short -t $rec_type $fqdn)
}

