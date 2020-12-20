#!/bin/bash


# =========================================================
# Variables
# =========================================================
SOURCE=${DDNS_SOURCE:-}                     # Source additional files
if [ ! -z "$SOURCE" ]; then 
  source $SOURCE
fi

MODE=${DDNS_MODE:-update-now}               # Change Script mode
LOG_LEVEL=${DDNS_LOG_LEVEL:-1}              # 0...Silent to 3...Debug
IP_PROVIDER=${DDNS_IP_PROVIDER:-cloudflare} # Where to query the public IP
DDNS_PROVIDER=${DDNS_PROVIDER:-mock}        # DDNS provider to update

# =========================================================
# Main program
# =========================================================

# Update DDNS record
function update_now {
  check_binary 'curl'
  check_binary 'grep'
  check_binary 'tr'
  check_fn_exists "ip_provider_${IP_PROVIDER}"
  get_param "HOSTNAMES" > /dev/null
  check_provider_${DDNS_PROVIDER} || exit $?

  # Get public IP
  log 2 "Using IP provider: ${IP_PROVIDER}"
  PUBLIC_IP=$("ip_provider_${IP_PROVIDER}")
  for IP in $PUBLIC_IP; do
    log 2 "Public IP is: $IP"
  done

  # Update Cloudflare
  for IP in $PUBLIC_IP;  do
    local REC_TYPE=$(echo $IP | cut -d '=' -f 1)
    local IP_ADDR=$(echo $IP | cut -d '=' -f 2)
    
    for HOST in $(get_param "HOSTNAMES"); do
      # TODO: ddns_prodiver call cannot fail...
      DDNS_RESULT=$(ddns_provider_${DDNS_PROVIDER} $HOST $IP_ADDR $REC_TYPE)
      DDNS_RC=$?
      echo $DDNS_RESULT
      print_ddns_update $HOST $IP_ADDR $REC_TYPE $DDNS_RC $DDNS_RESULT
    done
  done
}

case $MODE in
  update-now) update_now ;;
  *) echo "Unknown mode: $MODE"; ;;
esac
