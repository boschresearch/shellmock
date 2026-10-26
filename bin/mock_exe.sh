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

# This file contains the mock executable used by shellmock. As such, it can
# impersonate any executable just by being called with a specific name. It also
# uses the environment variables set by the main shellmock library to determine
# which configured call to match and what to write to stdout, if anything.
#
# This script will write its arguments and stdin to files in a sub-directory of
# __SHELLMOCK_OUTPUT. No two calls will overwrite each other's data. The data
# stored this way can be used by the main shellmock library to assert
# user-defined expectations.

# Check whether required environment variables are set.
env_var_check() {
  local var dir
  local vars=(
    __SHELLMOCK_ORGPATH
  )
  local dirs=(
    __SHELLMOCK_MOCKBIN
    __SHELLMOCK_FUNCSTORE
    __SHELLMOCK_OUTPUT
  )
  for dir in "${dirs[@]}"; do
    if ! [[ -d ${!dir-} ]]; then
      echo >&2 "Variable ${dir} not defined or no directory."
      _kill_parent
      return 1
    fi
  done
  for var in "${vars[@]}"; do
    if [[ -z ${!var-} ]]; then
      echo >&2 "Variable ${var} not defined."
      _kill_parent
      return 1
    fi
  done
}

# Remove shellmock's mockbin directory from PATH.
rm_mock_path() {
  local paths=()
  readarray -d : -t paths <<< "${PATH}"
  local idx path
  for idx in "${!paths[@]}"; do
    path="${paths["${idx}"]}"
    if [[ ${path} == "${__SHELLMOCK_MOCKBIN}" ]]; then
      unset "paths[${idx}]"
    fi
  done
  local new_path ifs="${IFS}"
  IFS=:
  new_path="${paths[*]}"
  IFS="${ifs}"
  export PATH="${new_path}"
}

# Make sure that we can find all the executables we need.
binary_deps_check() {
  local has_err=0
  local cmd
  local deps=(base32 cat mkdir)
  if [[ ! -d /proc ]]; then
    deps+=(ps)
  fi
  for cmd in "${deps[@]}"; do
    if ! PATH="${__SHELLMOCK_ORGPATH}" command -v "${cmd}" &> /dev/null; then
      echo >&2 "Required executable ${cmd@Q} not found."
      has_err=1
    fi
  done
  if ! command -v flock &> /dev/null; then
    echo >&2 "Optional executable flock not found." \
      "Please install for best performance."
  fi
  if [[ ${has_err} != 0 ]]; then
    _kill_parent
    return 1
  fi
  return 0
}

_check_w_flock() {
  local cmd_b32=$1
  local count=$2
  local outdir=$3

  (
    flock -n 9 || exit 1
    PATH="${__SHELLMOCK_ORGPATH}" mkdir "${outdir}" &> /dev/null
  ) 9> "${__SHELLMOCK_OUTPUT}/lockfile_${cmd_b32}_${count}"
}

_check_wo_flock() {
  local cmd_b32=$1
  local count=$2
  local outdir=$3

  PATH="${__SHELLMOCK_ORGPATH}" \
    mkdir "${__SHELLMOCK_OUTPUT}/lockfile_${cmd_b32}_${count}" &> /dev/null \
    && PATH="${__SHELLMOCK_ORGPATH}" mkdir "${outdir}" &> /dev/null
}

_cleanup_wo_flock() {
  local cmd_b32="$1"
  local count="$2"

  PATH="${__SHELLMOCK_ORGPATH}" \
    rm -rf "${__SHELLMOCK_OUTPUT}/lockfile_${cmd_b32}_${count}"
}

get_and_ensure_outdir() {
  local cmd_b32="$1"

  local max_num_calls=${SHELLMOCK_MAX_CALLS_PER_MOCK:-100}
  if ! [[ ${max_num_calls} =~ ^[0-9][0-9]*$ ]]; then
    echo >&2 "SHELLMOCK_MAX_CALLS_PER_MOCK must be a number."
    _kill_parent
    return 1
  fi
  local tmp
  tmp=$((max_num_calls - 1))
  local max_digits=${#tmp}

  local check cleanup
  if
    ! command -v flock &> /dev/null \
      || [[ ${__SHELLMOCK_TESTING_WO_FLOCK-0} == 1 ]]
  then
    check=_check_wo_flock
    cleanup=_cleanup_wo_flock
  else
    check=_check_w_flock
    cleanup=true
  fi

  # Ensure no two calls overwrite each other in a thread-safe way.
  local padded count=0
  padded=$(printf "%0${max_digits}d" "${count}")
  PATH="${__SHELLMOCK_ORGPATH}" mkdir -p "${__SHELLMOCK_OUTPUT}/${cmd_b32}"
  local outdir="${__SHELLMOCK_OUTPUT}/${cmd_b32}/${padded}"
  # Increment the counter until we find one that has not been used before.
  while ! "${check}" "${cmd_b32}" "${count}" "${outdir}"; do
    count=$((count + 1))
    padded=$(printf "%0${max_digits}d" "${count}")
    outdir="${__SHELLMOCK_OUTPUT}/${cmd_b32}/${padded}"

    if [[ ${count} -ge ${max_num_calls} ]]; then
      echo >&2 "The maximum number of calls per mock is ${max_num_calls}." \
        "Consider increasing SHELLMOCK_MAX_CALLS_PER_MOCK, which is currently" \
        "set to '${max_num_calls}'."
      _kill_parent
      return 1
    fi
  done
  "${cleanup}" "${cmd_b32}" "${count}"

  echo "${outdir}"
}

# When called, this script will write its own errors to a file so that they can
# be retrieved later when asserting expectations.
errecho() {
  if [[ -n ${STDERR} ]]; then
    echo >> "${STDERR}" "$@"
  else
    echo >&2 "$@"
  fi
}

output_args_and_stdin() {
  local outdir="$1"
  shift

  # Split arguments by null bytes.
  local arg
  for arg in "$@"; do
    printf -- "%s\0" "${arg-}"
  done > "${outdir}/args"
  # If stdin is a terminal, we are called interactively. Don't output our stdin
  # in this case. Only output our stdin if we are not invoked interactively.
  # Otherwise, this would block until the user hit Ctrl+D to send EOF.
  if [[ -t 0 ]]; then
    : > "${outdir}/stdin"
  else
    PATH="${__SHELLMOCK_ORGPATH}" cat - > "${outdir}/stdin"
  fi
  echo "${outdir}/stdin"
}

_match_arg() {
  local kind="$1"
  local value="$2"
  local null_value="$3"
  local cmp="$4"

  case "${kind}" in
  "" | value)
    [[ ${value} == "${cmp}" ]]
    ;;
  substring)
    [[ ${value} == *"${cmp}"* ]]
    ;;
  prefix)
    [[ ${value} == "${cmp}"* ]]
    ;;
  suffix)
    [[ ${value} == *"${cmp}" ]]
    ;;
  regex)
    [[ ${value} =~ ${cmp} ]]
    ;;
  set)
    [[ -n ${value} || ${null_value} != NULL ]]
    ;;
  *)
    echo >&2 "Internal error, unknown argspec kind ${kind@Q}."
    _kill_parent
    ;;
  esac
}

_find_arg() {
  local kind="$1"
  local cmp="$2"
  shift 2
  local args=("$@")

  local check
  case "${kind}" in
  "" | value)
    for check in "${args[@]}"; do
      if [[ ${check} == "${cmp}" ]]; then
        return 0
      fi
    done
    ;;
  substring)
    for check in "${args[@]}"; do
      if [[ ${check} == *"${cmp}"* ]]; then
        return 0
      fi
    done
    ;;
  prefix)
    for check in "${args[@]}"; do
      if [[ ${check} == "${cmp}"* ]]; then
        return 0
      fi
    done
    ;;
  suffix)
    for check in "${args[@]}"; do
      if [[ ${check} == *"${cmp}" ]]; then
        return 0
      fi
    done
    ;;
  regex)
    for check in "${args[@]}"; do
      if [[ ${check} =~ ${cmp} ]]; then
        return 0
      fi
    done
    ;;
  *)
    echo >&2 "Internal error, unknown argspec kind ${kind@Q}."
    _kill_parent
    ;;
  esac

  return 1
}

# Determine whether an argspec defined via a specific environment variable
# matches the arguments this mock received.
_match_spec() {
  local full_spec="$1"
  shift

  local spec
  while IFS= read -d $'\0' -r spec; do
    local id val="${spec#*":"}" kind=${spec%%":"*} env cmp="" empty="NULL"

    # Negative any match.
    if [[ ${spec} =~ ^!([^-:][^-:]*-any|any): ]]; then
      kind=${kind#"!"}
      kind=${kind%"any"}
      kind=${kind%"-"}
      if _find_arg "${kind}" "${val}" "$@"; then
        return 1
      fi
    # Positive any match.
    elif [[ ${spec} =~ ^([^-:][^-:]*-any|any): ]]; then
      kind=${kind%"any"}
      kind=${kind%"-"}
      if ! _find_arg "${kind}" "${val}" "$@"; then
        return 1
      fi
    # Negative env match.
    elif [[ ${spec} =~ ^!([^-:][^-:]*-env=[A-Za-z_][A-Za-z0-9_]*|env=[A-Za-z_][A-Za-z0-9_]*): ]]; then
      env=${kind##*"env="}
      kind=${kind#"!"}
      kind=${kind%"env="*}
      kind=${kind%"-"}
      if cmp="${!env-}" 2> /dev/null; then
        empty="${!env-NULL}"
      fi
      if _match_arg "${kind}" "${cmp}" "${empty}" "${val}"; then
        return 1
      fi
    # Positive env match.
    elif [[ ${spec} =~ ^([^-:][^-:]*-env=[A-Za-z_][A-Za-z0-9_]*|env=[A-Za-z_][A-Za-z0-9_]*): ]]; then
      env=${kind##*"env="}
      kind=${kind%"env="*}
      kind=${kind%"-"}
      if cmp="${!env-}" 2> /dev/null; then
        empty="${!env-NULL}"
      fi
      if ! _match_arg "${kind}" "${cmp}" "${empty}" "${val}"; then
        return 1
      fi
    # Negative positional match.
    elif [[ ${spec} =~ ^!([^-:][^-:]*-[0-9][0-9]*|[0-9][0-9]*): ]]; then
      kind=${kind#"!"}
      id=${kind#*"-"}
      kind=${kind%%"${id}"}
      kind=${kind%%"-"}
      if _match_arg "${kind}" "${!id-}" "${!id-NULL}" "${val}"; then
        return 1
      fi
    # Positive positional match.
    elif [[ ${spec} =~ ^([^-:][^-:]*-[0-9][0-9]*|[0-9][0-9]*): ]]; then
      id=${kind#*"-"}
      kind=${kind%%"${id}"}
      kind=${kind%%"-"}
      if ! _match_arg "${kind}" "${!id-}" "${!id-NULL}" "${val}"; then
        return 1
      fi
    else
      errecho "Internal error, incorrect spec ${spec}"
      return 1
    fi
  done < <(
    PATH="${__SHELLMOCK_ORGPATH}" base32 --decode <<< "${full_spec}"
  ) && wait $! || return 1
}

# Check whether the given process is a bats process. A bats process is a bash
# process with a script located in bats's libexec directory. If we are not
# being executed by bats at all, we consider all processes to be non-bats.
_is_bats_process() {
  local process="$1"
  if [[ -z ${BATS_LIBEXEC-} ]]; then
    # Not using bats, process cannot be a bats one.
    return 1
  fi

  local cmd_w_args
  if
    [[ -f "/proc/${process}/cmdline" && ${__SHELLMOCK_TESTING_WO_PROC-0} != 1 ]]
  then
    mapfile -t -d $'\0' cmd_w_args < "/proc/${process}/cmdline"
  else
    local ps_output && ps_output=$(
      PATH="${__SHELLMOCK_ORGPATH}" ps -p "${process}" -o command=
    )
    mapfile -t -d ' ' cmd_w_args <<< "${ps_output}"
  fi
  # The first entry in cmd_w_args would be "bash" and the second one the bats
  # script if our parent process were a bats process. Such a bats script is in
  # bats's libexec directory.
  [[ ${#cmd_w_args[@]} -ge 2 ]] \
    && [[ ${cmd_w_args[0]} == "bash" &&
      ${cmd_w_args[1]} == "${BATS_LIBEXEC%%/}/"* ]]
}

_kill_parent() {
  local parent="${PPID}"

  # Do not kill the parent process if it is a bats process. If we did, bats
  # would no longer be able to track the test.
  if
    [[ ${__SHELLMOCK__KILLPARENT-} != 1 ]] || _is_bats_process "${parent}"
  then
    return 0
  fi

  local cmd_w_args
  if
    [[ -f "/proc/${parent}/cmdline" && ${__SHELLMOCK_TESTING_WO_PROC-0} != 1 ]]
  then
    mapfile -t -d $'\0' cmd_w_args < "/proc/${parent}/cmdline"
  else
    local ps_output && ps_output=$(
      PATH="${__SHELLMOCK_ORGPATH}" ps -p "${parent}" -o command=
    )
    mapfile -t -d ' ' cmd_w_args <<< "${ps_output}"
  fi
  errecho "Killing parent process: ${cmd_w_args[*]@Q}"
  kill "${parent}"
}

find_matching_argspec() {
  # Find arg specs for this command and determine whether a specification
  # matches.
  local outdir="${1}"
  local cmd="${2}"
  local cmd_b32="${3}"
  shift 3

  local env_var var
  while IFS= read -r env_var; do

    if _match_spec "${!env_var}" "$@"; then
      echo "${env_var##MOCK_ARGSPEC_BASE32_}"
      echo "${env_var}" > "${outdir}/argspec"
      return 0
    fi
  done < <(
    for var in "${!MOCK_ARGSPEC_BASE32_@}"; do
      if [[ ${var} == "MOCK_ARGSPEC_BASE32_${cmd_b32}_"* ]]; then
        echo "${var}"
      fi
    done
  ) && wait $! || return 1

  errecho "SHELLMOCK: unexpected call '${cmd} $*'"
  _kill_parent
  return 1
}

provide_output() {
  local cmd_spec="$1"
  # Base32 encoding is an easy way to be able to store arbitrary data in
  # environment variables.
  local output_base32="MOCK_OUTPUT_BASE32_${cmd_spec}"
  if [[ -n ${!output_base32-} ]]; then
    PATH="${__SHELLMOCK_ORGPATH}" base32 --decode <<< "${!output_base32}"
  fi
}

run_hook() {
  local cmd_spec="$1"
  local stdin_path="$2"
  shift 2
  local args=("$@")
  # If a hook function was specified, run it. It has to be exported for this to
  # work.
  local hook_env_var
  hook_env_var="MOCK_HOOKFN_${cmd_spec}"
  if
    [[ -n ${!hook_env_var-} ]] \
      && [[ $(type -t "${!hook_env_var-}") == function ]]
  then
    # Run hook in sub-shell to reduce its influence on the mock.
    if ! ("${!hook_env_var}" "${args[@]}" < "${stdin_path}"); then
      # Not using errecho because we want this to always show up in the test's
      # output. Anything output via errecho will end up in a file that is only
      # looked at when asserting expectations.
      echo >&2 "SHELLMOCK: error calling hook '${!hook_env_var}'"
      _kill_parent
      return 1
    fi
  fi
}

return_with_code() {
  local cmd_spec="$1"
  # If a return code was specified, exit with that return code. Otherwise exit
  # with success.
  local rc_env_var
  rc_env_var="MOCK_RC_${cmd_spec}"
  if [[ -n ${!rc_env_var-} ]]; then
    return "${!rc_env_var}"
  fi
  return 0
}

# Check whether this mock sould actually call the external executable instead of
# providing mock output and exit code. If it should forward, the value of the
# checked env var for this cmd_spec should be "forward".
should_forward() {
  local cmd_spec="$1"
  local rc_env_var
  rc_env_var="MOCK_RC_${cmd_spec}"
  [[ -n ${!rc_env_var-} ]] \
    && [[ ${!rc_env_var} == forward || ${!rc_env_var} == "forward:"* ]]
}

# Forward the arguments to the first executable in PATH that is not controlled
# by shellmock, that is the first executable not in __SHELLMOCK_MOCKBIN. We
# can also forward to functions that we stored, but those functions cannot
# access shell variables of the surrounding shell. If requested, we will first
# call an exported shell function that may modify the arguments or stdin that
# we forward.
forward() {
  local cmd_spec=$1
  local cmd=$2
  local stdin_path=$3
  shift 3
  local args=("$@")

  # Update arguments or stdin if requested.
  local rc_env_var
  rc_env_var="MOCK_RC_${cmd_spec}"
  if [[ ${!rc_env_var} == "forward:"* ]]; then
    local forward_fn="${!rc_env_var##forward:}"
    local updated_args=() updated_stdin_path="${stdin_path}_updated"
    : > "${updated_stdin_path}"
    if ! {
      mapfile -t -d $'\0' updated_args < <(
        # These functions will be invoked indirectly by the forward function.
        # shellcheck disable=SC2317,SC2329
        update_args() {
          local arg && for arg in "$@"; do printf -- '%s\0' "${arg}"; done
        }
        # shellcheck disable=SC2317,SC2329
        update_stdin() {
          if ! [[ -t 0 ]]; then
            PATH="${__SHELLMOCK_ORGPATH}" cat - >> "${updated_stdin_path}"
          fi
        }
        "${forward_fn}" "${cmd}" "${args[@]}" < "${stdin_path}"
      ) && wait $!
    }; then
      echo >&2 "SHELLMOCK: failed to call function ${forward_fn@Q} that" \
        "shall modify arguments forwarded to ${cmd@Q}."
      _kill_parent
      return 1
    fi
    cmd=${updated_args[0]}
    args=("${updated_args[@]:1}")
    stdin_path=${updated_stdin_path}
  fi

  local exe
  local path="${__SHELLMOCK_FUNCSTORE}:${PATH}"
  # Extend PATH by shellmock's funcstore because we may want to forward to a
  # function instead of a binary.
  if
    ! exe=$(PATH="${path}" command -v "${cmd}")
  then
    echo >&2 "SHELLMOCK: failed to find executable to forward to: ${cmd}"
    _kill_parent
    return 1
  fi
  echo >&2 "SHELLMOCK: forwarding call: ${exe@Q} ${*@Q}"
  exec "${exe}" "${args[@]}" < "${stdin_path}"
}

main() {
  # Make sure that shell aliases never interfere with this mock.
  unalias -a
  rm_mock_path
  binary_deps_check
  env_var_check
  # Determine our name. This assumes that the first value in argv is the name of
  # the command. This is almost always so.
  local cmd cmd_b32 args
  cmd="${0##*/}"
  cmd_b32="$(PATH="${__SHELLMOCK_ORGPATH}" base32 -w0 <<< "${cmd}")"
  cmd_b32="${cmd_b32//=/_}"
  local outdir
  outdir="$(get_and_ensure_outdir "${cmd_b32}")"
  declare -g STDERR="${outdir}/stderr"
  # Stdin is consumed in the function output_args_and_stdin.
  local stdin_path
  stdin_path=$(output_args_and_stdin "${outdir}" "$@")
  # Find the matching argspec defined by the user. If found, write the
  # associated information to stdout and exit with the associated exit code. If
  # it cannot be found, either exit with an error or kill the parent process.
  local cmd_spec
  cmd_spec="$(find_matching_argspec "${outdir}" "${cmd}" "${cmd_b32}" "$@")"
  run_hook "${cmd_spec}" "${stdin_path}" "$@"
  if should_forward "${cmd_spec}"; then
    forward "${cmd_spec}" "${cmd}" "${stdin_path}" "$@"
  else
    provide_output "${cmd_spec}"
    return_with_code "${cmd_spec}"
  fi
}

# Run if executed directly. If sourced from a bash shell, don't do anything,
# which simplifies testing.
if [[ -z ${BASH_SOURCE[0]-} ]] || [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
  set -euo pipefail
  shopt -s inherit_errexit
  main "$@"
fi
