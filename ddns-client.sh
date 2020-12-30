
# =========================================================
# Cloudflare IP Provider
# =========================================================
function ip_cloudflare {
  local URL="https://1.1.1.1/cdn-cgi/trace"
  local ipv4=$(curl -s $URL | grep 'ip=' | cut -d '=' -f 2)
  echo "A=$ipv4"
}

# =========================================================
# Cloudflare DDNS Provider
# =========================================================
function check_ddns_cloudflare {
  check_binary 'curl'
  check_fn_exists 'provider_cloudflare_auth'
  check_fn_exists 'provider_cloudflare_zone_to_id'

  provider_cloudflare_auth > /dev/null
}
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
  echo "auth_info=$(provider_cloudflare_auth | tr ' ' '-')"
  
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

function provider_cloudflare_zone_to_id {
  local CLOUDFLARE_ZONE_QUERY_API='https://api.cloudflare.com/client/v4/zones'  # GET
  local zone_name=$1

  zone_list=$(provider_cloudflare_api "GET_ZONES ${zone_name}" "${CLOUDFLARE_ZONE_QUERY_API}?per_page=50&name=${zone_name}") || exit $?
  local id=$(extract_from "$zone_list" "id" | head -1)
  echo $id
}

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

function provider_cloudflare_post {
  local action_name=$1
  local url=$2
  local data=$3

  local verb=${4:-PATCH}
  local content_type=${5:-application/json}

  log 3 "${action_name}:\ncurl -H '$(provider_cloudflare_auth)' -X $verb '$url' --data '${data}' -H 'Content-Type: $content_type'"
  local response=$(curl -s -H "$(provider_cloudflare_auth)" -X $verb "$url" --data "${data}" )
  log 3 "$response"
  if [ "$success" == "false" ]; then
    echo "$query_name: Reuest failed. success=$success" >&2
    exit 1
  fi
  echo "$response"
}

function provider_cloudflare_api {
  local query_name=$1
  local url=$2

  log 3 "${query_name}:\ncurl -H '$(provider_cloudflare_auth)' '$url'"
  local response=$(curl -s -H "$(provider_cloudflare_auth)" "$url")
  log 3 "$response"

  local success=$(extract_from "$response" "success")
  local count=$(extract_from "$response" "count")

  if [ "$success" == "false" ]; then
    echo "$query_name: Reuest failed. success=$success" >&2
    exit 1
  elif [ $count -ne 1 ]; then 
    echo "$query_name: Wrong number of zones. count=$count" >&2
    exit 1
  fi
  echo "${response}" 
}

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

# Query DNS using dig
#
function query_dig {
  local fqdn=$1
  local rec_type=${2:-A}
  echo $(dig +short -t $rec_type $fqdn)
}


# =========================================================
# Reference IP & DDNS Provider
# =========================================================
function check_provider {
  return 0
}
function ip_provider_mock { 
  echo "A=1.2.3.4" # One or more IPv4 Addresses
  echo "AAAA=2001:db8::1" # One or more IPv6 Addresses 
}
function ddns_provider_mock {
  # $1...Record type (A or AAAA)
  # $2...IP address
  echo "Eample=Key-Value pairs of useful information regarding the ddns update"
  return 0
}
# =========================================================
# Script validation and utility functions
# =========================================================

# Prints a humanreadable summary of the DDNS updata
#
function print_ddns_update {
  local NAME=$1
  local IP_ADDR=$2
  local REC_TYPE=$3
  local DDNS_RC=$4
  local SUCCESS=$( if [ $DDNS_RC -eq 0 ]; then echo success; else echo "error"; fi )
  local DDNS_RESULT=$5

  log 1 "Update $NAME with $IP_ADDR: $SUCCESS"
  for line in $DDNS_RESULT; do
    echo "  $line"
  done
}

# Check a commands RC and do nothing or exit
#
function exit_on_error {
  if [ $1 -ne 0 ]; then
    echo $2 >&2
    exit 1
  fi
}

# Logging based on LOG_LEVEL
#
function log {
  if [ $1 -le $LOG_LEVEL ]; then
    echo -e "$2" >&2
  fi 
}

# Get Parameter from Environment
# Return default or error if non-existent
#
function get_param {
  local name="DDNS_$1"
  local default=$2
  local value=$(eval "echo \$$name")

  if [ -z "$value" ] && [ -z "$default" ]; then 
    echo  "Parameter not found: $name" >&2
    exit 1
  fi
  echo ${value:-$default}
}

# Extract value from JSON string
#
# Known Issues:
# * Matches multiple entries if search_string is a substring of multiple keys
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
function extract_key {
  local data=$1
  local key=$2
  local pattern="^${key}=\K.*?$"
  local match=$(echo "$data" | grep --only-matching --perl-regexp $pattern )
  log 3 "Extracting: key=${key} value=${match}"
  echo $match
}

# Check if executable is in PATH
#
function check_binary {
  which $1 > /dev/null 2>&1
  exit_on_error $? "Dependency not found: $1"
}

# Check is a function is defined
#
function check_fn_exists {
  local REQ_TYPE=${2:-function}
  LC_ALL=C type $1 2>&1 | grep -q "$REQ_TYPE"
  exit_on_error $? "$1 not found!"
}

# Resolve hostname to fqdn
# Mostly handles the special host @
#
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

# Print all the help
#
function help {
  echo "Usage: DDNS_SOURCE=/path/to/parameters.env $0"
  echo ""
  echo "Supported ENV variables:"
  echo "  DDNS_MODE:        update-now: Update DDNS_HOSTNAMES using a provider"
  echo "                    check: Compare current DNS entry against current public ip"
  echo "                    lazy-update: Do a Check and perform a DDNS-Update if out-of-date"
  echo "                    help: print this message"
  echo "                    noop: May be used to include this script"
  echo "  DDNS_SOURCE       source a file for ENV varaiables"
  echo "  DDNS_PROVIDER:    Select a supportd provider (currently only cloudflare)"
  echo "  DDNS_IP_PROVIDER: Select a supported public ip query service"
  echo "  DDNS_HOSTNAMES:   list of hostnames to update. Hostnames do not include the domain."
  echo "                    Using '@' updates the root of the domain"
  echo "                    Example: 'www api @'"
  echo "  DDNS_DOMAIN:      Your DDNS-Domain name"
  echo "  DDNS_QUERY:       Used only in check-mode. Compare ip address of a specific host (instead of all DDNS_HOSTNAMES"
  echo "  DDNS_LOG_LEVEL:   Change LogLevel: 0...No Logs, 1...Short Logs, 2...Detailed Logs, 3...Dump Debug info"
  echo ""
  echo "Provider Cloudflare (DDNS_PROVIDER=cloudflare):"
  echo "  DDNS_CF_AUTHTYPE: Use token or apikey authentication"
  echo "  DDNS_CF_TOKEN:    Token. Permissions nedded: All Zones Read, DNS Edit"
  echo "  DDNS_CF_APIUSER:  Cloudflare Username for apikey authentication"
  echo "  DDNS_CF_APIKEY:   Cloudflare API Key for apikey authentication"
}

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
