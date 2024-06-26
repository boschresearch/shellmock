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

# This file contains the definition of the global-config command.

# The global-config command that can be used to get and set some global options.
__shellmock__global-config() {
  __shellmock_internal_pathcheck
  __shellmock_internal_trapcheck

  local subcmd="$1"
  local arg="$2"
  local val="${3-}"

  local replacement="${arg//-/_}"
  replacement="${replacement^^}"

  case ${subcmd} in
  setval)
    case ${arg} in
    checkpath | killparent | ensure-assertions)
      if [[ -z ${val-} ]]; then
        echo >&2 "Value argument to setval must not be empty."
        return 1
      fi
      local varname="__SHELLMOCK__${replacement}"
      declare -gx "${varname}=${val}"
      ;;
    *)
      echo >&2 "Unknown global config to set: $2"
      return 1
      ;;
    esac
    ;;
  getval)
    case ${arg} in
    checkpath | killparent | ensure-assertions)
      local varname="__SHELLMOCK__${replacement}"
      echo "${!varname}"
      ;;
    *)
      echo >&2 "Unknown global config to get: $2"
      return 1
      ;;
    esac
    ;;
  *)
    echo >&2 "Unknown sub-command for shellmock global-config: $1"
    return 1
    ;;
  esac
}
