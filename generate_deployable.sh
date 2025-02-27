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

_cat() {
  (
    local line
    IFS=
    while read -d $'\n' -r line; do
      printf -- '%s\n' "${line}"
    done
  )
}

deployable() {
  # Output header including the licence file.
  echo '#!/bin/bash'
  (
    IFS=
    while read -r line; do
      echo "# ${line}"
    done < LICENSE
  )
  _cat << 'EOF'

# This file is auto-generated. It is the main deployable of shellmock. To make
# contributions to shellmock, please visit the repository under:
# https://github.com/boschresearch/shellmock

EOF
  # Output all bats helper files containing function definitions.
  for bats_file in lib/*.bash; do
    printf -- "\n# FILE: %s\n" "${bats_file}"
    _cat < "${bats_file}"
  done

  # Create a function providing the help text.
  _cat << 'ENDOFFILE'
__shellmock__help() {
  "${PAGER-cat}" << 'EOF'
This is shellmock, a tool to mock executables called within shell scripts.
ENDOFFILE

  # Add helptexts from the usage docs, but only a reduced version. The docs are
  # enclosed by the HTML comments given below.
  (
    local line
    IFS=
    do_print=0
    while read -r line; do
      if [[ ${line} == '<!-- shellmock-helptext-end -->' ]]; then
        do_print=0
      fi
      if [[ ${do_print} == 1 ]]; then
        echo "${line}"
      fi
      if [[ ${line} == '<!-- shellmock-helptext-start -->' ]]; then
        do_print=1
      fi
    done < ./docs/usage.md
  )

  _cat << 'ENDOFFILE'
EOF
}
ENDOFFILE

  # Create a function that outputs the mock executable to its stdout.
  _cat << 'EOF'

# Mock executable writer.
__shellmock_write_mock_exe() {
EOF

  echo "PATH=\"\${__SHELLMOCK_ORGPATH}\" cat << 'ENDOFFILE'"
  _cat < ./bin/mock_exe.sh

  _cat << 'EOF'
ENDOFFILE
}

# Internal Go code used to check used commands in shell code.
__shellmock_internal_init_command_search() {
  local path=$1
EOF

  echo "PATH=\"\${__SHELLMOCK_ORGPATH}\" cat > \"\${path}/go.mod\"  << 'ENDOFFILE'"
  _cat < ./go/go.mod

  _cat << 'EOF'
ENDOFFILE
EOF

  echo "PATH=\"\${__SHELLMOCK_ORGPATH}\" cat > \"\${path}/main.go\"  << 'ENDOFFILE'"
  _cat < ./go/main.go

  _cat << 'EOF'
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
