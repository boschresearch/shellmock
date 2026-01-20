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

# This file contains functionality needed for the command used to check which
# executables a script is executing. That makes it easier to determine which
# ones to mock.
__shellmock__commands() {
  __shellmock_internal_pathcheck
  __shellmock_internal_trapcheck

  local check_functions=0
  local usage_counts=0
  while [[ $# -gt 0 ]]; do
    case $1 in
    --check-functions | -f)
      local check_functions=1
      ;;
    --usage-counts | -c)
      local usage_counts=1
      ;;
    *)
      echo >&2 "Unknown argument '$1'."
      return 1
      ;;
    esac
    shift
  done

  if ! PATH="${__SHELLMOCK_ORGPATH}" command -v go &> /dev/null; then
    echo >&2 "The 'commands' command requires a Go toolchain." \
      "Get it from here: https://go.dev/doc/install"
    return 1
  fi

  if [[ -t 0 ]]; then
    echo >&2 "Shell code is read from stdin but stdin is a terminal, aborting."
    return 1
  fi
  local code
  code="$(PATH="${__SHELLMOCK_ORGPATH}" cat -)"

  # shellmock: uses-command=flock
  local _flock=flock
  if
    ! command -v flock &> /dev/null \
      || [[ ${__SHELLMOCK_TESTING_WO_FLOCK-0} == 1 ]]
  then
    _flock=true
  fi

  # Build the binary used to analyse the shell code.
  local bin="${__SHELLMOCK_GO_MOD}/main"
  if ! [[ -x ${bin} ]]; then
    (
      "${_flock}" 9 && if ! [[ -x ${bin} ]]; then
        __shellmock_internal_init_command_search "${__SHELLMOCK_GO_MOD}" \
          && cd "${__SHELLMOCK_GO_MOD}" \
          && PATH="${__SHELLMOCK_ORGPATH}" go get \
          && PATH="${__SHELLMOCK_ORGPATH}" go build
      fi
    ) 1>&2 9> "${__SHELLMOCK_GO_MOD}/.lockfile"
  fi

  declare -A builtins
  local tmp
  while IFS= read -r tmp; do
    builtins["${tmp}"]=1
  done < <(compgen -b) && wait $! || return 1

  local cmd
  while IFS= read -r tmp; do
    cmd="${tmp%:*}"
    # Only output if it is neither a currently defined function or a built-in.
    if
      [[ -z ${builtins["${cmd}"]-} ]] \
        && [[ ${check_functions} == 1 ||
          $(type -t "${cmd}" || :) != function ]]
    then
      # Adjust output format as requested.
      if [[ ${usage_counts} == 1 ]]; then
        echo "${tmp}"
      else
        echo "${cmd}"
      fi
    fi
  done < <("${bin}" <<< "${code}") && wait $! || return 1
}
