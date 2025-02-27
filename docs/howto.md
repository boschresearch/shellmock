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

# How to

This document guides you through the process of writing tests using `shellmock`.
It assumes some familiarity with [bats-core].
If you want to get started with [bats-core]-based testing, we can recommend this
[bats testing guide][bats-guide].
Although, instead of installing [bats-core] as a `git` sub-module, we recommend
a user-space installation via `npm` via `npm install -g bats`.

The process of creating `shellmock`-based tests described here can be divided
into the following steps:

1. Refactor the script.
1. Devise test cases.
1. Decide which executables are worth mocking.
1. Write the tests.

We recommend this approach because it can be rather difficult to know which
executables to mock before having written the actual script.

## Refactoring the script

_You_ know what your script is supposed to so, so use all the power of the shell
to write it.
Then, refactor it as a next step, keeping the following in mind.

### Partitioning

If your script is relatively complex, it makes sense to test only parts of it.
To be able to do so, define functions that can be used elsewhere in the script.
That is, prefer outsourcing common functionality into functions:

```bash
# Get all git tags matching a regex.
matching_git_tags() {
  local regex=$1
  git tag --list | grep "${regex}"
}

# Elsewhere in the script.
tags=($(matching_git_tags "^v"))
```

Over calling the code inline, possibly in multiple locations:

```bash
tags=($(git tag --list | grep -E "^v"))
```

The reason is that the function can be tested independently while any test of
the inlined code would have to take into account the surrounding code.

### Single-purpose

To be easy to test, your script should fulfil a single purpose.
It can take flags to modify its behaviour, but the more complex the script gets,
the harder it becomes to test.
If your script combines multiple purposes, consider splitting it into multiple
library files and `source` them from the main script.
That is, prefer outsourcing functions into separate files:

```bash
# This is the main script.
# Load functionality for interacting with our API.
source ./api.sh
# Load functionality for interacting with the file system.
source ./fs.sh

# Execute the main code.
# [...]
```

Over defining everything in a single file:

```bash
# This is the main script.
# Functionality for interacting with our API.
rest_call() {
  # [...]
}
# Functionality for interacting with the file system.
read_from_file() {
  # [...]
}

# Execute the main code.
# [...]
```

The reason is that separate files provide a way of grouping functionality.
Furthermore, the library files can be tested independently of the rest of the
code.

### Library and executable

If your script is relatively complex, it makes sense to test only parts of it.
To be able to do so, you have to be able to load all the functions it defines
without actually executing it.
Thus, prefer not executing code at the root of your script:

```bash
main() {
  # [...]
}

# Do not execute `main` if this script is being sourced from a bash script.
if [[ -z ${BASH_SOURCE[0]-} ]] || [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
  main "$@"
fi
```

Over executing code directly:

```bash
main() {
  # [...]
}

# Execute `main` at the bottom of the script.
main "$@"
```

## Devising test cases

In general, consider what the script should do in the case of success and in the
most common error cases.
But it is hard to come up with test cases without a concrete example.
So let's look at one - a script that asks the user which `shellmock` release to
download, listing all available releases.
Such a script, using functions to improve readability, could look as follows:

```bash
#!/bin/bash
# This is in a file `github.sh`.

# Global constants.
GITHUB_API=https://api.github.com
ORG_AND_REPO=boschresearch/shellmock
ASSET=shellmock.bash

# See https://docs.github.com/en/rest/releases/releases?apiVersion=2022-11-28#list-releases
get_release_data() {
  curl -sSf -L "${GITHUB_API}/repos/${ORG_AND_REPO}/releases" < /dev/null
}

get_release_names() {
  get_release_data | jq -r ".[].name" | sort -n | sed '/^$/d'
}

filter_release_asset() {
  local release=$1
  local asset=$2
  jq ".[] | select(.name == \"${release}\")" \
    | jq ".assets[] | select(.name == \"${asset}\")"
}

download_release() {
  local release=$1
  echo >&2 "Downloading release ${release}."

  local asset_data
  asset_data=$(get_release_data | filter_release_asset "${release}" "${ASSET}")
  if [[ -z ${asset_data} ]]; then
    echo >&2 "Release ${release} not found."
    return 1
  fi

  local asset_url
  asset_url=$(jq -r ".browser_download_url" <<< "${asset_data}")
  curl -sSf -L -o "${ASSET}" "${asset_url}"
}

main() {
  local releases
  mapfile -t releases < <(get_release_names)
  if [[ ${#releases[@]} == 0 ]]; then
    echo >&2 "Failed to get releases or no releases available."
    return 1
  fi
  echo >&2 "Available releases: ${releases[*]}"

  local release
  read -r -p "Select release to download (empty is latest): " release
  # If there are releases, select latest release if left empty.
  if [[ ${#releases[@]} -gt 0 && -z ${release} ]]; then
    release=${releases[-1]}
  fi

  download_release "${release}"
}

# Do not execute `main` if this script is being sourced from a bash script.
if [[ -z ${BASH_SOURCE[0]-} ]] || [[ ${BASH_SOURCE[0]} == "${0}" ]]; then
  main
fi
```

Some obvious test cases come to mind:

1. The script downloads the latest release if the user does not request a
   specific one.
1. The script errors out if the user requests a release that does not exist.

## Deciding which executables are worth mocking.

One important step of testing shell scripts with `shellmock` is to decide which
executables to mock.
First, imagine we wanted to mock every single executable used.
We would end up with tests that are significantly more complex than the script,
and they would not even test any actual logic.
Instead, they would only test the interactions of the mocks.

The above script uses some executables, namely `curl`, `jq`, `sed`, and `sort`.
However, all apart from `curl` are free of side effects in this case.
That is, only `curl` interacts with outside systems, i.e. GitHub's REST API, or
makes modifications to the machine running the script, i.e. when downloading the
asset.
All the other executables filter their input and produce output that only
depends on the input.

Given the above, the only executable that makes sense to mock in this case is
`curl`.

## Writing the tests.

To mock calls to `curl`, we first have to find out the actual arguments passed
to the executables.
We can derive them from the script ourselves or we can use the command
`shellmock calls`.
To be able to use that command, we have to set up a "catch-all" mock that
accepts any call to `curl` and then use `shellmock calls curl` to retrieve the
calls made.
The first draft of the test file will look like this:

```bash
#!/usr/bin/env bats
# This file is `test.bats` and lies next to `github.sh`. The file
# `shellmock.bash` is in the same directory.

setup() {
  load shellmock
  source ./github.sh
}

@test "downloading the latest release if none requested" {
  # Shadow the curl executable with a mock.
  shellmock new curl
  # Set up a catch-all mock to accept any call to curl.
  shellmock config curl 0
  # Providing empty stdin to select latest release.
  run main <<< ""
  # Retrieve calls made. This will fail the test automatically.
  shellmock calls curl
}

@test "refusing to download a non-existent release" {
  shellmock new curl
  shellmock config curl 0
  # Providing non-existing release via stdin.
  run main <<< "0.0.0"
  shellmock calls curl
}
```

Run the tests with `bats --print-output-on-failure ./test.bats`.
For both tests, you will receive output like this:

```
 ✗ downloading the latest release if none requested
   (from function `__shellmock_internal_trap' in file shellmock.bash, line 786,
    from function `__shellmock__calls' in file shellmock.bash, line 640,
    from function `shellmock' in file shellmock.bash, line 834,
    in test file test.bats, line 34)
     `shellmock calls curl' failed
   name:       curl
   id:         1
   args:       -sSf -L https://api.github.com/repos/boschresearch/shellmock/releases
   stdin:
   suggestion: shellmock config curl 0 1:-sSf 2:-L 3:https://api.github.com/repos/boschresearch/shellmock/releases <<< ''

   name:       curl
   id:         2
   args:       -sSf -L https://api.github.com/repos/boschresearch/shellmock/releases
   stdin:
   suggestion: shellmock config curl 0 1:-sSf 2:-L 3:https://api.github.com/repos/boschresearch/shellmock/releases
```

The output's `args` line shows which arguments were passed to `curl`.
The `suggestion` line provides a command that, if copied and pasted into the
test, will set up the mock to accept exactly this call.
We do so, leaving out the arguments 1 `-sSf` and 2 `-L` because we do not
consider them important for the test.
Note that we also have to add a global constant that contains the payload we
would expect from GitHub's API and feed that payload to the mock.
The `calls` command cannot determine which stdout we want our mock to produce.
In any case, we will arrive at this test file next:

```bash
#!/usr/bin/env bats
# This file is `test.bats` and lies next to `github.sh`. The file
# `shellmock.bash` is in the same directory.

setup() {
  load shellmock
  source ./github.sh
}

RELEASE_DATA_FOR_TESTS='
[
  {"name": "0.4.0",
   "assets": [{
     "name": "shellmock.bash",
     "browser_download_url": "https://github.com/boschresearch/shellmock/releases/download/0.4.0/shellmock.bash"
    }]
  },
  {"name": "0.3.0",
   "assets": [{
     "name": "shellmock.bash",
     "browser_download_url": "https://github.com/boschresearch/shellmock/releases/download/0.3.0/shellmock.bash"
  }]}
]
'

@test "downloading the latest release if none requested" {
  shellmock new curl
  shellmock config curl 0 \
    3:https://api.github.com/repos/boschresearch/shellmock/releases \
    <<< "${RELEASE_DATA_FOR_TESTS}"
  # Providing empty stdin to select latest release.
  run main <<< ""
  shellmock calls curl
}

@test "refusing to download a non-existent release" {
  shellmock new curl
  shellmock config curl 0 \
    3:https://api.github.com/repos/boschresearch/shellmock/releases \
    <<< "${RELEASE_DATA_FOR_TESTS}"
  # Providing non-existing release via stdin.
  run main <<< "0.0.0"
  shellmock calls curl
}
```

Running the tests again, `shellmock calls` reports an additional call to `curl`
for the first test, which we also have to configure.
Doing so, we arrive at our final test file.
Note that we also removed the catch-all mocks as well as the calls to `shellmock
calls`.
Instead, we asserted some expectations that we have.

```bash
#!/usr/bin/env bats
# This file is `test.bats` and lies next to `github.sh`. The file
# `shellmock.bash` is in the same directory.

setup() {
  load shellmock
  source ./github.sh
}

RELEASE_DATA_FOR_TESTS='
[
  {"name": "0.4.0",
   "assets": [{
     "name": "shellmock.bash",
     "browser_download_url": "https://github.com/boschresearch/shellmock/releases/download/0.4.0/shellmock.bash"
    }]
  },
  {"name": "0.3.0",
   "assets": [{
     "name": "shellmock.bash",
     "browser_download_url": "https://github.com/boschresearch/shellmock/releases/download/0.3.0/shellmock.bash"
  }]}
]
'

@test "downloading the latest release if none requested" {
  shellmock new curl
  shellmock config curl 0 \
    3:https://api.github.com/repos/boschresearch/shellmock/releases \
    <<< "${RELEASE_DATA_FOR_TESTS}"
  shellmock config curl 0 \
    3:-o \
    4:shellmock.bash \
    5:https://github.com/boschresearch/shellmock/releases/download/0.4.0/shellmock.bash
  # Providing empty stdin to select latest release.
  run main <<< ""
  # Make assertions.
  shellmock assert expectations curl
  [[ ${status} == 0 ]]
  [[ ${output} == *"Downloading release 0.4.0"* ]]
}

@test "refusing to download a non-existent release" {
  shellmock new curl
  shellmock config curl 0 \
    3:https://api.github.com/repos/boschresearch/shellmock/releases \
    <<< "${RELEASE_DATA_FOR_TESTS}"
  # Providing non-existing release via stdin.
  run main <<< "0.0.0"
  # Make assertions.
  shellmock assert expectations curl
  [[ ${status} != 0 ]]
  [[ ${output} == *"Release 0.0.0 not found."* ]]
}
```

[bats-core]: https://bats-core.readthedocs.io/ "bats core website"
[bats-guide]: https://bats-core.readthedocs.io/en/stable/tutorial.html "bats guide"
