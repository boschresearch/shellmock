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
    )
  done
}

@test "changing PATH after init issues warning" {
  export PATH="/I/do/not/exist:${PATH}"
  local stderr
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
