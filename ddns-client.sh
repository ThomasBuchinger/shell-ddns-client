# Cloudflare Provider
# includes an IP Provider and a DDNS Provider

# =========================================================
# Cloudflare IP Provider
# =========================================================
# Resolve Public IP with Cloudlares 1.1.1.1 DNS server
#
# Arguments: none
# Output: A=<public_ipv4_address>
function ip_cloudflare {
  local URL="https://1.1.1.1/cdn-cgi/trace"
  local ipv4=$(curl -s $URL | grep 'ip=' | cut -d '=' -f 2)
  echo "A=$ipv4"
}

# =========================================================
# Cloudflare DDNS Provider
# =========================================================
# Check if all necessary parameters are set. Exits if not
#
# Arguments: None
# Returns: Exits if something is missing
function check_ddns_cloudflare {
  check_binary 'curl'
  check_fn_exists 'provider_cloudflare_auth'
  check_fn_exists 'provider_cloudflare_zone_to_id'

  provider_cloudflare_auth > /dev/null
}

# Main Cloudflare DDNS update function
#
# Globals:
#   CF_ZONE_ID uuid of the domain in cloudflare. discovered automatically
# Arguments:
#   HOSTNAME name of the host to update
#   IP public IP address
#   REC_TYPE A or AAAA record
#   ZONE_NAME domain name
# Outputs: Key-Vlaue pairs with additional info
# Returns: non-zero exitcode on error
function ddns_cloudflare {
  local HOSTNAME=$1
  local IP=$2
  local REC_TYPE=$3
  local zone_name=$4
  local FQDN=$(host_to_fqdn $HOSTNAME $zone_name)

  if [ ${CF_ZONE_ID:-""} == "" ]; then
    CF_ZONE_ID=$(provider_cloudflare_zone_to_id $zone_name) || exit $?
  else
    log 3 "Using Cached ZONE_ID for $zone_name: $CF_ZONE_ID"
  fi
  echo "zone_id=$CF_ZONE_ID"
  echo "zone_name=$zone_name"
  echo "auth_info=$(provider_cloudflare_auth | tr ' ' '_')"
  
  output=$(provider_cloudflare_name_to_id "${FQDN}" $CF_ZONE_ID) || exit $?
  local record_id=$(extract_key "$output" "record_id")
  local current_ip=$(extract_key "$output" "current_ip")
  echo "record_id=$record_id"
  echo "old_ip=$current_ip"

  if [ $current_ip == $IP ]; then
    echo "update_needed=false"
    echo "success=true"
    exit 0
  fi


  update=$(provider_cloudflare_update_record $REC_TYPE "${FQDN}" $IP $CF_ZONE_ID $record_id ) || exit $?
  echo "update_needed=true"
  echo "success=true" 
}

# Resolve dns-record name to id used by cloudflare
#
# Argumnts:
#   NAME fqdn
#   ZONE_ID uuid of the zone
# Outputs: current_ip=<ip_address> record_id=<uuid>
function provider_cloudflare_name_to_id {
  local name=$1
  local zone_id=$2
  local CLOUDFLARE_ZONE_DNS_RECORDS_QUERY_API="https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records"  # GET

  record_list=$(provider_cloudflare_api "GET_RECORD ${name}" "${CLOUDFLARE_ZONE_DNS_RECORDS_QUERY_API}?per_page=50&name=${name}") || exit $?
  local ip=$(extract_from "$record_list" "content" | head -1)
  local id=$(extract_from "$record_list" "id" | head -1)
  echo "current_ip=${ip}"
  echo "record_id=${id}"
}

# Resolve domain to zone id used by cloudflare
#
# Arguments:
#   ZONE_NAME domain name
# Outputs: zones uuid
function provider_cloudflare_zone_to_id {
  local CLOUDFLARE_ZONE_QUERY_API='https://api.cloudflare.com/client/v4/zones'  # GET
  local zone_name=$1

  zone_list=$(provider_cloudflare_api "GET_ZONES ${zone_name}" "${CLOUDFLARE_ZONE_QUERY_API}?per_page=50&name=${zone_name}") || exit $?
  local id=$(extract_from "$zone_list" "id" | head -1)
  echo $id
}

# Perform the DDNS Update on cloudlares API
#
# Arguments:
#   TYPE A or AAAA record
#   FQDN fqdn of th host
#   IP public IP
#   ZONE zone uuid
#   RECORD record uuid
function provider_cloudflare_update_record {
  local type=$1
  local fqdn=$2
  local ip=$3
  local zone=$4
  local record=$5
  local CLOUDFLARE_ZONE_DNS_RECORDS_UPDATE_API="https://api.cloudflare.com/client/v4/zones/${zone}/dns_records/${record}"  # PATCH
  local post_data="{\"type\":\"${type}\",\"name\":\"${fqdn}\",\"content\":\"${ip}\",\"ttl\":120}"

  update=$(provider_cloudflare_post "UPDATE $fqdn" "$CLOUDFLARE_ZONE_DNS_RECORDS_UPDATE_API" "$post_data" "PATCH") || exit $?
}

# Perform API calls that send data
#
# Arguments:
#   ACTION_NAME human readable name of the performed operation (appears in logs)
#   URL URL to call
#   DATA data to send. Must be formatted
#   VERB(PATCH) http verb
#   CONTENT_TYPE(application/json) content-type header
# Outputs: Response body
# Returns: non-zero exitcode on curl error 
function provider_cloudflare_post {
  local action_name=$1
  local url=$2
  local data=$3

  local verb=${4:-PATCH}
  local content_type=${5:-application/json}

  log 3 "${action_name}:\ncurl -H '$(provider_cloudflare_auth)' -X $verb '$url' --data '${data}' -H 'Content-Type: $content_type'"
  local response=$(curl -s -H "$(provider_cloudflare_auth)" -X $verb "$url" --data "${data}" )
  log 3 "$response"

  local success=$(extract_from "$response" "success")
  if [ "$success" != "true" ]; then
    echo "$query_name: Reuest failed. success=$success" >&2
    exit 1
  fi
  echo "$response"
}

# Perform GET requests against cloudflare API
# Also checks i cloudlares returns more than 1 entry
#
# Argumets:
#   QUERY_NAME human readable name of the operation (appears in logs)
#   URL URL to call
# Outputs: Response body
# Returns: non-zero exitcode on curl error
function provider_cloudflare_api {
  local query_name=$1
  local url=$2

  log 3 "${query_name}:\ncurl -H '$(provider_cloudflare_auth)' '$url'"
  local response=$(curl -s -H "$(provider_cloudflare_auth)" "$url")
  log 3 "$response"

  local success=$(extract_from "$response" "success")
  local count=$(extract_from "$response" "count")

  if [ "$success" != "true" ]; then
    echo "$query_name: Reuest failed. success=$success" >&2
    exit 1
  elif [ $count -ne 1 ]; then 
    echo "$query_name: Wrong number of zones. count=$count" >&2
    exit 1
  fi
  echo "${response}" 
}

# translate AUTH information to curl params
# Exits if AUTH variables are not found in ENV
# 
# Globals:
#   DDNS_CF_AUTHTYPE token or key
#   DDNS_CF_TOKEN auth token for token authentication
#   DDNS_CF_APIUSER user for apikey authentication
#   DDNS_CF_APIKEY key for apikey authentication
# Outputs: curl parameters to authenticate with cloudflares api
# Returns: non-zero exitcode if no auth info is found
function provider_cloudflare_auth {
  local auth_type=$(get_param "CF_AUTHTYPE" "token")
  if [ $auth_type == "token"  ]; then
    get_param "CF_TOKEN" > /dev/null
    echo "Authorization: Bearer $(get_param "CF_TOKEN")"
  elif [ $auth_type == "key" ]; then
    get_param "CF_APIUSER" > /dev/null
    get_param "CF_APIKEY" > /dev/null
    echo "-H \"X-Auth-Email: $(get_param "CF_APIUSER")\" -H \"X-Auth-Key: $(get_param "CF_APIKEY")\""
  else
    exit_with_error 1 "Unsupported cloudflare auth_type: $auth_type"
  fi
}
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
# Reference IP & DDNS Provider
function check_provider {
  exit 0
}
function ip_provider_mock { 
  echo "A=1.2.3.4" # One or more IPv4 Addresses
  echo "AAAA=2001:db8::1" # One or more IPv6 Addresses 
}
function ddns_provider_mock {
  # $1...Record type (A or AAAA)
  # $2...IP address
  # $3...A or AAAA record
  # $4...Domain name
  echo "Eample=Key-Value-pairs-of-useful-information-regarding-the-ddns-update"
  exit 0
}
# This file contains all the functions used

# Prints a humanreadable summary of the DDNS updata
#
# Arguments:
#   NAME hostname (without domain) on which the DDNS update was performed
#   IP_ADDR the updated public IP
#   DDNS_RC exitcode oft the ddns update
#   REC_TYPE was it a A or AAAA DNS entry? (not used)
#   DDNS_RESULT list if key-value pairs with aditional info. 
#               key/value separated by '='. pairs seperated by space
# Outputs: human-readable result of DDNS update operation to LOG
function print_ddns_update {
  local NAME=$1
  local IP_ADDR=$2
  local REC_TYPE=$3
  local DDNS_RC=$4
  local SUCCESS=$( if [ $DDNS_RC -eq 0 ]; then echo success; else echo "error"; fi )
  local DDNS_RESULT=$5

  log 1 "Update $NAME with $IP_ADDR: $SUCCESS"
  for line in $DDNS_RESULT; do
    log 2 "  $line"
  done
}

# Check a commands RC and do nothing or exit
#
# Arguments:
#   $1 Exitcode at the command
#   $2 Error message
function exit_on_error {
  if [ $1 -ne 0 ]; then
    echo $2 >&2
    exit 2
  fi
}

# Print to STDERR
#
function err {
  echo -e "[$(date +'%Y-%m-%dT%H:%M:%S%z')]: $*" >&2
}

# Logging based on LOG_LEVEL
# Logging to STDERR because we often use STDOUT to pass data around and we do not want logs polluting it
#
function log {
  if [ $1 -le $LOG_LEVEL ]; then
    err $2
  fi 
}

# Get Parameter from Environment
# Return default or error if non-existent
#
# Arguments
#   NAME Name of the parameter (without DDNS_ prefix)
#   DEFAULT default value if NAME is not found
# Outputs: Value of NAME on STDOUT
function get_param {
  local name="DDNS_$1"
  local default=$2
  local value=$(eval "echo \$$name")

  if [ -z "$value" ] && [ -z "$default" ]; then 
    err "Parameter not found: $name" >&2
    exit 2
  fi
  echo ${value:-$default}
}

# Extract value from JSON string
#
# Known Issues:
# * Matches multiple entries if search_string is a substring of multiple keys
#
# Arguments:
#   DATA Json string of data. preferably not formatted
#   SEARCH_STRING key to look for
# Outputs: value of SEARCH_STRING, one per line
function extract_from {
  local data=$1
  local search_string=$2
  # REGEX:
  #              # Search 'search_string' with double quotes around it
  #                                  # colon, whitespaces and optional quote
  #                                         # \K discards everything until now from --only-matching output
  #                                               # capture value
  #                                                  # (?=) discard from --only-matching output
  #                                                     # End with comma, ] or } (and optional quote)
  local pattern="\"${search_string}\":\s*\"?\K[^,].*?(?=\"?[,\]\}])"
  local match=$(echo "$data" | grep --only-matching --perl-regexp $pattern)
  log 3 "Matching grep pattern: $pattern | Result $match"
  echo "$match"
}
# Extract value from Key-Value pairs
# Format: key/value separated by '='. pairs seperated by space
#
# Arguments:
#   DATA kv-pair string
#   KEY Name of the key
# Outputs: value of KEY, one per line
function extract_key {
  local data=$1
  local key=$2
  local pattern="^${key}=\K.*?$"
  local match=$(echo "$data" | grep --only-matching --perl-regexp $pattern )
  log 3 "Extracting: key=${key} value=${match}"
  echo $match
}

# Check if executable is in PATH. Exit if not
#
# Arguments:
#   $1 name of the executeable
function check_binary {
  which $1 > /dev/null 2>&1
  exit_on_error $? "Dependency not found: $1"
}

# Check is a function is defined. Exit if not
#
# Arguments:
#   $1 name of the function 
function check_fn_exists {
  local REQ_TYPE=${2:-function}
  LC_ALL=C type $1 2>&1 | grep -q "$REQ_TYPE"
  exit_on_error $? "$1 not found!"
}

# Resolve hostname to fqdn
# Mostly handles the special host @
#
# Globals:
#   DDNS_DOMAIN default domain if none is given
# Arguments:
#   HOST hostname without domain
#   DOMAIN domain name
function host_to_fqdn {
  local host=$1
  local zone_name=$2
  if [ -z ${zone_name} ]; then
    local zone_name=$(get_param "DOMAIN")
  fi

  if [ ${host} == "@" ]; then 
    local FQDN=${zone_name}
  else
    local FQDN="${host}.${zone_name}"
  fi
  echo $FQDN 
}

# Print help
#
# Output: Print all the help to STDOUT
function help {
  echo "Usage: DDNS_SOURCE=/path/to/parameters.env $0"
  echo ""
  echo "Supported ENV variables:"
  echo "  DDNS_MODE:        update: Update DDNS_HOSTNAMES using a provider"
  echo "                    check: Compare current DNS entry against current public ip"
  echo "                    lazy-update: Do a Check and perform a DDNS-Update if out-of-date"
  echo "                    help: print this message"
  echo "                    noop: May be used to include this script"
  echo "  DDNS_CONF         Execute config files as shell scripts to set ENV variables"
  echo "                    Defaults to $CONF_SEARCHPATH"
  echo "  DDNS_PROVIDER:    Select a supportd provider (currently only cloudflare)"
  echo "  DDNS_IP_PROVIDER: Select a supported public ip query service"
  echo "  DDNS_HOSTNAMES:   list of hostnames to update. Hostnames do not include the domain."
  echo "                    Using '@' updates the root of the domain"
  echo "                    Example: 'www api @'"
  echo "  DDNS_DOMAIN:      Your DDNS-Domain name"
  echo "  DDNS_QUERY:       Used only in check-mode. Compare ip address of a specific host (instead of all DDNS_HOSTNAMES"
  echo "  DDNS_LOG_LEVEL:   Change LogLevel: 0...No Logs, 1...Short Logs, 2...Detailed Logs, 3...Dump Debug info"
  echo "                    Note: All output happens on STDERR"
  echo ""
  echo "Provider Cloudflare (DDNS_PROVIDER=cloudflare):"
  echo "  DDNS_CF_AUTHTYPE: Use token or apikey authentication"
  echo "  DDNS_CF_TOKEN:    Token. Permissions nedded: All Zones Read, DNS Edit"
  echo "  DDNS_CF_APIUSER:  Cloudflare Username for apikey authentication"
  echo "  DDNS_CF_APIKEY:   Cloudflare API Key for apikey authentication"
}

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
