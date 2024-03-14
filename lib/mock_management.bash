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
  __shellmock_internal_trapcheck

  local cmd="$1"

  if [[ $(type -t "${cmd}") == function ]]; then
    # We are mocking a function, unset it or it will take precedence over our
    # injected executable.
    unset -f "${cmd}"
  fi

  __shellmock_write_mock_exe > "${__SHELLMOCK_MOCKBIN}/${cmd}"
  chmod +x "${__SHELLMOCK_MOCKBIN}/${cmd}"
}

__shellmock_assert_no_duplicate_argspecs() {
  local args=("$@")

  declare -A arg_idx_count=()
  declare -A duplicate_arg_indices=()
  local count
  for arg in "${args[@]}"; do
    idx=${arg%%:*}
    idx=${idx#regex-}
    if [[ ${idx} == any ]]; then
      continue
    fi
    count=${arg_idx_count["${idx}"]-0}
    arg_idx_count["${idx}"]=$((count + 1))
    if [[ ${count} -gt 0 ]]; then
      duplicate_arg_indices["${idx}"]=1
    fi
  done
  if [[ ${#duplicate_arg_indices[@]} -gt 0 ]]; then
    local dups
    dups=$(printf '%s\n' "${!duplicate_arg_indices[@]}" | sort -n | tr '\n' ' ')
    echo >&2 "Multiple arguments specified for the following indices, cannot" \
      "continue: ${dups}"
    return 1
  fi
}

# Configure an already created mock. Provide the mock name, the desired exit
# code, as well as the desired argspecs.
__shellmock__config() {
  __shellmock_internal_pathcheck
  __shellmock_internal_trapcheck

  # Fake output is read from stdin.
  local cmd="$1"
  local cmd_b32
  cmd_b32=$(base32 -w0 <<< "${cmd}" | tr "=" "_")
  local rc="$2"
  shift 2

  # If a hook has been set, check whether it is a function and export it.
  local hook
  if [[ ${1-} == "hook:"* ]]; then
    hook="${1##hook:}"
    shift
    if [[ $(type -t "${hook}") != function ]]; then
      echo >&2 "Requested hook function '${hook}' does not exist."
      return 1
    fi
    export -f "${hook?}"
  fi

  # Validate input format.
  local args=()
  local has_err=0
  local regex='^(regex-[0-9][0-9]*|regex-any|i|[0-9][0-9]*|any):'
  for arg in "$@"; do
    if ! grep -qE "${regex}" <<< "${arg}"; then
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

  if ! __shellmock_assert_no_duplicate_argspecs "${args[@]}"; then
    return 1
  fi

  # Handle fake exit code. Use the exit code as a proxy to determine which count
  # to use next because all mock configurations have to set the exit code but
  # not all of them have to provide arg specs or output.
  local count=0
  local env_var_val="${rc}"
  local env_var_name="MOCK_RC_${cmd_b32}_${count}"
  while [[ -n ${!env_var_name-} ]]; do
    count=$((count + 1))
    env_var_name="MOCK_RC_${cmd_b32}_${count}"
  done
  declare -gx "${env_var_name}=${env_var_val}"

  # Handle arg specs.
  env_var_val=$(for arg in "${args[@]}"; do
    echo "${arg}"
  done | base64 -w0)
  env_var_name="MOCK_ARGSPEC_BASE64_${cmd_b32}_${count}"
  declare -gx "${env_var_name}=${env_var_val}"

  # Handle fake output. Read from stdin but only if stdin is not a terminal.
  if ! [[ -t 0 ]]; then
    env_var_val="$(base64 -w0)"
  else
    env_var_val=
  fi
  env_var_name="MOCK_OUTPUT_BASE64_${cmd_b32}_${count}"
  declare -gx "${env_var_name}=${env_var_val}"

  # Handle hook.
  if [[ -n ${hook-} ]]; then
    env_var_name="MOCK_HOOKFN_${cmd_b32}_${count}"
    declare -gx "${env_var_name}=${hook}"
  fi
}

# Assert whether the configured mocks have been called as expected.
__shellmock__assert() {
  __shellmock_internal_pathcheck
  __shellmock_internal_trapcheck

  local assert_type="$1"
  local cmd="$2"
  local cmd_b32
  cmd_b32=$(base32 -w0 <<< "${cmd}" | tr "=" "_")

  # Ensure we only assert on existing mocks.
  if ! [[ -x "${__SHELLMOCK_MOCKBIN}/${cmd}" ]]; then
    echo >&2 "Cannot assert on mock '${cmd}', create mock first."
    return 1
  fi

  touch "${__SHELLMOCK_EXPECTATIONS_DIR}/${cmd}"

  case "${assert_type}" in
  # Make sure that no calls were issued to the mock that we did not expect. By
  # default, the mock will kill its parent process if an unexpected call
  # happens. However, there are cases where that is not desired, which is why
  # this assertion is helpful.
  only-expected-calls)
    if [[ ! -d "${__SHELLMOCK_OUTPUT}/${cmd_b32}" ]]; then
      # If this directory is missing, the mock has never been called. That is
      # fine for this assert type because it means we did not get any unexpected
      # calls.
      return 0
    fi

    local has_err=0
    local stderr
    while read -r stderr; do
      if [[ -s ${stderr} ]]; then
        cat >&2 "${stderr}"
        has_err=1
      fi
    done < <(
      find "${__SHELLMOCK_OUTPUT}/${cmd_b32}" -mindepth 2 -type f -name stderr
    ) && wait $!
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
      if [[ -d "${__SHELLMOCK_OUTPUT}/${cmd_b32}" ]]; then
        find "${__SHELLMOCK_OUTPUT}/${cmd_b32}" -mindepth 2 -type f \
          -name argspec -print0 | xargs -r -0 cat | sort -u
      fi
    ) && wait $!

    declare -a expected_argspecs
    mapfile -t expected_argspecs < <(
      # Ignore grep's exit code, which is relevant with the "pipefail" option.
      # The case of no matches is OK here.
      env | sed 's/=.*$//' \
        | { grep -x "MOCK_ARGSPEC_BASE64_${cmd_b32}_[0-9][0-9]*" || :; } \
        | sort -u
    ) && wait $!

    local has_err=0
    for argspec in "${expected_argspecs[@]}"; do
      if ! [[ " ${actual_argspecs[*]} " == *"${argspec}"* ]]; then
        has_err=1
        echo >&2 "SHELLMOCK: cannot find call for mock ${cmd} and argspec:" \
          "$(base64 --decode <<< "${!argspec}")"
      fi
    done
    if [[ ${has_err} -ne 0 ]]; then
      echo >&2 "SHELLMOCK: at least one expected call for mock ${cmd}" \
        "was not issued."
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
    return 1
    ;;
  esac
}

# Quote special JSON characters backslash, forward slash, and double quotes.
__shellmock_jsonify_string() {
  local val=$1
  # shellcheck disable=SC1003
  val=${val//'\'/'\\'} # Escape all backslashes with a backslash.
  local _S='/'
  local _ES='\/'
  val=${val//"${_S}"/"${_ES}"} # Escape all forward slashes with a backslash.
  val=${val//'"'/'\"'}         # Escape all double quotes with a backslash.
  echo "${val}"
}

# Turn a bash array into a JSON array with proper quoting and indentation.
__shellmock_jsonify_array() {
  local indent="${1}"
  shift
  local args=("$@")
  # Assume first line will already be indented properly by caller.
  echo "["
  for idx in "${!args[@]}"; do
    if [[ $((idx + 1)) -ne ${#args[@]} ]]; then
      local sep=,
    else
      local sep=
    fi
    local arg="${args["${idx}"]}"
    echo "${indent}  \"$(__shellmock_jsonify_string "${arg}")\"${sep}"
  done
  echo "${indent}]"
}

__shellmock__calls() {
  __shellmock_internal_pathcheck
  __shellmock_internal_trapcheck

  local cmd="$1"
  local format="${2-"--plain"}"
  local cmd_b32
  cmd_b32=$(base32 -w0 <<< "${cmd}" | tr "=" "_")
  local cmd_quoted
  cmd_quoted="$(printf "%q" "${cmd}")"

  # Ensure we only retrieve call logs for existing mocks and ones that have been
  # called at least once.
  if ! [[ -d "${__SHELLMOCK_OUTPUT}/${cmd_b32}" ]]; then
    echo >&2 "Cannot retrieve call logs for executable '${cmd}'," \
      "mock unknown or it has never been called."
    return 2
  fi

  local call_ids
  readarray -d $'\n' -t call_ids < <(
    find "${__SHELLMOCK_OUTPUT}/${cmd_b32}" -mindepth 1 -maxdepth 1 -type d \
      | sort -n
  ) && wait $!

  for call_idx in "${!call_ids[@]}"; do
    local call_id="${call_ids[${call_idx}]}"
    local call_num=$((call_idx + 1))
    local shell_quoted=()

    # Extract arguments and stdin. Shell-quote everything for the suggestion.
    local args=()
    readarray -d $'\n' -t args < "${call_id}/args"
    local idx
    for idx in "${!args[@]}"; do
      local arg="${args[${idx}]}"
      shell_quoted+=("$(printf "%q" "$((idx + 1)):${arg}")")
    done
    local stdin=
    if [[ -s "${call_id}/stdin" ]]; then
      stdin="$(cat "${call_id}/stdin")"
      shell_quoted+=("<<<" "$(printf "%q" "${stdin}")")
    fi
    local suggestion="shellmock config ${cmd_quoted} 0 ${shell_quoted[*]}"

    case ${format} in
    --plain)
      # Split records using one empty line.
      if [[ ${call_num} -ne 1 ]]; then
        echo
      fi
      cat << EOF
name:       ${cmd}
id:         ${call_num}
args:       ${args[*]}
stdin:      ${stdin}
suggestion: ${suggestion}
EOF
      ;;
    --json)
      # JSON-quote all strings. Use 2 spaces as indentation.
      if [[ ${call_num} -eq 1 ]]; then
        echo $'[\n  {'
      fi
      cat << EOF
    "name": "$(__shellmock_jsonify_string "${cmd}")",
    "id": "$(__shellmock_jsonify_string "${call_num}")",
    "args": $(__shellmock_jsonify_array "    " "${args[@]}"),
    "stdin": "$(__shellmock_jsonify_string "${stdin}")",
    "suggestion": "$(__shellmock_jsonify_string "${suggestion}")"
EOF
      if [[ ${call_num} -ne ${#call_ids[@]} ]]; then
        echo $'  },\n  {'
      else
        echo $'  }\n]'
      fi
      ;;
    *)
      echo >&2 "unknown call log format '${format}'"
      return 2
      ;;
    esac
  done
  # Always exit with error because this function is used for mock development.
  # That way, there is no chance that tests using it succeed (unless the exit
  # code is deliberately ignored).
  return 1
}
