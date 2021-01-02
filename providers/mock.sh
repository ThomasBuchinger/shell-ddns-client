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
