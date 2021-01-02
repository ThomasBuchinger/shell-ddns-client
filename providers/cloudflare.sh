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
