load "helper"


@test "exit_on_error: skip on zero-rc" {
  run exit_on_error 0 "fatal error"
  [ "$status" -eq 0 ] 
  [ "$output" = "" ] 
}
@test "exit_on_error: exit on non-zero-rc and print error" {
  run exit_on_error 1 "fatal error"
  [ "$status" -eq 1 ] 
  [ "$output" = "fatal error" ] 
}

@test "log: Print logs to stdout" {
  export LOG_LEVEL=3
  run log 1 "my message"
  [ "$output" = "my message" ] 
}
@test "log: No output for debug logs" {
  export LOG_LEVEL=3
  run log 5 "my message"
  [ "$output" = "" ] 
}

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
@test "get_param: Exists if PARAM2 not defined" {
  export DDNS_PARAM1=hello
  run get_param "PARAM2"
  [ "$status" -eq 1 ]
  [ "$output" = "Parameter not found: DDNS_PARAM2" ]
} 


@test "check_binary: continue if executable is present (ls)" {
  run check_binary "ls"
  [ "$status" -eq 0 ] 
  [ "$output" = "" ]
}
@test "check_binary: fails in non-existent executable" {
  run check_binary "non-existent"
  [ "$status" -eq 1 ] 
  [ "$output" = "Dependency not found: non-existent" ]
}


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
  [ "$status" -eq 1 ] 
  [ "$output" = "non-existent not found!" ]
}
