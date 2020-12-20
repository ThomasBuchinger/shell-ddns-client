
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
# Cloudflare IP & DDNS Provider
# =========================================================
function check_provider_cloudflare {
  check_binary 'curl'
  check_fn_exists 'provider_cloudflare_auth'
  check_fn_exists 'provider_cloudflare_zone_to_id'

  get_param "CF_DOMAIN" > /dev/null
  provider_cloudflare_auth > /dev/null
}
function ip_provider_cloudflare {
  local URL="https://1.1.1.1/cdn-cgi/trace"
  local ipv4=$(curl -s $URL | grep 'ip=' | cut -d '=' -f 2)
  echo "A=$ipv4"
}
function ddns_provider_cloudflare {
  local HOSTNAME=$1
  local IP=$2
  local REC_TYPE=$3
  local zone_name=$(get_param "CF_DOMAIN")
  if [ ${HOSTNAME} == "@" ]; then 
    local FQDN=${zone_name}
  else
    local FQDN="${HOSTNAME}.${zone_name}"
  fi

  if [ ${CF_ZONE_ID:-""} == "" ]; then
    CF_ZONE_ID=$(provider_cloudflare_zone_to_id $zone_name) || exit $?
  else
    log 3 "Using Cached ZONE_ID for $zone_name: $CF_ZONE_ID"
  fi
  echo "zone_id=$CF_ZONE_ID"
  echo "zone_name=$zone_name"
  echo "auth_info=$(provider_cloudflare_auth)"
  
  record_id=$(provider_cloudflare_name_to_id "${FQDN}" $CF_ZONE_ID) || exit $?
  echo "record_id=$record_id"

  update=$(provider_cloudflare_update_record $REC_TYPE "${FQDN}" $IP $CF_ZONE_ID $record_id ) || exit $?
  echo "success=true" 
}
function provider_cloudflare_name_to_id {
  local name=$1
  local zone_id=$2
  local CLOUDFLARE_ZONE_DNS_RECORDS_QUERY_API="https://api.cloudflare.com/client/v4/zones/${zone_id}/dns_records"  # GET

  record_list=$(provider_cloudflare_api "GET_RECORD ${name}" "${CLOUDFLARE_ZONE_DNS_RECORDS_QUERY_API}?per_page=50&name=${name}") || exit $?
  local id=$(extract_from "$record_list" "id" | head -1)
  echo ${id} 
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
  local post_data="{\"type\":\"${type}\",\"name\":\"${fqdn}\",\"content\":\"${ip}\",\"ttl\":120,\"proxied\":true}"

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
  for line in $(echo $DDNS_RESULT); do
    echo -e "  $line"
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
function extract_from {
  local data=$1
  local search_string=$2
  local match=$(echo $data | grep -o -P "\"$2\":\"?\K[^,].*?(?=\"?,)")
  log 3 "Matching grep pattern: \"$2\":\K[^,].*?(?=,) | Result $match"
  echo "$match"
}

# Generate (flat) json by key-value pairs
#
#function to_json {
#  echo '{'
#  for line in $1; do
#    key=$(echo $line | cut -d '=' -f 1)
#    value=$(echo $line | cut -d '=' -f 2)
#    echo "\"$ey\":\"$value\","
#  done
#  echo "}"
#}

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
