# The scripts logic lives here.
# This file contains the scripts setup (config and variables) and the top level function or each mode
# shellcheck shell=sh
# TODO Remove 'local' because it is not in posix 
# shellcheck disable=SC2039

# =========================================================
# Variables
# =========================================================
CONF_SEARCHPATH='/etc/shell-ddns.d/*:/etc/shell-ddns.env:~/.shell-ddns.d/*:/shell-ddns.env:./shell-ddns.d/*:./shell-ddns.env'
LOG_LEVEL=${DDNS_LOG_LEVEL:-1}             # Check log-level first, to figure out if we want to log sourcing the config
conf=${DDNS_CONF:-$CONF_SEARCHPATH}   # Set searchpath for config files

IFS=':'
for src in $(echo "$conf"); do
  if [ -f ${src} ]; then
    log 3 "Reading ${src}"
    source ${src}
  fi
done
unset IFS

MODE=${DDNS_MODE:-help}                               # Change Script mode
LOG_LEVEL=${DDNS_LOG_LEVEL:-1}                        # Reread log-level, because we now have the final config
                                                      # 0...Silent to 3...Debug
IP_PROVIDER=${DDNS_IP_PROVIDER:-cloudflare}           # Where to query the public IP
DDNS_PROVIDER=${DDNS_PROVIDER:-mock}                  # DDNS provider to update
DNS_QUERY_PROVIDER=${DDNS_DNS_QUERY_PROVIDER:-getent} # How to query DNS (for check)

# =========================================================
# Main Functions
# =========================================================

# Update DDNS record
update() {
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
  for ip in ${PUBLIC_IP}; do
    log 2 "Public IP is: ${ip}"
  done

  # Update DDNS provider (one host/ip-type at a time)
  local DOMAIN=$(get_param "DOMAIN")
  for ip in ${PUBLIC_IP};  do
    local REC_TYPE=$(echo "${ip}" | cut -d '=' -f 1)
    local IP_ADDR=$(echo "${ip}" | cut -d '=' -f 2)
    
    for HOST in $(get_param "HOSTNAMES"); do
      DDNS_RESULT=$(ddns_${DDNS_PROVIDER} "${HOST}" "${IP_ADDR}" "${REC_TYPE}" "${DOMAIN}")
      DDNS_RC=$?
      print_ddns_update "${HOST}" "${IP_ADDR}" "${REC_TYPE}" ${DDNS_RC} "${DDNS_RESULT}"
    done
  done
}

#Check if update is needed
check() {
  local query_prog="${DNS_QUERY_PROVIDER}"
  check_binary "${query_prog}"
  check_fn_exists "query_${query_prog}"
  check_fn_exists "ip_${IP_PROVIDER}"

  # Get public IP
  log 2 "Using IP provider: ${IP_PROVIDER}"
  PUBLIC_IP=$("ip_${IP_PROVIDER}")
  for ip in $PUBLIC_IP; do
    log 2 "Public IP is: ${ip}"
  done

  # Query current IPs
  local query_results=""
  QUERY_HOST=$(get_param "QUERY" "NA")
  for ip in $PUBLIC_IP;  do
    local REC_TYPE=$(echo "${ip}" | cut -d '=' -f 1)
    local IP_ADDR=$(echo "${ip}" | cut -d '=' -f 2)

    if [ "${QUERY_HOST}" != "NA" ]; then
      log 3 "Query ${QUERY_HOST} in DNS"
      dns_ip=$(query_${query_prog} "${QUERY_HOST}" "${REC_TYPE}")
      log 2 "Queried ${QUERY_HOST} in DNS: public_ip=${IP_ADDR} dns=${dns_ip}"
      query_results="${query_results} ${QUERY_HOST}=${IP_ADDR}=${dns_ip}"
    else
      get_param "HOSTNAMES" > /dev/null
      get_param "DOMAIN" > /dev/null
      for HOST in $(get_param "HOSTNAMES"); do
	local fqdn=$(host_to_fqdn "${HOST}") # host_to_fqdn can query the domain itself 
        log 3 "Query ${fqdn} in DNS"
        dns_ip=$(query_${query_prog} "${fqdn}" "${REC_TYPE}")
        log 2 "Queried ${fqdn} in DNS: public_ip=${IP_ADDR} dns=${dns_ip}"
        query_results="${query_results} ${fqdn}=${IP_ADDR}=${dns_ip}"
      done
    fi
  done

  # Print result
  local outdated_hosts=""
  for entry in ${query_results}; do
    name=$(echo "${entry}" | cut -d '=' -f 1)
    public_ip=$(echo "${entry}" | cut -d '=' -f 2)
    dns_ip=$(echo "${entry}" | cut -d '=' -f 3)
    if [ "$public_ip" != "$dns_ip" ]; then
      log 1 "Host ${name} out-of-date: dns_ip=${dns_ip} public_ip=${public_ip}"
      outdated_hosts="${outdated_hosts}host=${name} dns_ip=${dns_ip} public_ip=${public_ip};"
    fi
  done
  if [ "$outdated_hosts" = "" ]; then exit 0; else exit 2; fi
}
lazy_update() {
  # TODO: handle function returns vs exit better. it works but is really ugly
  # shellcheck disable=SC2091
  $(check > /dev/null) 
  local check_rc=$?
  if [ $check_rc -eq 0 ]; then
    log 1 "IP up-to-date. Nothing to do."
    exit 0
  elif [ $check_rc -eq 2 ]; then
    log 1 "IP out-of-date. Performing DDNS Update"
  else
    exit_on_error 1 "Error during Check"
  fi

  update
  local update_rc=$?
  exit $update_rc
}

log 2 "Using mode: $MODE"
case ${MODE} in
  update) update ;;
  check) check ;;
  lazy-update) lazy_update ;;
  help) help ;;
  noop) ;;
  *) exit_on_error 1 "Unknown mode: ${MODE}. Use DDNS_MODE=help to print help"; ;;
esac
