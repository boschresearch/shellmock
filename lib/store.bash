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

# Output a function as a reusable block of code. The generated script can be
# sourced to define the function. The generated script can also be executed to
# call the function. Arguments will be forwarded to the function.
__shellmock_internal_funcstore() {
  local cmd="$1"

  # Make sure the generated script will always be called with the same shell we
  # are using at the moment.
  printf "#!%s\n# " "${BASH}"
  type "${cmd}"
  PATH="${__SHELLMOCK_ORGPATH}" cat << 'EOF'
# Run only if executed directly.
if [[ -z ${BASH_SOURCE[0]-} ]] || [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
EOF
  printf '%s "$@"\n' "${cmd}"
  PATH="${__SHELLMOCK_ORGPATH}" cat << 'EOF'
else
  :
fi
EOF
}
