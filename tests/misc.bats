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
  load ../shellmock
  shellmock global-config setval ensure-assertions 0
  # shellcheck disable=SC2086 # We want to perform word splitting here.
  set ${TEST_OPTS-"--"}
}

@test "incorrect argspecs fail the configuration" {
  shellmock new my_exe
  run ! shellmock config my_exe 0 option-without-position
}

@test "configuring a non-existent mock fails" {
  run ! shellmock config missing_exe 0 any:value
}

@test "asserting on a non-existent mock fails" {
  run ! shellmock assert expectations missing_exe
}

@test "using an unknown assertion type" {
  shellmock new my_exe
  run ! shellmock assert unknown-assertion missing_exe
}

@test "setting or getting an unknown global config" {
  run ! shellmock global-config setval unknown-config 1
  run ! shellmock global-config getval unknown-config
}

@test "setting a global config with an empty value" {
  run ! shellmock global-config setval killparent
}

@test "setting and getting a global config" {
  org_val="$(shellmock global-config getval killparent)"
  shellmock global-config setval killparent 0
  new_val="$(shellmock global-config getval killparent)"
  [[ ${org_val} -eq 1 ]]
  [[ ${new_val} -eq 0 ]]
}

@test "using an unknown subcommand for global config" {
  run ! shellmock global-config unknown-command something 1
}

@test "using an unknown command" {
  run ! shellmock i-am-not-a-known-command
}

@test "the help command" {
  shellmock help
}

@test "mocking executables with unusual names" {
  for exe in happy😀face exe-with-dash chinese龙dragon "exe with spaces"; do
    (
      echo >&2 "Testing executable: ${exe@Q}"
      # Make sure the test fails as soon as one command errors out, even though
      # we are in a subshell.
      set -euo pipefail
      shellmock new "${exe}"
      # Define the mock to return with success.
      shellmock config "${exe}" 0 1:arg
      # Ensure assertions fail without the configured call having happened.
      run ! shellmock assert expectations "${exe}"
      # Call the mock.
      "${exe}" arg
      # Make sure assertions work for such mocks.
      shellmock assert expectations "${exe}"
      echo >&2 "Success for executable: ${exe@Q}"
    )
  done
}

@test "using arguments with (fancy) whitespace" {
  for arg in "a b" $'a\tb' $'a\nb' 'a b' " " " a "; do
    (
      echo >&2 "Testing arg: ${arg@Q}"
      # Make sure the test fails as soon as one test errors out, even though
      # we are in a subshell.
      set -euo pipefail
      shellmock new exe
      # Define the mock to return with success.
      shellmock config exe 0 1:first-arg 2:"${arg}" 3:third-arg
      # Call the mock.
      exe first-arg "${arg}" third-arg
      # Make sure assertions work for such mocks.
      shellmock assert expectations exe
      echo >&2 "Success for arg: ${arg@Q}"
    )
  done
}

@test "changing PATH after init issues warning" {
  local stderr
  PATH="/I/do/not/exist:${PATH}" \
    run -0 --separate-stderr shellmock new my_exe
  local regex="^WARNING: value for PATH has changed since loading shellmock"
  [[ ${stderr} =~ ${regex} ]]
}

@test "catch-all mocks are not overwritten" {
  shellmock new git
  shellmock config git 0 <<< "catchall"
  shellmock config git 0 1:branch <<< "branch"

  run git branch
  [[ ${output} == catchall ]]
}

@test "asserting expectations does not overwrite run's stderr variable" {
  do_something_and_echo_to_stderr() {
    some_executable
    echo >&2 "I write to stderr."
  }

  shellmock new some_executable
  shellmock config some_executable 0

  local stderr
  run --separate-stderr do_something_and_echo_to_stderr

  shellmock assert expectations some_executable
  [[ ${status} -eq 0 ]]
  [[ -z ${output} ]]
  [[ ${stderr} == "I write to stderr." ]]
}

@test "expectations can be asserted when defining a mock but not configuring" {
  shellmock new some_executable
  shellmock assert expectations some_executable
}

@test "disallow calling more often than specified" {
  export SHELLMOCK_MAX_CALLS_PER_MOCK=3
  shellmock new some_executable
  shellmock config some_executable 0
  # The first 3 calls work out.
  some_executable
  some_executable
  some_executable
  # The next call fails.
  run ! some_executable

  shellmock assert expectations some_executable
}

@test "disallow configuring more often than specified" {
  export SHELLMOCK_MAX_CONFIGS_PER_MOCK=3
  shellmock new some_executable
  # The first 3 configs can be set.
  shellmock config some_executable 0 1:arg1
  shellmock config some_executable 0 1:arg2
  shellmock config some_executable 0 1:arg3
  # The next one fails.
  run ! shellmock config some_executable 0 1:arg4
}

@test "shellmock works also with almost empty PATH" {
  orgpath="${PATH}"
  export PATH="${__SHELLMOCK_MOCKBIN}"
  shellmock new my_exe
  shellmock config my_exe 0 1:arg
  my_exe arg
  shellmock assert expectations my_exe
  run ! my_exe asdf
  export PATH=${orgpath}
}

@test "determining whether an executable is a mock" {
  # An executable is no mock by default.
  run ! shellmock is-mock ls
  [[ -z ${output} ]]
  # Create mock.
  shellmock new ls
  # An executable is a mock after creating one.
  run -0 shellmock is-mock ls
  [[ -z ${output} ]]
}

@test "whether something is a mock works for non-existent executables" {
  run ! command -v some_non_existent_exe
  run ! shellmock is-mock some_non_existent_exe
  [[ -z ${output} ]]
}
