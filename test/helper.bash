loggify() {
  whitespace='[[:blank:]]'
  log_prefix='\[.+\]:[[:blank:]]'
  echo "${log_prefix}$*" | tr ' ' '[[:blank:]]'
}
source "utils.sh"
