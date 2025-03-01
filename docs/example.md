<!---
  Copyright (c) 2022 - for information on the respective copyright owner
  see the NOTICE file or the repository
  https://github.com/boschresearch/shellmock

  Licensed under the Apache License, Version 2.0 (the "License"); you may not
  use this file except in compliance with the License. You may obtain a copy of
  the License at

    http://www.apache.org/licenses/LICENSE-2.0

  Unless required by applicable law or agreed to in writing, software
  distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
  WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
  License for the specific language governing permissions and limitations under
  the License.
-->

# Detailed Example

This example first presents a script that shall then be tested using [bats-core]
and `shellmock`.

Assume a shell script of medium complexity that checks out a `git` branch.
If the branch does not yet exist, the script creates it first.
That script could look like this:

```bash
#!/bin/bash
# Read argument to script.
branch_name="${1-}"
# Ensure the argument is non-empty.
if [[ -z "${branch_name}" ]]; then
  echo "Empty argument received." >&2
  # The "false" command always exits with an error. It's the last one executed
  # and, thus, its exit code will be the one of this script. It is important not
  # to call the "exit" command in scripts that should be easy to test.
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
```

There are a few obvious tests you could perform.
For example, you could test:

- the success case with a missing branch,
- the success case with an existing branch, or
- the failure case with empty input.

The below examples assume some familiarity with [bats-core].
If you want to get started with [bats-core]-based testing, we can recommend this
[bats testing guide][bats-guide].
Although, instead of installing [bats-core] as a `git` sub-module, we recommend
a user-space installation via `npm` via `npm install -g bats`.

Below, you can find the three example tests mentioned above.

```bash
#!/usr/bin/env bats

setup_file() {
  # Ensure we use the minimum required bats version for the "run" built-in.
  bats_require_minimum_version 1.5.0
}

setup() {
  # Load the downloaded shellmock library. The ".bash" extension is added
  # automatically. The path is interpreted relative to the file containing the
  # tests.
  load shellmock
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
  # been an unexpected call, e.g. to " git branch", or if one of the configured
  # calls hadn't happened, this line would error out and report the problem.
  shellmock assert expectations git
  # Assert on the exit code.
  [[ ${status} == 0 ]]
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
  # Configure the mock to have an exit code of 0 if it is called with the
  # branch command and the -l argument. The mock will write "* some branch" to
  # stdout. The first matching config will be used.
  shellmock config git 0 1:branch 2:-l <<< "* some_branch"
  # The checkout command should also succeed for any feature branch.
  shellmock config git 0 1:checkout regex-2:"^feature/.*$"
  run "${script}" "feature/some-feature"
  shellmock assert expectations git
  [[ ${status} == 0 ]]
}

@test "the failure case with empty input" {
  # Shadow the original git executable by a mock. This is just to make sure we
  # do not call the actual git executable by accident.
  shellmock new git
  # Note that we do not run the command "shellmock config" here. That means that
  # the mock does not expect to be called at all. Any call to the mock would be
  # considered an error when asserting expectations below.
  run "${script}"
  shellmock assert expectations git
  # Assert on the exit code. We expect a non-zero exit code.
  [[ ${status} != 0 ]]
}
```

The above example calls the script itself via the `run` built-in.
For more complex scripts, you want to be able to test parts of it instead of the
whole script at once.
To do so, you need to use shell functions throughout and source the script in
your tests.
Doing so will allow you to test individual functions.
You can also mock functions called by your own functions.
Please have a look at [shellmock's own tests][shellmock-tests] for what is
possible.

<!-- link-category: how to set up and use -->

[bats-core]: https://bats-core.readthedocs.io/ "bats core website"
[bats-guide]: https://bats-core.readthedocs.io/en/stable/tutorial.html "bats guide"
[shellmock-tests]: ../tests/main.bats "shellmock tests"
