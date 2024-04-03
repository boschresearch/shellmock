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

__shellmock_mktemp() {
  local has_bats=$1
  local what=$2
  local dir
  local base="${BATS_TEST_TMPDIR-${TMPDIR-/tmp}}/shellmock"
  local template="${what// /_}.XXXXXXXXXX"
  mkdir -p "${base}"
  dir=$(mktemp -d -p "${base}" "${template}")
  if [[ ${has_bats} -eq 0 ]]; then
    echo >&2 "Keeping ${what} in: ${dir}"
  fi
  echo "${dir}"
}

# Initialise shellmock, which includes setting up temporary directories either
# as subdirectories of bats' temporary ones when run via bats, or global
# temporary directories when run without bats. This function also modifies PATH
# so that mocks created by shellmock are used preferentially over others
# installed on the system. It also sets some global, internal configurations to
# their default values.
__shellmock_internal_init() {
  # Check minimum required bash version.
  if ! __shellmock_internal_bash_version_check; then
    return 1
  fi
  local has_bats=1
  if [[ -z ${BATS_TEST_TMPDIR} ]]; then
    has_bats=0
  fi

  if [[ ${has_bats} -eq 0 ]]; then
    echo >&2 "Running outside of bats, temporary directories will be kept."
  fi

  # Modify PATH to permit injecting executables.
  declare -gx __SHELLMOCK_MOCKBIN
  __SHELLMOCK_MOCKBIN="$(__shellmock_mktemp "${has_bats}" "mocks")"
  export PATH="${__SHELLMOCK_MOCKBIN}:${PATH}"

  declare -gx __SHELLMOCK_OUTPUT
  __SHELLMOCK_OUTPUT="$(__shellmock_mktemp "${has_bats}" "mock call data")"

  declare -gx __SHELLMOCK_FUNCSTORE
  __SHELLMOCK_FUNCSTORE="$(__shellmock_mktemp "${has_bats}" "mocked functions")"

  declare -gx __SHELLMOCK_EXPECTATIONS_DIR
  __SHELLMOCK_EXPECTATIONS_DIR="$(
    __shellmock_mktemp "${has_bats}" "call records"
  )"

  declare -gx __SHELLMOCK_GO_MOD
  __SHELLMOCK_GO_MOD="$(
    __shellmock_mktemp "${has_bats}" "go code"
  )"

  declare -gx __SHELLMOCK_PATH
  # Remember the value of "${PATH}" when shellmock was loaded, including the
  # prepended mockbin dir.
  __SHELLMOCK_PATH="${PATH}"
  # By default, perform checks for changes made to PATH because that can prevent
  # mocking from working.
  declare -gx __SHELLMOCK__CHECKPATH=1
  # By default, we kill a mock's parent process in case there is an unexpected
  # call.
  declare -gx __SHELLMOCK__KILLPARENT=1

  # By default, we assert that all mocks have had their expectations asserted.
  # We do so only when running inside of bats because, otherwise, we cannot
  # easily determine the function at whose end we shall execute the trap.
  declare -gx __SHELLMOCK__ENSURE_ASSERTIONS
  declare -gx __SHELLMOCK_TRAP
  local return_trap
  return_trap="$(trap -p -- RETURN)"
  if [[ ${has_bats} -eq 1 ]] && [[ -z ${return_trap} ]]; then
    trap -- "__shellmock_internal_trap" RETURN
    __SHELLMOCK__ENSURE_ASSERTIONS=1
    __SHELLMOCK_TRAP="$(trap -p -- RETURN)"
  else
    local reason
    if [[ -n ${return_trap} ]]; then
      reason="Detected existing trap '${return_trap}' for RETURN signal."
    else
      reason="Not using bats to run tests."
    fi
    echo >&2 "${reason}" \
      "Shellmock will be unable to automatically ensure that" \
      "expectations have been asserted. Make sure to assert expectations" \
      "manually for every test."
    __SHELLMOCK__ENSURE_ASSERTIONS=0
    __SHELLMOCK_TRAP=
  fi
}

__shellmock_internal_bash_version_check() {
  if [[ -z ${BASH_VERSION-} ]]; then
    echo >&2 "Shellmock requires bash but different shell detected."
    return 1
  fi
  local major minor
  major="${BASH_VERSION%%.*}"
  minor="${BASH_VERSION#*.}"
  minor="${minor%%.*}"

  # Error out if the version is too low.
  if [[ ${major} -lt 4 ]] || [[ ${major} -eq 4 && ${minor} -lt 4 ]]; then
    echo >&2 "Shellmock requires bash >= 4.4 but ${BASH_VERSION} detected."
    return 1
  fi
}

# Check whether PATH changed since shellmock has been initialised. If it has
# changed, then shellmock's mocks might no longer be used preferentially.
__shellmock_internal_pathcheck() {
  if [[ ${__SHELLMOCK__CHECKPATH} -eq 1 ]] \
    && [[ ${PATH} != "${__SHELLMOCK_PATH}" ]]; then

    echo >&2 "WARNING: value for PATH has changed since loading shellmock, " \
      "mocking might no longer work."
  fi
}

# Check whether the pre-configured trap changed since shellmock has been
# initialised. If it has changed, then shellmock's automatic assertion detection
# will likely not work anymore.
__shellmock_internal_trapcheck() {
  if [[ ${__SHELLMOCK__ENSURE_ASSERTIONS} -eq 1 ]] \
    && [[ "$(trap -p -- RETURN)" != "${__SHELLMOCK_TRAP}" ]]; then

    echo >&2 "WARNING: RETURN trap has changed since loading shellmock," \
      "we will not be able to automatically ensure that expectations have" \
      "been asserted."
  fi
}

# This function is called as a trap (signal handler) for the RETURN signal. Due
# to the way bats works, it will be called pretty often at the end of many of
# bats's helper functions. Thus, we have to determine whether we are being
# called at the end of the actual test function because that is when we can test
# whether all expectations have been asserted.
__shellmock_internal_trap() {
  # Do not perform any actions if the auto-assert feature has been deactivated.
  # Do not perform any actions if we are not being called by the expected bats
  # test function.
  if
    [[ ${__SHELLMOCK__ENSURE_ASSERTIONS} -eq 1 &&
      "$(caller 0)" == *" ${BATS_TEST_NAME-} "* ]]
  then
    local defined_cmds
    readarray -d $'\n' -t defined_cmds < <(
      # shellmock: uses-command=basename
      find "${__SHELLMOCK_MOCKBIN}" -type f -print0 | xargs -r -0 -I{} basename {}
    ) && wait $!

    local cmd has_err=0
    for cmd in "${defined_cmds[@]}"; do
      if ! [[ -e "${__SHELLMOCK_EXPECTATIONS_DIR}/${cmd}" ]]; then
        local cmd_quoted
        cmd_quoted=$(printf "%q" "${cmd}")
        echo >&2 "ERROR: expectations for mock ${cmd} have not been asserted." \
          "Consider adding 'shellmock assert expectations ${cmd_quoted}' to" \
          "the following test: ${BATS_TEST_DESCRIPTION-}"
        has_err=1
      fi
    done
    # Exit the current process to indicate a test failure. This is how we can
    # signal a test failure from within a return trap. When running tests, we
    # only return, though, because bats would be unable to track the test if we
    # were to call exit here.
    if [[ ${__SHELLMOCK_TESTING_TRAP-0} -eq 1 ]]; then
      return "${has_err}"
    elif [[ ${has_err} -ne 0 ]]; then
      exit "${has_err}"
    fi
  fi
}

# Main shellmock command. Subcommands can be added by creating a shell function
# following a specific naming scheme. We avoid complex parsing of arguments with
# a tool such as getopt or getopts.
shellmock() {
  # Handle the user requesting a help text.
  for arg in "$@"; do
    if [[ ${arg} == --help ]]; then
      set -- "help"
      break
    fi
  done

  local cmd="$1"
  shift

  # Execute subcommand with arguments but only if they are shell functions and
  # exist.
  if [[ $(type -t "__shellmock__${cmd}") == function ]]; then
    "__shellmock__${cmd}" "$@"
  else
    echo >&2 "Unknown command for shellmock: ${cmd}." \
      "Call with --help to view the help text."
    return 1
  fi
}
