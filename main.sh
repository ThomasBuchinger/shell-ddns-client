# =========================================================
# Variables
# =========================================================
SOURCE=${DDNS_SOURCE:-}                     # Source additional files
if [ ! -z "$SOURCE" ]; then 
  source $SOURCE
fi

MODE=${DDNS_MODE:-help}                            # Change Script mode
LOG_LEVEL=${DDNS_LOG_LEVEL:-1}                     # 0...Silent to 3...Debug
IP_PROVIDER=${DDNS_IP_PROVIDER:-cloudflare}        # Where to query the public IP
DDNS_PROVIDER=${DDNS_PROVIDER:-mock}               # DDNS provider to update
DNS_QUERY_PROVIDER=${DDNS_DNS_QUERY_PROVIDER:-dig} # How to query DNS (for check)

# =========================================================
# Main Functions
# =========================================================

# Update DDNS record
function update_now {
  check_binary 'curl'
  check_binary 'grep'
  check_binary 'tr'
  check_fn_exists "ip_${IP_PROVIDER}"
  get_param "HOSTNAMES" > /dev/null
  get_param "DOMAIN" > /dev/null
  check_ddns_${DDNS_PROVIDER} || exit $?

  # Get public IP
  log 2 "Using IP provider: ${IP_PROVIDER}"
  PUBLIC_IP=$("ip_${IP_PROVIDER}")
  for IP in $PUBLIC_IP; do
    log 2 "Public IP is: $IP"
  done

  # Update DDNS provider (one host/ip-type at a time)
  local DOMAIN=$(get_param "DOMAIN")
  for IP in $PUBLIC_IP;  do
    local REC_TYPE=$(echo $IP | cut -d '=' -f 1)
    local IP_ADDR=$(echo $IP | cut -d '=' -f 2)
    
    for HOST in $(get_param "HOSTNAMES"); do
      DDNS_RESULT=$(ddns_${DDNS_PROVIDER} $HOST $IP_ADDR $REC_TYPE $DOMAIN)
      DDNS_RC=$?
      print_ddns_update $HOST $IP_ADDR $REC_TYPE $DDNS_RC "$DDNS_RESULT"
    done
  done
}

#Check if update is needed
function check {
  local query_prog=$DNS_QUERY_PROVIDER
  check_binary $query_prog
  check_fn_exists "query_${query_prog}"
  check_fn_exists "ip_${IP_PROVIDER}"

  # Get public IP
  log 2 "Using IP provider: ${IP_PROVIDER}"
  PUBLIC_IP=$("ip_${IP_PROVIDER}")
  for IP in $PUBLIC_IP; do
    log 2 "Public IP is: $IP"
  done

  # Query current IPs
  local query_results=""
  QUERY_HOST=$(get_param "QUERY" "")
  for IP in $PUBLIC_IP;  do
    local REC_TYPE=$(echo $IP | cut -d '=' -f 1)
    local IP_ADDR=$(echo $IP | cut -d '=' -f 2)

    if [ ! -z ${QUERY_HOST} ]; then
      log 3 "Query $QUERY_HOST in DNS"
      dns_ip=$(query_${query_prog} "${QUERY_HOST}" $REC_TYPE)
      log 2 "Queried $QUERY_HOST in DNS: public_ip=$IP_ADDR dns=$dns_ip"
      query_results="${query_results} $QUERY_HOST=$IP_ADDR=$dns_ip"
    else
      get_param "HOSTNAMES" > /dev/null
      get_param "DOMAIN" > /dev/null
      for HOST in $(get_param "HOSTNAMES"); do
	local fqdn=$(host_to_fqdn $HOST) # host_to_fqdn can query the domain itself 
        log 3 "Query $fqdn in DNS"
        dns_ip=$(query_${query_prog} "${fqdn}" $REC_TYPE)
        log 2 "Queried $fqdn in DNS: public_ip=$IP_ADDR dns=$dns_ip"
        query_results="${query_results} $fqdn=$IP_ADDR=$dns_ip"
      done
    fi
  done

  # Print result
  local message=""
  for entry in $query_results; do
    name=$(echo $entry | cut -d '=' -f 1)
    public_ip=$(echo $entry | cut -d '=' -f 2)
    dns_ip=$(echo $entry | cut -d '=' -f 3)
    if [ $public_ip != $dns_ip ]; then
      message="${message}Host $name out-of-date: dns_ip=$dns_ip public_ip=$public_ip\n"
    fi
  done
  log 1 "$message"
  if [ "$message" = "" ]; then exit 0; else exit 2; fi
}
function lazy_update {
  $(check)
  local check_rc=$?
  if [ $check_rc -eq 0 ]; then
    log 2 "IP up-to-date. Nothing to do."
  elif [ $check_rc -eq 2 ]; then
    log 2 "IP out-of-date. Performing DDNS Update"
  else
    log 2 "Error during Check"
  fi

  update_now
  local update_rc=$?
}

case ${MODE} in
  update-now) update_now ;;
  check) check ;;
  lazy-update) lazy_update ;;
  help) help ;;
  noop) ;;
  *) echo "Unknown mode: ${MODE}. Use DDNS_MODE=help to print help"; ;;
esac
