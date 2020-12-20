load 'helper'
#@setup() {
#  echo "DDNS_MODE=mymode" > file_to_source
#  echo "echo hello world" >> "file_to_source"
#}
#@teardown() {
#  rm "${BATS_TMPDIR}/file_to_source"
#}

@test "main: Unknown mode is unknown" {
  export DDNS_MODE=mymode
  run sh main.sh
  [ "$status" -eq 0 ]
  [ "$output" = "Unknown mode: mymode" ]
}
@test "main: Can source files" {
  skip
  export DDNS_SOURCE="file_to_source"
  export DDNS_MODE=mymode
  run sh main.sh
  ls >&2
  [ "$status" -eq 0 ]
  [ "$output" = "hello world\nUnknown mode: mymode" ]
}

@test "main: Runs update-now with mocks" {
  skip
  export DDNS_IP_PROVIDER=mock
  export DDNS_PROVIDER=mock
  run sh main.sh
  [ "$status" -eq 0 ]
  [ "$output" = "Unknown mode: mymode" ]
}
