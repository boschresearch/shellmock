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

# This file contains the main entrypoint, namely the shellmock function.

# Main shellmock command. Subcommands can be added by creating a shell function
# following a specific naming scheme. We avoid complex parsing of arguments with
# a tool such as getopt or getopts.
shellmock() {
  # Ensure that only those shell options are set that shellmock needs.
  local - # Restrict all changes to shell options to this function.
  # Options available via "set". Options available via "shopt" cannot easily be
  # scoped to a function without using a RETURN trap, but we are already uisng
  # one for another purpose.
  local opt opts=() flags=()
  IFS=: read -r -a opts <<< "${SHELLOPTS}"
  for opt in "${opts[@]}"; do flags+=(+o "${opt}"); done
  set "${flags[@]}"
  # Set the ones we expect and need.
  set -euo pipefail

  # Main code follows.
  # Handle the user requesting a help text.
  local arg
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
