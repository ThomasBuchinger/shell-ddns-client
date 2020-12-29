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

function help {
  echo "Usage: DDNS_SOURCE=/path/to/parameters.env $0"
  echo ""
  echo "Supported ENV variables:"
  echo "  DDNS_MODE:        update-now: Update DDNS_HOSTNAMES using a provider"
#  echo "                    check: Compare current DNS entry against current public ip"
  echo "                    help: print this message"
  echo "                    noop: May be used to include this script"
  echo "  DDNS_SOURCE       source a file for ENV varaiables"
  echo "  DDNS_PROVIDER:    Select a supportd provider (currently only cloudflare)"
  echo "  DDNS_IP_PROVIDER: Select a supported public ip query service"
  echo "  DDNS_HOSTNAMES:   list of hostnames to update. Hostnames do not include the domain."
  echo "                    Using '@' updates the root of the domain"
  echo "                    Example: 'www api @'"
  echo "  DDNS_DOMAIN:      Your DDNS-Domain name"
#  echo "  DDNS_QUERY:       Used only in check-mode. Compare ip address of a specific host (instead of all DDNS_HOSTNAMES"
  echo "  DDNS_LOGLEVEL:    Change LogLevel: 0...No Logs, 1...Short Logs, 2...Detailed Logs, 3...Dump Debug info"
  echo ""
  echo "Provider Cloudflare (DDNS_PROVIDER=cloudflare):"
  echo "  DDNS_CF_AUTHTYPE: Use token or apikey authentication"
  echo "  DDNS_CF_TOKEN:    Token. Permissions nedded: All Zones Read, DNS Edit"
  echo "  DDNS_CF_APIUSER:  Cloudflare Username for apikey authentication"
  echo "  DDNS_CF_APIKEY:   Cloudflare API Key for apikey authentication"
}

