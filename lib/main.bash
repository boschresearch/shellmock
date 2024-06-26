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
