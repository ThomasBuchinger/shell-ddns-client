# Bash DDNS Client
This is a posix-shell compatible implementation of a DDNS client.

## Usage
* Download the ddns-client.sh script and make it executeable
* Check [Reference-Section](#Reference) for required Parameters.
  At least DDNS_PROVIDER must be configured
* Run script

## Providers
* mock (default)
* Cloudflare

## Reference
General Parameters:
Name | Default | Description
---|---|---
DDNS_MODE | update-now | Support for multiple modes. Not yet used
DDNS_SOURCE | - | Source another file before running. Mostly to set parameters (or to add more providers)
DDNS_LOG_LEVEL | 0 | Change log level:
* 0 Only Fatal Errors
* 1 Info: Log important steps
* 2 Debug1: Log human-readable debug ino
* 3 Debug2: Everything, including dumps 
DDNS_IP_PROVIDER | cloudflare | Set Public-IP-Query Service
DDNS_PROVIDER | mock | DDNS Service  

Cloudflare:
Name | default | Description
DDNS_CF_TOKEN | - | API_TOKEN for cloudflare

## Testing
We are using [BASH Automated Testing System](https://github.com/bats-core/bats-core).

```bash
# Make executable
make

# Run Tests
make test
```
