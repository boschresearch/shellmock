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

# This file contains the definition of all of shellmock's commands that are
# needed to manage mocks. This file also contains some helper functions for the
# individual commands.

# Create a new mock for an executable or a function. Functions are unset first
# or they could not be mocked with executables.
__shellmock__new() {
  __shellmock_internal_pathcheck
  __shellmock_internal_trapcheck

  local cmd="$1"

  if [[ ${cmd} == *"/"* ]]; then
    echo >&2 "Command to mock must not contain slashes but received ${cmd@Q}."
  fi

  if [[ $(type -t "${cmd}") == function ]]; then
    # We are mocking a function, unset it or it will take precedence over our
    # injected executable. However, store the original function so that we could
    # restore it.
    __shellmock_internal_funcstore "${cmd}" > "${__SHELLMOCK_FUNCSTORE}/${cmd}"
    PATH="${__SHELLMOCK_ORGPATH}" chmod +x "${__SHELLMOCK_FUNCSTORE}/${cmd}"
    unset -f "${cmd}"
  fi

  # The function __shellmock_write_mock_exe is generated when building the
  # deployable.
  __shellmock_write_mock_exe > "${__SHELLMOCK_MOCKBIN}/${cmd}"
  PATH="${__SHELLMOCK_ORGPATH}" chmod +x "${__SHELLMOCK_MOCKBIN}/${cmd}"
}

# Check whether a command has been mocked by shellmock.
__shellmock__is-mock() {
  __shellmock_internal_pathcheck
  __shellmock_internal_trapcheck

  local cmd="$1"

  local location
  location=$(command -v "${cmd}" 2> /dev/null || :)
  [[ ${location} == "${__SHELLMOCK_MOCKBIN}/${cmd}" ]]
}

# An alias for the "new" command.
__shellmock__mock() {
  __shellmock__new "$@"
}

__shellmock__unmock() {
  __shellmock_internal_pathcheck
  __shellmock_internal_trapcheck

  local cmd="$1"
  local cmd_b32
  cmd_b32=$(PATH="${__SHELLMOCK_ORGPATH}" base32 -w0 <<< "${cmd}")
  cmd_b32=${cmd_b32//=/_}

  # Restore the function if we are mocking one.
  local store="${__SHELLMOCK_FUNCSTORE}/${cmd}"
  if [[ -f ${store} ]]; then
    # shellcheck disable=SC1090
    source "${store}"
    PATH="${__SHELLMOCK_ORGPATH}" rm "${store}"
  fi

  # In any case, remove the mock and unset all env vars defined for it. Mocks
  # are identified by their argspecs or return codes. Thus, we only remove those
  # env vars.
  local env_var
  while IFS= read -r env_var; do
    unset "${env_var}"
  done < <(
    local var
    for var in "${!MOCK_RC_@}" "${!MOCK_ARGSPEC_BASE32_@}"; do
      if
        [[ ${var} == "MOCK_RC_${cmd_b32}_"* ]] \
          || [[ ${var} == "MOCK_ARGSPEC_BASE32_${cmd_b32}_"* ]]
      then
        echo "${var}"
      fi
    done
  ) && wait $! || return 1

  if [[ -f "${__SHELLMOCK_MOCKBIN}/${cmd}" ]]; then
    PATH="${__SHELLMOCK_ORGPATH}" rm "${__SHELLMOCK_MOCKBIN}/${cmd}"
  fi
}

# An alias for the "unmock" command.
__shellmock__delete() {
  __shellmock__unmock "$@"
}

__shellmock_assert_no_duplicate_argspecs() {
  local args=("$@")

  declare -A arg_idx_count=()
  declare -a duplicate_arg_indices=()
  local count arg
  for arg in "${args[@]}"; do
    idx=${arg%%:*}
    idx=${idx#regex-}
    if [[ ${idx} == any ]]; then
      continue
    fi
    count=${arg_idx_count["${idx}"]-0}
    arg_idx_count["${idx}"]=$((count + 1))
    if [[ ${count} == 1 ]]; then
      duplicate_arg_indices+=("${idx}")
    fi
  done
  if [[ ${#duplicate_arg_indices[@]} -gt 0 ]]; then
    echo >&2 "Multiple arguments specified for the following indices, cannot" \
      "continue: ${duplicate_arg_indices[*]}"
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
  cmd_b32=$(PATH="${__SHELLMOCK_ORGPATH}" base32 -w0 <<< "${cmd}")
  cmd_b32=${cmd_b32//=/_}
  local rc="$2"
  shift 2

  # Sanity check the provided return code.
  if
    ! [[ ${rc} =~ ^[0-9][0-9]*$ || ${rc} == "forward" || ${rc} == "forward:"* ]]
  then
    echo >&2 "Incorrect format for second argument to 'shellmock config'." \
      "It must be numeric, 'forward', or 'forward:<function_name>'"
    return 1
  fi
  # If a forwarding function has been set, check whether it is a function and
  # export it.
  if [[ ${rc} == "forward:"* ]]; then
    local forward_fn
    forward_fn="${rc##forward:}"
    if [[ $(type -t "${forward_fn}") != function ]]; then
      echo >&2 "Requested forwarding function ${forward_fn@Q} does not exist."
      return 1
    fi
    if [[ ${forward_fn} == update_args ]]; then
      echo >&2 "Forwarding function must not be called 'update_args'."
      return 1
    fi
    export -f "${forward_fn?}"
  fi

  # If a hook has been set, check whether it is a function and export it.
  local hook
  if [[ ${1-} == "hook:"* ]]; then
    hook="${1##hook:}"
    shift
    if [[ $(type -t "${hook}") != function ]]; then
      echo >&2 "Requested hook function ${hook@Q} does not exist."
      return 1
    fi
    export -f "${hook?}"
  fi

  # Validate input format.
  local arg
  local args=()
  local has_err=0
  local regex='^(regex-[0-9][0-9]*|regex-any|i|[0-9][0-9]*|any):'
  for arg in "$@"; do
    if ! [[ ${arg} =~ ${regex} ]]; then
      echo >&2 "Incorrect format of argspec: ${arg}"
      has_err=1
    fi
    args+=("${arg}")
  done
  if [[ ${has_err} != 0 ]]; then
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

  local max_num_configs=${SHELLMOCK_MAX_CONFIGS_PER_MOCK:-100}
  if ! [[ ${max_num_configs} =~ ^[0-9][0-9]*$ ]]; then
    echo >&2 "SHELLMOCK_MAX_CONFIGS_PER_MOCK must be a number."
    return 1
  fi
  local tmp
  tmp=$((max_num_configs - 1))
  local max_digits=${#tmp}

  # Handle fake exit code. Use the exit code as a proxy to determine which count
  # to use next because all mock configurations have to set the exit code but
  # not all of them have to provide arg specs or output.
  local count=0 padded
  padded=$(printf "%0${max_digits}d" "${count}")
  local env_var_val="${rc}"
  local env_var_name="MOCK_RC_${cmd_b32}_${padded}"
  while [[ -n ${!env_var_name-} ]]; do
    count=$((count + 1))
    padded=$(printf "%0${max_digits}d" "${count}")
    env_var_name="MOCK_RC_${cmd_b32}_${padded}"
  done

  if [[ ${count} -ge ${max_num_configs} ]]; then
    echo >&2 "The maximum number of configs per mock is ${max_num_configs}." \
      "Consider increasing SHELLMOCK_MAX_CONFIGS_PER_MOCK, which is currently" \
      "set to '${max_num_configs}'."
    return 1
  fi

  declare -gx "${env_var_name}=${env_var_val}"

  # Handle arg specs.
  env_var_val=$(for arg in "${args[@]}"; do
    printf "%s\0" "${arg}"
  done | PATH="${__SHELLMOCK_ORGPATH}" base32 -w0)
  env_var_name="MOCK_ARGSPEC_BASE32_${cmd_b32}_${padded}"
  declare -gx "${env_var_name}=${env_var_val}"

  # Handle mock's output. Read from stdin but only if stdin is not a terminal.
  if ! [[ -t 0 ]]; then
    env_var_val="$(PATH="${__SHELLMOCK_ORGPATH}" base32 -w0)"
  else
    env_var_val=
  fi
  env_var_name="MOCK_OUTPUT_BASE32_${cmd_b32}_${padded}"
  declare -gx "${env_var_name}=${env_var_val}"

  # Handle hook.
  if [[ -n ${hook-} ]]; then
    env_var_name="MOCK_HOOKFN_${cmd_b32}_${padded}"
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
  cmd_b32=$(PATH="${__SHELLMOCK_ORGPATH}" base32 -w0 <<< "${cmd}")
  cmd_b32=${cmd_b32//=/_}

  # Ensure we only assert on existing mocks.
  if ! [[ -x "${__SHELLMOCK_MOCKBIN}/${cmd}" ]]; then
    echo >&2 "Cannot assert on mock '${cmd}', create mock first."
    return 1
  fi

  # Create new empty file.
  : > "${__SHELLMOCK_EXPECTATIONS_DIR}/${cmd}"

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
    while IFS= read -r stderr; do
      if [[ -s ${stderr} ]]; then
        PATH="${__SHELLMOCK_ORGPATH}" cat >&2 "${stderr}"
        has_err=1
      fi
    done < <(
      shopt -s globstar
      local file
      for file in "${__SHELLMOCK_OUTPUT}/${cmd_b32}/"**"/stderr"; do
        if [[ -f ${file} ]]; then
          echo "${file}"
        fi
      done
    ) && wait $! || return 1
    if [[ ${has_err} != 0 ]]; then
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
      local file
      if [[ -d "${__SHELLMOCK_OUTPUT}/${cmd_b32}" ]]; then
        shopt -s globstar
        for file in "${__SHELLMOCK_OUTPUT}/${cmd_b32}/"**"/argspec"; do
          if [[ -f ${file} ]]; then
            PATH="${__SHELLMOCK_ORGPATH}" cat "${file}"
          fi
        done
      fi
    ) && wait $! || return 1

    declare -a expected_argspecs
    mapfile -t expected_argspecs < <(
      local var
      for var in "${!MOCK_ARGSPEC_BASE32_@}"; do
        if [[ ${var} == "MOCK_ARGSPEC_BASE32_${cmd_b32}_"* ]]; then
          echo "${var}"
        fi
      done
    ) && wait $! || return 1

    local has_err=0
    for argspec in "${expected_argspecs[@]}"; do
      if ! [[ " ${actual_argspecs[*]} " == *"${argspec}"* ]]; then
        has_err=1
        local msg_args=()
        readarray -d $'\0' -t msg_args < <(
          PATH="${__SHELLMOCK_ORGPATH}" base32 --decode <<< "${!argspec}"
        ) && wait $! || exit 1
        (
          IFS=" " && echo >&2 "SHELLMOCK: cannot find call for mock ${cmd}" \
            "and argspec: ${msg_args[*]}"
        )
      fi
    done
    if [[ ${has_err} != 0 ]]; then
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
    if [[ $((idx + 1)) != "${#args[@]}" ]]; then
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
  cmd_b32=$(PATH="${__SHELLMOCK_ORGPATH}" base32 -w0 <<< "${cmd}")
  cmd_b32=${cmd_b32//=/_}
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
    local dir
    for dir in "${__SHELLMOCK_OUTPUT}/${cmd_b32}/"*; do
      if [[ -d ${dir} ]]; then
        echo "${dir}"
      fi
    done
  ) && wait $! || return 1

  for call_idx in "${!call_ids[@]}"; do
    local call_id="${call_ids[${call_idx}]}"
    local call_num=$((call_idx + 1))
    local shell_quoted=()

    # Extract arguments and stdin. Shell-quote everything for the suggestion.
    local args=()
    readarray -d $'\0' -t args < "${call_id}/args"
    local idx
    for idx in "${!args[@]}"; do
      local arg="${args[${idx}]}"
      shell_quoted+=("$(printf "%q" "$((idx + 1)):${arg}")")
    done
    local stdin=
    if [[ -s "${call_id}/stdin" ]]; then
      stdin="$(PATH="${__SHELLMOCK_ORGPATH}" cat "${call_id}/stdin")"
      shell_quoted+=("<<<" "$(printf "%q" "${stdin}")")
    fi
    local suggestion="shellmock config ${cmd_quoted} 0 ${shell_quoted[*]}"

    case ${format} in
    --plain)
      # Split records using one empty line.
      if [[ ${call_num} != 1 ]]; then
        echo
      fi
      PATH="${__SHELLMOCK_ORGPATH}" cat << EOF
name:       ${cmd}
id:         ${call_num}
args:       ${args[*]}
stdin:      ${stdin}
suggestion: ${suggestion}
EOF
      ;;
    --simple)
      if [[ -z ${stdin} ]]; then
        stdin="''"
      fi
      (IFS=" " && printf -- "%s %s <<< %s\n" "${cmd}" "${args[*]}" "${stdin}")
      ;;
    --quoted)
      (IFS=" " && printf -- "%s %s <<< %s\n" "${cmd@Q}" "${args[*]@Q}" "${stdin@Q}")
      ;;
    --json)
      # JSON-quote all strings. Use 2 spaces as indentation.
      if [[ ${call_num} == 1 ]]; then
        echo $'[\n  {'
      fi
      PATH="${__SHELLMOCK_ORGPATH}" cat << EOF
    "name": "$(__shellmock_jsonify_string "${cmd}")",
    "id": "$(__shellmock_jsonify_string "${call_num}")",
    "args": $(__shellmock_jsonify_array "    " "${args[@]}"),
    "stdin": "$(__shellmock_jsonify_string "${stdin}")",
    "suggestion": "$(__shellmock_jsonify_string "${suggestion}")"
EOF
      if [[ ${call_num} != "${#call_ids[@]}" ]]; then
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
