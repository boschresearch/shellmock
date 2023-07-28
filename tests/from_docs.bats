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
  branch_name="$1"
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
  fi
}

@test "the success case with an existing branch" {
  # Shadow original git executable by a mock.
  shellmock new git
  # Configure the mock to have an exit code of 0 if it is called with the
  # rev-parse command. This simulates git reporting that the branch exists. The
  # name can be at any position.
  shellmock config git 0 1:rev-parse any:some_branch
  # Configure the mock to have an exit code of 0 if it is called with the
  # checkout command and a specific branch name.
  shellmock config git 0 1:checkout 2:some_branch
  # Now run your script via the "run" built-in. Here "${script}" contains the
  # path to your executable script. We use a shell function here.
  run "${script}" some_branch
  # Now assert that the calls you expected have indeed happened. If there had
  # been an unexpected call, e.g. to " git branch", this line would error out
  # and report the problem.
  shellmock assert expectations git
  # Assert on the exit code.
  [[ ${status} -eq 0 ]]
}

@test "the success case with a missing branch" {
  shellmock new git
  # Configure the mock to have an exit code of 1 if it is called with the
  # rev-parse command for a feature branch. This simulates git reporting that
  # the branch does not exist. We match an argument at any position with a bash
  # regular expression.
  shellmock config git 1 1:rev-parse regex-any:"^feature/.*$"
  # Configure the mock to have an exit code of 0 if it is called with the
  # branch command and a specific branch name. We match the branch name, which
  # is argument 2, with a bash regular expression.
  shellmock config git 0 1:branch regex-2:"^feature/.*$"
  # The checkout command should also succeed for any feature branch.
  shellmock config git 0 1:checkout regex-2:"^feature/.*$"
  run "${script}" "feature/some-feature"
  shellmock assert expectations git
  [[ ${status} -eq 0 ]]
}

@test "the failure case with empty input" {
  # Shadow the original git executable by a mock. This is just to make sure we
  # do not call the actual git executable by accident.
  shellmock new git
  run "${script}"
  shellmock assert expectations git
  # Assert on the exit code. We expect a non-zero exit code.
  [[ ${status} -ne 0 ]]
}
