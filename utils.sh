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

