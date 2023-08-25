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

set -euo pipefail

# Check whether required environment variables are set.
env_var_check() {
  if ! [[ -d ${__SHELLMOCK_OUTPUT-} ]]; then
    echo "Vairable __SHELLMOCK_OUTPUT not defined or no directory."
    exit 1
  fi
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

  while read -r spec; do
    local id val
    id="$(awk -F: '{print $1}' <<< "${spec}")"
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
  done < <(base64 --decode <<< "${full_spec}")
}

_kill_parent() {
  local parent="$1"

  if [[ ${__SHELLMOCK__KILLPARENT-} -ne 1 ]]; then
    return
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
  local cmd_b32="${1}"
  shift

  local env_var
  while read -r env_var; do

    if _match_spec "${!env_var}" "$@"; then
      echo "${env_var##MOCK_ARGSPEC_BASE64_}"
      echo "${env_var}" > "${outdir}/argspec"
      return 0
    fi
  done < <(
    env | sed 's/=.*$//' \
      | grep -x "MOCK_ARGSPEC_BASE64_${cmd_b32}_[0-9][0-9]*" | sort -u
  )

  errecho "SHELLMOCK: unexpected call to '$0 $*'"
  _kill_parent "${PPID}"
  return 1
}

provide_output() {
  local cmd_spec="$1"
  # Base64 encoding is an easy way to be able to store arbitrary data in
  # environment variables.
  output_base64="MOCK_OUTPUT_BASE64_${cmd_spec}"
  if [[ -n ${!output_base64} ]]; then
    base64 --decode <<< "${!output_base64}"
  fi
}

return_with_code() {
  local cmd_spec="$1"
  # If a return code was specified, exit with that return code. Otherwise exit
  # with success.
  local rc_env_var
  rc_env_var="MOCK_RC_${cmd_spec}"
  if [[ -n ${!rc_env_var} ]]; then
    return "${!rc_env_var}"
  fi
  return 0
}

main() {
  env_var_check
  # Determine our name. This assumes that the first value in argv is the name of
  # the command. This is almost always so.
  local cmd_b32
  cmd_b32="$(basename "$0" | base32 -w0 | tr "=" "_")"
  local outdir
  outdir="$(get_and_ensure_outdir "${cmd_b32}")"
  declare -g STDERR="${outdir}/stderr"
  # Stdin is consumed in the function output_args_and_stdin.
  output_args_and_stdin "${outdir}" "$@"
  # Find the matching argspec defined by the user. If found, write the
  # associated information to stdout and exit with the associated exit code. If
  # it cannot be found, either exit with an error or kill the parent process.
  local cmd_spec
  cmd_spec="$(find_matching_argspec "${cmd_b32}" "$@")"
  provide_output "${cmd_spec}"
  return_with_code "${cmd_spec}"
}

# Run if executed directly. If sourced from a bash shell, don't do anything,
# which simplifies testing.
if [[ -z ${BASH_SOURCE[0]-} ]] || [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
  main "$@"
else
  :
fi
