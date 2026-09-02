#!/usr/bin/env bash
set -euo pipefail

TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=../scripts/common.sh disable=SC1091
source "$TEST_DIR/../scripts/common.sh"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

[[ "$(heap_to_megabytes 12G)" == 12288 ]] || fail "12G"
[[ "$(heap_to_megabytes 512m)" == 512 ]] || fail "512m"
[[ "$(heap_to_megabytes 2048)" == 2048 ]] || fail "2048"
heap_to_megabytes 12GB >/dev/null 2>&1 && fail "12GB accepted"
heap_to_megabytes abc >/dev/null 2>&1 && fail "abc accepted"

[[ "$(server_status_pid 'main: state=ready session=HOL pid=12345 up=42s idle conns=1')" == 12345 ]] || fail "pid"
server_status_pid 'no server' >/dev/null 2>&1 && fail "pid from no server"

[[ "$(sanitize_name 'My Project (2)')" == "my-project-2" ]] || fail "sanitize: $(sanitize_name 'My Project (2)')"
[[ "$(sanitize_name '!!!')" == "project" ]] || fail "sanitize empty"

# descendant_pids sees this shell's children.
sleep 30 &
child=$!
descendant_pids $$ | grep -qx "$child" || fail "descendant_pids missed child $child"
kill "$child"

echo "common.sh tests passed"
