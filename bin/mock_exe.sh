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
  local var
  for var in __SHELLMOCK_MOCKBIN __SHELLMOCK_FUNCSTORE __SHELLMOCK_OUTPUT; do
    if ! [[ -d ${!var-} ]]; then
      echo >&2 "Vairable ${var} not defined or no directory."
      exit 1
    fi
  done
}

get_and_ensure_outdir() {
  local cmd_b32="$1"
  # Ensure no two calls overwrite each other in a thread-safe way.
  local count=0
  local outdir="${__SHELLMOCK_OUTPUT}/${cmd_b32}/${count}"
  while ! (
    # Increment the counter until we find one that has not been used before.
    flock -n 9 || exit 1
    [[ -d ${outdir} ]] && exit 1
    mkdir -p "${outdir}"
  ) 9> "${__SHELLMOCK_OUTPUT}/lockfile_${cmd_b32}_${count}"; do
    count=$((count + 1))
    outdir="${__SHELLMOCK_OUTPUT}/${cmd_b32}/${count}"
  done
  echo "${outdir}"
}

# When called, this script will write its own errors to a file so that they can
# be retrieved later when asserting expectations.
errecho() {
  echo >> "${STDERR}" "$@"
}

output_args_and_stdin() {
  local outdir="$1"
  shift

  # Split arguments by newlines. This will cause problems if there are ever
  # arguments with newlines, of course. Improvements are welcome.
  for arg in "$@"; do
    printf -- "%s\n" "${arg-}"
  done > "${outdir}/args"
  # If stdin is a terminal, we are called interactively. Don't output our stdin
  # in this case. Only output our stdin if we are not invoked interactively.
  # Otherwise, this would block until the user hit Ctrl+D to send EOF.
  if ! [[ -t 0 ]]; then
    cat - > "${outdir}/stdin"
  fi
}

_find_arg() {
  local arg="$1"
  shift
  local args=("$@")

  for check in "${args[@]}"; do
    if [[ ${arg} == "${check}" ]]; then
      return 0
    fi
  done

  return 1
}

_find_regex_arg() {
  local regex="$1"
  shift
  local args=("$@")

  for check in "${args[@]}"; do
    if [[ ${check} =~ ${regex} ]]; then
      return 0
    fi
  done

  return 1
}

# Determine whether an argspec defined via a specific environment variable
# matches the arguments this mock received.
_match_spec() {
  local full_spec="$1"
  shift

  local spec
  while read -r spec; do
    local id val
    id="$(gawk -F: '{print $1}' <<< "${spec}")"
    val="${spec##"${id}":}"

    if [[ ${spec} =~ ^any: ]]; then
      if ! _find_arg "${val}" "$@"; then
        return 1
      fi
    elif [[ ${spec} =~ ^[0-9][0-9]*: ]]; then
      if [[ ${val} != "${!id-}" ]]; then
        return 1
      fi
    elif [[ ${spec} =~ ^regex-any: ]]; then
      if ! _find_regex_arg "${val}" "$@"; then
        return 1
      fi
    elif [[ ${spec} =~ ^regex-[0-9][0-9]*: ]]; then
      id="${id##regex-}"
      if ! [[ ${!id-} =~ ${val} ]]; then
        return 1
      fi
    else
      errecho "Internal error, incorrect spec ${spec}"
      return 1
    fi
  done < <(base64 --decode <<< "${full_spec}") && wait $! || return 1
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
  mapfile -t -d $'\0' cmd_w_args < "/proc/${process}/cmdline"
  # The first entry in cmd_w_args would be "bash" and the second one the bats
  # script if our parent process were a bats process. Such a bats script is in
  # bats's libexec directory.
  [[ ${#cmd_w_args[@]} -ge 2 ]] \
    && [[ ${cmd_w_args[0]} == "bash" &&
      ${cmd_w_args[1]} == "${BATS_LIBEXEC%%/}/"* ]]
}

_kill_parent() {
  local parent="$1"

  # Do not kill the parent process if it is a bats process. If we did, bats
  # would no longer be able to track the test.
  if
    [[ ${__SHELLMOCK__KILLPARENT-} -ne 1 ]] || _is_bats_process "${parent}"
  then
    return 0
  fi

  errecho "Killing parent process with information:"
  # In case the `ps` command fails (e.g. because we mock it), don't fail this
  # mock.
  errecho "$(ps -p "${parent}" -lF || :)"
  kill "${parent}"
}

find_matching_argspec() {
  # Find arg specs for this command and determine whether a specification
  # matches.
  local outdir="${1}"
  local cmd="${2}"
  local cmd_b32="${3}"
  shift 3

  local env_var
  while read -r env_var; do

    if _match_spec "${!env_var}" "$@"; then
      echo "${env_var##MOCK_ARGSPEC_BASE64_}"
      echo "${env_var}" > "${outdir}/argspec"
      return 0
    fi
  done < <(
    env | sed 's/=.*$//' \
      | {
        grep -x "MOCK_ARGSPEC_BASE64_${cmd_b32}_[0-9][0-9]*" || :
      } | sort -u
  ) && wait $! || return 1

  errecho "SHELLMOCK: unexpected call '${cmd} $*'"
  _kill_parent "${PPID}"
  return 1
}

provide_output() {
  local cmd_spec="$1"
  # Base64 encoding is an easy way to be able to store arbitrary data in
  # environment variables.
  output_base64="MOCK_OUTPUT_BASE64_${cmd_spec}"
  if [[ -n ${!output_base64-} ]]; then
    base64 --decode <<< "${!output_base64}"
  fi
}

run_hook() {
  local cmd_spec="$1"
  # If a hook function was specified, run it. It has to be exported for this to
  # work.
  local hook_env_var
  hook_env_var="MOCK_HOOKFN_${cmd_spec}"
  if
    [[ -n ${!hook_env_var-} ]] \
      && [[ $(type -t "${!hook_env_var-}") == function ]]
  then
    # Run hook in sub-shell to reduce its influence on the mock.
    if ! ("${!hook_env_var}"); then
      # Not using errecho because we want this to always show up in the test's
      # output. Anything output via errecho will end up in a file that is only
      # looked at when asserting expectations.
      echo >&2 "SHELLMOCK: error calling hook '${!hook_env_var}'"
      _kill_parent "${PPID}"
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
  [[ -n ${!rc_env_var-} && ${!rc_env_var} == forward ]]
}

# Forward the arguments to the first executable in PATH that is not controlled
# by shellmock, that is the first executable not in __SHELLMOCK_MOCKBIN. We can
# also forward to functions that we stored, but those functions cannot access
# shell variables of the surrounding shell.
forward() {
  local cmd=$1
  shift
  local args=("$@")

  while read -r -d: path; do
    if
      [[ ${path} != "${__SHELLMOCK_MOCKBIN}" ]] \
        && PATH="${path}" command -v "${cmd}" &> /dev/null
    then
      local exe="${path}/${cmd}"
      echo >&2 "SHELLMOCK: forwarding call: ${exe} $*"
      exec "${exe}" "${args[@]}"
    fi
  done <<< "${__SHELLMOCK_FUNCSTORE}:${PATH}"
}

main() {
  # Make sure that shell aliases never interfere with this mock.
  unalias -a
  env_var_check
  # Determine our name. This assumes that the first value in argv is the name of
  # the command. This is almost always so.
  local cmd cmd_b32 args
  cmd="$(basename "$0")"
  cmd_b32="$(base32 -w0 <<< "${cmd}" | tr "=" "_")"
  local outdir
  outdir="$(get_and_ensure_outdir "${cmd_b32}")"
  declare -g STDERR="${outdir}/stderr"
  # Stdin is consumed in the function output_args_and_stdin.
  output_args_and_stdin "${outdir}" "$@"
  # Find the matching argspec defined by the user. If found, write the
  # associated information to stdout and exit with the associated exit code. If
  # it cannot be found, either exit with an error or kill the parent process.
  local cmd_spec
  cmd_spec="$(find_matching_argspec "${outdir}" "${cmd}" "${cmd_b32}" "$@")"
  if should_forward "${cmd_spec}"; then
    forward "${cmd}" "$@"
  else
    provide_output "${cmd_spec}"
    run_hook "${cmd_spec}"
    return_with_code "${cmd_spec}"
  fi
}

# Run if executed directly. If sourced from a bash shell, don't do anything,
# which simplifies testing.
if [[ -z ${BASH_SOURCE[0]-} ]] || [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
  set -euo pipefail
  main "$@"
else
  :
fi
