#!/usr/bin/env bats

# Copyright (c) 2022 - for information on the respective copyright owner
# see the NOTICE file or the repository
# https://github.com/boschresearch/shellmock
#
# Licensed under the Apache License, Version 2.0 (the "License"); you may not
# use this file except in compliance with the License. You may obtain a copy of
# the License at
#
#   http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
# WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
# License for the specific language governing permissions and limitations under
# the License.

setup_file() {
  # Ensure we use the minimum required bats version and fail with a nice error
  # if not.
  bats_require_minimum_version 1.5.0
}

setup() {
  root="$(git rev-parse --show-toplevel)"
  load ../shellmock
  # shellcheck disable=SC2086 # We want to perform word splitting here.
  set ${TEST_OPTS-"--"}
}

@test "auto-detection of forgotten assertions" {
  # Clear shellmock's own RETURN trap. Instead, we call the trap manually for
  # these tests. There is no way to tell bats that this test function is
  # supposed to fail inside its RETURN trap.
  trap -- - RETURN
  shellmock global-config setval ensure-assertions 1
  shellmock new my_exe
  shellmock config my_exe 0
  my_exe
  local stderr
  if stderr=$(__SHELLMOCK_TESTING_TRAP=1 __shellmock_internal_trap 2>&1); then
    echo >&2 "Expected manual trap call to fail."
    exit 1
  fi
  [[ ${stderr} == *"ERROR: expectations for mock my_exe have not been asserted."* ]]
}

@test "asserting expectations works" {
  trap -- - RETURN
  shellmock global-config setval ensure-assertions 1
  shellmock new my_exe
  shellmock config my_exe 0
  my_exe
  shellmock assert expectations my_exe
  __SHELLMOCK_TESTING_TRAP=1 __shellmock_internal_trap
}

@test "deactivating auto-detection of forgotten assertions does not error out" {
  trap -- - RETURN
  shellmock global-config setval ensure-assertions 0
  shellmock new my_exe
  shellmock config my_exe 0
  my_exe
  __SHELLMOCK_TESTING_TRAP=1 __shellmock_internal_trap
}

@test "changing the RETURN trap is detected" {
  # Clear the RETURN trap set by shellmock, triggering the warning.
  trap -- - RETURN
  stderr="$(__shellmock_internal_trapcheck 2>&1)"
  echo "${stderr}"
  [[ ${stderr} == "WARNING: RETURN trap has changed since loading shellmock"* ]]
}

@test "an empty trap is overwritten" {
  trap -- - RETURN
  __shellmock_internal_init
  [[ -n $(trap -p -- RETURN) ]]
}

@test "an existing RETURN trap is kept" {
  trap "echo some trap" RETURN
  __shellmock_internal_init
  [[ $(trap -p -- RETURN) == "trap -- 'echo some trap' RETURN" ]]
  trap -- - RETURN
}

@test "not setting a trap outside of bats" {
  trap -- - RETURN
  tmpdir="${BATS_TEST_TMPDIR}"
  TMPDIR="${tmpdir}" BATS_TEST_TMPDIR="" __shellmock_internal_init
  [[ -z $(trap -p -- RETURN) ]]
}

_join() {
  local sep=$1
  shift
  (
    IFS="${sep}"
    echo "$*"
  )
}

@test "finding executables in shell code" {
  run -0 --separate-stderr shellmock commands << 'EOF'
echo "Built-ins are not detected."
if which bash; then
  echo "Arguments that happen to be commands are not detected."
fi
if which bash; then
  echo "Using an executable multiple times is OK."
fi
echo "Shell functions are not reported."
shellmock new git
shellmock new curl
shellmock new wget
echo "Normal executables are reported."
ls
ls
find
awk
EOF

  [[ ${output} == $(_join $'\n' awk find ls which) ]]
}

@test "counting executables and functions in shell code" {
  run -0 --separate-stderr shellmock commands -c -f << 'EOF'
echo "Built-ins are not detected."
if which bash; then
  echo "Arguments that happen to be commands are not detected."
fi
if which bash; then
  echo "Using an executable multiple times is OK."
fi
echo "Shell functions are also reported."
shellmock new git
shellmock new curl
shellmock new wget
echo "Normal executables are reported."
ls
ls
find
awk
EOF

  [[ ${output} == $(_join $'\n' awk:1 find:1 ls:2 shellmock:3 which:2) ]]
}

@test "that we know which executables shellmock uses" {
  # Source mock executable to know functions defined therein. Shellmock itself
  # has already been sourced, which means we can filter its internal functions.
  source "${root}/bin/mock_exe.sh"

  code=$(cat "${root}/shellmock.bash" "${root}/bin/mock_exe.sh")
  run -0 --separate-stderr shellmock commands <<< "${code}"

  exes=(
    base32
    base64
    basename
    cat
    chmod
    env
    find
    flock
    gawk
    go
    grep
    mkdir
    mktemp
    ps
    rm
    sed
    sort
    touch
    tr
    xargs
  )
  [[ ${output} == $(_join $'\n' "${exes[@]}") ]]
}

@test "hinting at which executables are being used" {
  # We support multiple ways to specify directives. Test that they all work.
  directives=(
    '# shellmock uses-command=cmd1'
    '#shellmock:uses-command=cmd1,cmd with spaces,cmd2 # followed by a comment'
    '     #   shellmock: uses-command=cmd2,cmd2'
  )
  run -0 shellmock commands -c <<< "$(_join $'\n' "${directives[@]}")"

  exes=(
    "cmd with spaces:1"
    "cmd1:2"
    "cmd2:3"
  )
  [[ ${output} == $(_join $'\n' "${exes[@]}") ]]
}

@test "warning about unknown directives" {
  line='# shellmock: unknown-directive=value'
  script=$'\n\n\n'"${line}"$'\n\n'
  run -0 shellmock commands -c <<< "${script}"
  [[ ${output} == *"WARNING: found unknown shellmock directive in line 4: ${line}"* ]]
}
