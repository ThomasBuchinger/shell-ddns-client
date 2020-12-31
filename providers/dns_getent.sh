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
