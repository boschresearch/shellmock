#!/usr/bin/env bats

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

setup_file() {
  # Ensure we use the minimum required bats version for the "run" built-in.
  bats_require_minimum_version 1.5.0
}

setup() {
  # Load the downloaded shellmock library. The ".bash" extension is added
  # automatically.
  load ../shellmock
  script=script
}

# We replace the script with a function to have a self-contained example.
script() {
  #!/bin/bash
  # Read argument to script.
  branch_name="${1-}"
  # Ensure the argument is non-empty.
  if [[ -z ${branch_name} ]]; then
    echo "Empty argument received." >&2
    # This command always exits with an error. It's the last one executed and,
    # thus, its exit code will be the one of this script. It is important not to
    # call the "exit" command in scripts that should be easy to test.
    false
  else
    # Check whether the branch exists.
    if ! git rev-parse --quiet --verify "${branch_name}"; then
      # Branch does not yet exist, create it.
      git branch "${branch_name}"
    fi
    # Check out the branch. It is guaranteed to exist.
    git checkout "${branch_name}"
    # List all existing branches at the end, informing the user which branches
    # exist at the moment.
    echo "Current branches:"
    git branch -l
  fi
}

@test "the success case with an existing branch" {
  # Shadow original git executable by a mock.
  shellmock new git
  # Configure the mock to have an exit code of 0 if it is called with the
  # rev-parse command. This simulates git reporting that the branch exists. The
  # name must be at position 4. The values at positions 2 and 3 do not matter.
  shellmock config git 0 1:rev-parse 4:some_branch
  # Configure the mock to have an exit code of 0 if it is called with the
  # checkout command and a specific branch name. The branch name can be at any
  # position.
  shellmock config git 0 1:checkout any:some_branch
  # Configure the mock to have an exit code of 0 if it is called with the
  # branch command and the -l argument. The mock will write "* some branch" to
  # stdout.
  shellmock config git 0 1:branch 2:-l <<< "* some_branch"
  # Now run your script via the "run" built-in. Here "${script}" contains the
  # path to your executable script.
  run "${script}" some_branch
  # Now assert that the calls you expected have indeed happened. If there had
  # been an unexpected call, e.g. to " git branch", this line would error out
  # and report the problem.
  shellmock assert expectations git
  # Assert on the exit code.
  [[ ${status} == 0 ]]
}

@test "the success case with a missing branch" {
  shellmock new git
  # Configure the mock to have an exit code of 1 if it is called with the
  # rev-parse command for a feature branch. This simulates git reporting that
  # the branch does not exist. We use a prefix match at any position.
  shellmock config git 1 1:rev-parse prefix-any:"feature/"
  # Configure the mock to have an exit code of 0 if it is called with the
  # branch command and a specific branch name. We match the branch name, which
  # is argument 2, with a bash regular expression.
  shellmock config git 0 1:branch regex-2:"^feature/.*$"
  # Configure the mock to have an exit code of 0 if it is called with the
  # branch command and the -l argument. The mock will write "* some branch" to
  # stdout. The first matching config will be used. Using value-1 or just 1 on
  # the left side of an argspec is identical, the former is just more explicit.
  shellmock config git 0 value-1:branch 2:-l <<< "* some_branch"
  # The checkout command should also succeed for any branch whose name
  # starts with "some". Branch designations typically start with the type
  # followed by a slash and then followed by the actual name.
  shellmock config git 0 1:checkout substring-2:"/some-"
  run "${script}" "feature/some-feature"
  shellmock assert expectations git
  [[ ${status} == 0 ]]
}

@test "the failure case with empty input" {
  # Shadow the original git executable by a mock. This is just to make sure we
  # do not call the actual git executable by accident.
  shellmock new git
  run "${script}"
  shellmock assert expectations git
  # Assert on the exit code. We expect a non-zero exit code.
  [[ ${status} != 0 ]]
}

@test "enforcing the number of arguments" {
  shellmock new my_exe_noextra
  shellmock config my_exe_noextra 0 set-4: !set-i:
  shellmock new my_exe_extra
  shellmock config my_exe_extra 0 set-4: !set-i:

  run -0 my_exe_noextra one two three four
  run ! my_exe_extra one two three four five

  shellmock assert expectations my_exe_noextra
  run ! shellmock assert only-expected-calls my_exe_extra
  [[ ${output} == *"SHELLMOCK: unexpected call 'my_exe_extra"* ]]
}

@test "different ways of providing multi-line stdout" {
  shellmock new my_exe
  # This is not real multi-line output but a literal \n embedded in a string.
  shellmock config my_exe 0 1:literal <<< 'first\nsecond\n'
  shellmock config my_exe 0 1:newlines <<< "first
second
"
  shellmock config my_exe 0 1:heredoc << EOF
first
second
EOF
  shellmock config my_exe 0 1:ansi <<< $'first\nsecond\n'

  run -0 my_exe literal
  [[ ${output} == 'first\nsecond\n' ]]
  run -0 my_exe newlines
  [[ ${output} == $'first\nsecond' ]]
  run -0 my_exe heredoc
  [[ ${output} == $'first\nsecond' ]]
  run -0 my_exe ansi
  [[ ${output} == $'first\nsecond' ]]
  shellmock assert expectations my_exe
}
