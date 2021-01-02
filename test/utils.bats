load "helper"
setup() {
  JSON_DATA='{"key1":"value1","key2": "value2", "nested":{"nkey3":"nested3", "nkey4": "nested4"},"last":"element"}'
  KV_DATA=$( echo "key1=value1"; echo "key2=value2"; echo "dup=duplicate1"; echo "dup=duplicate2")
  LOG_LEVEL=5
  DDNS_DOMAIN="bats.local"
}

# =================================================================================================
# print_ddns_update
# =================================================================================================
@test "print_ddns_update" {
  skip
}

# =================================================================================================
# exit_on_error
# =================================================================================================
@test "exit_on_error: skip on zero-rc" {
  run exit_on_error 0 "fatal error"
  [ "$status" -eq 0 ] 
  [ "$output" = "" ] 
}
@test "exit_on_error: exit on non-zero-rc and print error" {
  run exit_on_error 1 "fatal error"
  [ "$status" -eq 2 ] 
  [ "$output" = "fatal error" ] 
}

# =================================================================================================
# log
# =================================================================================================
@test "log: Print logs to stdout" {
  export LOG_LEVEL=3
  run log 1 "my message"
  [[ "$output" =~ $(logify "my message") ]] 
}
@test "log: No output for debug logs" {
  export LOG_LEVEL=3
  run log 5 "my message"
  [ "$output" = "" ] 
}

# =================================================================================================
# get_param
# =================================================================================================
@test "get_param: Finds Parameter" {
  export DDNS_PARAM1=hello
  run get_param "PARAM1"
  [ "$output" = "hello" ] 
}
@test "get_param: Finds Parameter, default does not break code" {
  export DDNS_PARAM1=hello
  run get_param "PARAM1" "default"
  [ "$output" = "hello" ]
} 
@test "get_param: Uses default if provided" {
  export DDNS_PARAM1=hello
  run get_param "PARAM2" "default"
  [ "$output" = "default" ]
}
@test "get_param: Exits if PARAM2 not defined" {
  export DDNS_PARAM1=hello
  run get_param "PARAM2"
  [ "$status" -eq 2 ]
  [[ "$output" =~ $(logify "Parameter not found: DDNS_PARAM2") ]]
} 

# =================================================================================================
# extract_from
# =================================================================================================
@test "extract_from: JSON without space" {
  output=$(extract_from "$JSON_DATA" "key1")
  echo "# DUMP $output"
  [ "$output" = "value1" ]
} 
@test "extract_from: last element in JSON" {
  output=$(extract_from "$JSON_DATA" "last")
  [ "$output" = "element" ]
}
@test "extract_from: JSON with space" {
  output=$(extract_from "$JSON_DATA" "key2")
  [ "$output" = "value2" ]
}
@test "extract_from: nested JSON without space" {
  output=$(extract_from "$JSON_DATA" "nkey3")
  [ "$output" = "nested3" ]
}
@test "extract_from: nested JSON with space" {
  output=$(extract_from "$JSON_DATA" "nkey4")
  [ "$output" = "nested4" ]
}

# =================================================================================================
# extract_key
# =================================================================================================
@test "extract_key: simple" {
  output=$(extract_key "$KV_DATA" "key1")
  [ "$output" = "value1" ]
}
@test "extract_key: duplicate" {
  output=$(extract_key "$KV_DATA" "dup")
  [ "$output" = "duplicate1 duplicate2" ]
}
@test "extract_key: non-existent" {
  output=$(extract_key "$KV_DATA" "notaKey")
  [ "$output" = "" ]
}

# =================================================================================================
# check_binary
# =================================================================================================
@test "check_binary: continue if executable is present (ls)" {
  run check_binary "ls"
  [ "$status" -eq 0 ] 
  [ "$output" = "" ]
}
@test "check_binary: fails in non-existent executable" {
  run check_binary "non-existent"
  [ "$status" -eq 2 ] 
  [ "$output" = "Dependency not found: non-existent" ]
}

# =================================================================================================
# check_fn_exists
# =================================================================================================
@test "check_fn_exists: continue if function is present" {
  function g { echo "hello world"; }
  run check_fn_exists "g"
  [ "$status" -eq 0 ] 
  [ "$output" = "" ]
}
@test "check_fn_exists: supports shell builtins" {
  run check_fn_exists "echo" "shell builtin"
  [ "$status" -eq 0 ] 
  [ "$output" = "" ]
}
@test "check_fn_exists: fails in non-existent function" {
  run check_fn_exists "non-existent"
  [ "$status" -eq 2 ] 
  [ "$output" = "non-existent not found!" ]
}

# =================================================================================================
# host_to_fqdn
# =================================================================================================
@test "host_to_fqdn: with name" {
  output=$(host_to_fqdn "name" "mydomain.local")
  [ "$output" = "name.mydomain.local" ] 
} 
@test "host_to_fqdn: using @ for root" {
  output=$(host_to_fqdn "@" "mydomain.local")
  [ "$output" = "mydomain.local" ] 
} 
@test "host_to_fqdn: defaulting to DDNS_DOMAIN parameter" {
  output=$(host_to_fqdn "name")
  [ "$output" = "name.bats.local" ] 
} 
