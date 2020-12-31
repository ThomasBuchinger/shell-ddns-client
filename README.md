# Shell DDNS Client
This is a DDNS client with minimal requirements.
* posix-compatible shell (tested with bash on Fedora)
* `glibc` or `dig` for DNS queries
* `curl` for API calls (raise an issue if you need `wget` support)

## Usage
* Download the ddns-client.sh script and make it executeable
* Set required parameters as ENV variable ([see here](#Reference))
* Run script

## Providers
#### DDNS Updates
* Cloudflare: Update IPs ind Cloudflares DNS API
#### Query Public IP
* Cloudflare (default): Using Cloudflares 1.1.1.1 DNS Server
#### Query DNS
* getent (default): Part of glibc
* dig

## Reference
> :information_source: **Note**: All parameters must be set as ENV variables. There are no CLI-Arguments

General Parameters:
Name | Description
---|---
DDNS_MODE | **lazy-update**: check first, update only when required<br>**update-now**: Perform DDNS Update<br>**check**: Check if DDNS update is required<br>**help** (default): print help<br>**noop**: Do nothing. Allows script includes
DDNS_SOURCE | Source/Read a file at startup. Useful for exporting parameters
DDNS_LOG_LEVEL | 0...Only Fatal Errors<br>1...Info: Log important steps<br>2...Debug1: Log human-readable debug info<br>3...Debug2: Everything, including dumps 
DDNS_IP_PROVIDER | Set Public-IP-Query-Service
DDNS_PROVIDER | DDNS_SERVICE
DDNS_HOSTNAMES | List of hostnames (no domain) to update
DDNS_DOMAIN | Your domain
DDNS_QUERY | Query spcific DNS entry (must be FQDN) to check if DDNS-update is required.

Cloudflare (DDNS_PROVIDER=cloudflare):
Name | Description
---|---
DDNS_CF_AUTHTYPE | Use token or key authentication"
DDNS_CF_TOKEN | Token. Permissions nedded: All Zones Read, DNS Edit"
DDNS_CF_APIUSER | Cloudflare Username for apikey authentication"
DDNS_CF_APIKEY | Cloudflare API Key for apikey authentication"


## Testing
We are using [BASH Automated Testing System](https://github.com/bats-core/bats-core).

```bash
# Make executable
make

# Run Tests
make test
```
