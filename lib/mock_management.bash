#!/bin/bash

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

# Create a new mock for an executable or a function. Functions are unset first
# or they could not be mocked with executables.
__shellmock__new() {
  __shellmock_internal_pathcheck

  local exe="$1"

  if [[ $(type -t "${exe}") == function ]]; then
    # We are mocking a function, unset it or it will take precedence over our
    # injected executable.
    unset -f "${exe}"
  fi

  __shellmock_write_mock_exe > "${__SHELLMOCK_MOCKBIN}/${exe}"
  chmod +x "${__SHELLMOCK_MOCKBIN}/${exe}"
}

# Configure an already created mock. Provide the mock name, the desired exit
# code, as well as the desired argspecs.
__shellmock__config() {
  __shellmock_internal_pathcheck

  # Fake output is read from stdin.
  local cmd="$1"
  local rc="$2"
  shift 2

  # Validate input format.
  local args=()
  local has_err=0
  for arg in "$@"; do
    if ! grep -qE '^(regex-[0-9][0-9]*|regex-any|i|[0-9][0-9]*|any):' <<< "${arg}"; then
      echo >&2 "Incorrect format of argspec: ${arg}"
      has_err=1
    fi
    args+=("${arg}")
  done
  if [[ ${has_err} -ne 0 ]]; then
    return 1
  fi

  # Ensure we only configure existing mocks.
  if ! [[ -x "${__SHELLMOCK_MOCKBIN}/${cmd}" ]]; then
    echo >&2 "Cannot configure executable '${cmd}', create mock first."
    return 1
  fi

  # Convert incremented arg counters.
  local new_arg arg last_count=0 updated_args=()
  for arg in "${args[@]}"; do
    if [[ ${arg} == "i:"* ]]; then
      if [[ -z ${last_count} ]]; then
        echo >&2 "Cannot use non-numerical last counter as increment base."
        return 1
      fi
      last_count=$((last_count + 1))
      new_arg="${last_count}:${arg#i:}"
    else
      new_arg="${arg}"
      # Only use counter as increment base if one was given.
      if [[ ${arg%%:*} =~ [0-9][0-9]* ]]; then
        last_count="${arg%%:*}"
      else
        last_count=
      fi
    fi
    updated_args+=("${new_arg}")
  done
  args=("${updated_args[@]}")

  # Handle arg specs.
  local env_var_val
  env_var_val=$(for arg in "${args[@]}"; do
    echo "${arg}"
  done | base64)

  local count=0
  local env_var_name="MOCK_ARGSPEC_BASE64_${cmd}_${count}"
  while [[ -n ${!env_var_name-} ]]; do
    count=$((count + 1))
    env_var_name="MOCK_ARGSPEC_BASE64_${cmd}_${count}"
  done
  declare -gx "${env_var_name}=${env_var_val}"

  # Handle fake output. Read from stdin but only if stdin is not a terminal.
  if ! [[ -t 0 ]]; then
    env_var_val="$(base64)"
  else
    env_var_val=
  fi
  env_var_name="MOCK_OUTPUT_BASE64_${cmd}_${count}"
  declare -gx "${env_var_name}=${env_var_val}"

  # Handle fake exit code.
  env_var_val="${rc}"
  env_var_name="MOCK_RC_${cmd}_${count}"
  declare -gx "${env_var_name}=${env_var_val}"
}

# Assert whether the configured mocks have been called as expected.
__shellmock__assert() {
  __shellmock_internal_pathcheck

  local assert_type="$1"
  local cmd="$2"

  # Ensure we only assert on existing mocks.
  if ! [[ -x "${__SHELLMOCK_MOCKBIN}/${cmd}" ]]; then
    echo >&2 "Cannot assert on mock '${cmd}', create mock first."
    return 1
  fi

  case "${assert_type}" in
  # Make sure that no calls were issued to the mock that we did not expect. By
  # default, the mock will kill its parent process if an unexpected call
  # happens. However, there are cases where that is not desired, which is why
  # this assertion is helpful.
  only-expected-calls)
    if [[ ! -d "${__SHELLMOCK_OUTPUT}/${cmd}" ]]; then
      # If this directory is missing, the mock has never been called. That is
      # fine for this assert type because it means we did not get any unexpected
      # calls.
      return 0
    fi

    local has_err=0
    while read -r stderr; do
      if [[ -s ${stderr} ]]; then
        cat >&2 "${stderr}"
        has_err=1
      fi
    done < <(
      find "${__SHELLMOCK_OUTPUT}/${cmd}" -mindepth 2 -type f -name stderr
    )
    if [[ ${has_err} -ne 0 ]]; then
      echo >&2 "SHELLMOCK: got at least one unexpected call for mock ${cmd}."
      return 1
    fi
    ;;
  # Check whether each expected call has happened at least once. That is done by
  # checking which argspecs are defined for the mock and comparing those to the
  # argspecs that were found by then mock when it was being executed. If the
  # lists differ, some configured calls have not happened.
  call-correspondence)
    declare -a actual_argspecs
    mapfile -t actual_argspecs < <(
      [[ -d "${__SHELLMOCK_OUTPUT}/${cmd}" ]] \
        && find "${__SHELLMOCK_OUTPUT}/${cmd}" -mindepth 2 -type f \
          -name argspec -print0 | xargs -0 cat | sort -u
    )

    declare -a expected_argspecs
    mapfile -t expected_argspecs < <(
      env | sed 's/=.*$//' | grep -x "MOCK_ARGSPEC_BASE64_${cmd}_[0-9][0-9]*" \
        | sort -u
    )

    local has_err=0
    for argspec in "${expected_argspecs[@]}"; do
      if ! [[ " ${actual_argspecs[*]} " == *"${argspec}"* ]]; then
        has_err=1
        echo >&2 "SHELLMOCK: cannot find call for argspec: $(base64 --decode <<< "${!argspec}")"
      fi
    done
    if [[ ${has_err} -ne 0 ]]; then
      echo >&2 "SHELLMOCK: at least one expected call was not issued."
      return 1
    fi
    ;;
  expectations)
    # Run the two asserts defined above after each other.
    __shellmock__assert only-expected-calls "${cmd}" \
      && __shellmock__assert call-correspondence "${cmd}"
    ;;
  *)
    echo >&2 "Unknown assertion type: ${assert_type}"
    ;;
  esac
}
