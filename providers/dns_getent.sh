# DNS Query provider getent
# getent executable is provided by glibc and should be available on all systems

# Resolve DNS name
#
# Arguments:
#   FQDN fqdn to query
#   REC_TYPE query only A or AAAA records
# Outputs: ip address
function query_getent {
  local fqdn=$1
  local rec_type=${2:-A}

  if [ $rec_type = "A" ]; then
    addr=$(getent ahostsv4 "$fqdn")
  elif [ $rec_type = "AAAA" ]; then
    addr=$(getent ahostsv6 "$fqdn")
  fi
  echo $addr | grep 'RAW' | cut -d ' ' -f 1
}
