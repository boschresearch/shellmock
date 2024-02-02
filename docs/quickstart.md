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

# Quickstart Guide

Now that we have downloaded `shellmock` to the root directory of our repository
and installed [bats-core] on our system, we can create a simple test.
We put the following in a file called `test.bats`:

```bash
#!/usr/bin/env bats
setup() {
  # Load the self-contained shellmock library.
  load shellmock
}

@test "shellmock works" {
  # Create a new mock for the curl command. Curl is just used as an
  # arbitrary example command here.
  shellmock new curl
  # Configure the mock, specifying expectations.
  shellmock config curl 0 2:http://www.google.com
  # Try to call curl. The mock will be called instead.
  curl -v http://www.google.com
  # Check that the expected calls and only those calls have happened.
  shellmock assert expectations curl
}
```

With that in place, we can run `bats ./test.bats` to execute the test.
We should see the following output:

```
test.bats
 ✓ that shellmock works

1 test, 0 failures
```

If not, something is wrong with our installation of either `shellmock` or
`bats-core.`

What happens in details:

- `load shellmock`

  This line causes `bats` to load the `shellmock` library, making the
  `shellmock` command with all its sub-commands available.

- `shellmock new curl`

  This line creates a mock executable called `curl` in a directory `shellmock`
  controls.
  Then, `shellmock` will modify the `PATH` environment variable to make sure
  that the mock it controls is used preferentially to the actual `curl`
  executable on our system.

- `shellmock config curl 0 2:http://www.google.com`

  This line configures the mock.
  Here, we specify the arguments we expect our command to be called with, as
  well as the mock's exit status code.

  - `0`:
    The desired exit status code of the mock (`0` means "success")
  - `2:http://www.google.com`:
    We state that the second argument of the command is expected to be the
    literal string `http://www.google.com`.
    Note that counting arguments starts at 1.
    Any other argument could have any value and the mock would accept it.

- `shellmock assert expectations curl`

  This line asserts that the configured call has been issued to the mock.
  This command will have a non-zero (failure) exit code in either of the two
  following cases:

  1. There has been an unexpected call.
     That is, the mock has been called with arguments that have not been
     declared via a previous call to `shellmock config`.
  1. An expected call is missing.
     That is, the mock has not been called with at least one set of arguments
     that match a previous call to `shellmock config`.

Please have a look at the [full command reference](./usage.md) for all
details.
You can also have a look at [this detailed example](./example.md) or
[shellmock's own tests][shellmock-tests].
You may also check out our [how-to for creating tests](./howto.md).

[shellmock-tests]: ../tests/main.bats "shellmock tests"
[bats-core]: https://bats-core.readthedocs.io/ "bats core website"
