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
  if [[ -z ${BATS_RUN_TMPDIR} ]]; then
    has_bats=0
  fi
  # Modify PATH to permit injecting executables.
  declare -gx __SHELLMOCK_MOCKBIN
  __SHELLMOCK_MOCKBIN="$(mktemp -d -p "${BATS_RUN_TMPDIR-${TMPDIR-/tmp}}")"
  mkdir -p "${__SHELLMOCK_MOCKBIN}"
  export PATH="${__SHELLMOCK_MOCKBIN}:${PATH}"

  declare -gx __SHELLMOCK_OUTPUT
  __SHELLMOCK_OUTPUT="$(mktemp -d -p "${BATS_RUN_TMPDIR-${TMPDIR-/tmp}}")"
  mkdir -p "${__SHELLMOCK_OUTPUT}"

  if [[ ${has_bats} -eq 0 ]]; then
    echo >&2 "Running outside of bats, temporary directories will be kept."
    echo >&2 "Keeping mocks in: ${__SHELLMOCK_MOCKBIN}"
    echo >&2 "Keeping mock call data in: ${__SHELLMOCK_OUTPUT}"
  fi

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
}

__shellmock_internal_bash_version_check() {
  if [[ -z ${BASH_VERSION} ]]; then
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
# changed, the shellmock's mocks might no longer be used preferentially.
__shellmock_internal_pathcheck() {
  if [[ ${__SHELLMOCK__CHECKPATH} -eq 1 ]] \
    && [[ ${PATH} != "${__SHELLMOCK_PATH}" ]]; then

    echo >&2 "WARNING: value for PATH has changed since loading shellmock, " \
      "mocking might no longer work."
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
