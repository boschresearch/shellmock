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

# This script generates the shellmock deployable. That is, it generates a single
# file that can be imported to a bats test suite to provide all the
# functionality of shellmock.

__SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/" &> /dev/null && pwd)"

deployable() {
  # Output header including the licence file.
  echo '#!/bin/bash'
  sed 's/^/# /' LICENSE
  cat << 'EOF'

# This file is auto-generated. It is the main deployable of shellmock. To make
# contributions to shellmock, please visit the repository under:
# https://github.com/boschresearch/shellmock

EOF
  # Output all bats helper files containing function definitions.
  for bats_file in lib/*.bash; do
    printf -- "\n# FILE: %s\n" "${bats_file}"
    cat "${bats_file}"
  done

  # Create a function providing the help text.
  cat << 'ENDOFFILE'
__shellmock__help() {
  "${PAGER-cat}" << 'EOF'
This is shellmock, a tool to mock executables called within shell scripts.
ENDOFFILE

  awk \
    -v start='<!-- shellmock-helptext-start -->' \
    -v end='<!-- shellmock-helptext-end -->' \
    'BEGIN{act=0} {if($0==end){act=0}; if(act==1){print}; if($0==start){act=1;};}' \
    ./docs/usage.md

  cat << 'ENDOFFILE'
EOF
}
ENDOFFILE

  # Create a function that outputs the mock executable to its stdout.
  cat << 'EOF'

# Mock executable writer.
__shellmock_write_mock_exe() {
EOF

  echo "cat << 'ENDOFFILE'"
  cat ./bin/mock_exe.sh

  cat << 'EOF'
ENDOFFILE
}

# Run initialisation steps.
__shellmock_internal_init
EOF
}

main() {
  cd "${__SCRIPT_DIR}" || exit 1
  deployable > shellmock.bash
}

main
