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

# shellmock <!-- omit in toc -->

- [Quickstart Guide](#quickstart-guide)
  - [Dependencies](#dependencies)
- [Further examples](#further-examples)
- [Feedback](#feedback)
- [About](#about)
  - [Maintainers](#maintainers)
  - [License](#license)

This is the `shellmock` project, a mocking framework for shell scripts.
It works well with the [bats-core] testing framework.
You can find our technical documentation [here](./docs/README.md).
Inspiration for `shellmock` was taken from testing frameworks such as `pytest`
and `golang/mock`.

[bats-core]: https://bats-core.readthedocs.io/ "bats core website"

## Quickstart Guide

If you simply want to get this show in the road, just head over to the
[releases], download the [latest release][latest-release].
Then, you can write your [bats-core]-based tests.
Just make sure to use `load shellmock` in your `setup` function.
You can also have a look at [this example](./docs/example.md) or
[shellmock's own tests][shellmock-tests].

The [technical documentation](./docs/README.md) will go more in depth on how to
use `shellmock` to mock any commands but here is a simple example of the command
and what each parameter does.

```bash
# Source the self-contained shellmock library, which makes the shellmock command
# available. This is replaced by "load shellmock" in bats-based tests.
. shellmock.bash
# Instantiate a new mock for the curl command.
shellmock new curl
# Configure the mock, expecting the 2nd argument to be a specific URL.
shellmock config curl 0 2:http://www.google.com
# Calling the curl command in verbose mode. The mock will be called instead.
curl -v http://www.google.com
# Check that the expected calls and only those calls have happened.
shellmock assert expectations curl
```

The `shellmock` command:

- `shellmock new curl`

  Create a mock executable called `curl` in a directory `shellmock` controls.
  Then, `shellmock` will modify the `PATH` environment variable to make sure
  that the mock it controls is used preferentially to the actual `curl`
  executable on your system.

- `shellmock config curl 0 2:http://www.google.com`

  Configure the mock.
  Here, you specify the arguments you expect your command to be called with, as
  well as the mock's exit status code.

  - `0`:
    the exit status code of the mock (`0` means "success")
  - `2:http://www.google.com`:
    State that the second argument of the command is expected to be the literal
    string `http://www.google.com`.
    Note that counting arguments starts at 1.
    Any other argument could have any value and the mock would accept it.

- `shellmock assert expectations curl`

  Assert that the configured call has been issued to the mock.
  This command will have a non-zero (failure) exit code if

  - the mock has been called with arguments that have not been declared via a
    previous call to `shellmock config` (i.e. an unexpected call), or
  - the mock has not been called with at least one set of arguments specified
    via a previous call to `shellmock config` (i.e. an expected call is
    missing).

Please have a look at the [full command reference](./docs/usage.md) for all
details.

[shellmock-tests]: ./tests/main.bats "shellmock tests"
[releases]: https://github.com/boschresearch/shellmock/releases "releases"
[latest-release]: https://github.com/boschresearch/shellmock/releases/latest "latest release"

### Dependencies

The following tools are needed to use `shellmock`:

- `base32`
- `base64`
- `bash` (at least version 4.4)
- `cat`
- `env`
- `find`
- `gawk`
- `grep`
- `sed`
- `sort`
- `tr`
- `xargs`

On Debian-based systems, they can be installed via:

```bash
sudo apt install -yqq coreutils findutils gawk grep sed
```

## Further examples

As mentioned before, you can check out more examples in
[shellmock's own tests][shellmock-tests].
A non-exhaustive list of examples follows:

- Mock an executable
- Mock functions
- Mock with non-zero exit code
- Match positional arguments, both with fixed and flexible positions
- Create a mock that is writing a fixed string to stdout
- Kill the parent process when there is an unexpected call to fail a test

## Feedback

Like what we did?
Great, we’d love to hear that.
Don’t like it?
Not so great!
But we are eager to hear your feedback on how we could improve!

## About

### Maintainers

['Torsten Long'](https://github.com/razziel89)

### License

Shellmock is open-sourced under the Apache-2.0 license.
See the [LICENSE](./LICENSE) file for details.

> Copyright (c) 2022 - for information on the respective copyright owner
> see the NOTICE file or the repository
> https://github.com/boschresearch/shellmock
>
> Licensed under the Apache License, Version 2.0 (the "License"); you may not
> use this file except in compliance with the License. You may obtain a copy of
> the License at
>
> http://www.apache.org/licenses/LICENSE-2.0
>
> Unless required by applicable law or agreed to in writing, software
> distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
> WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
> License for the specific language governing permissions and limitations under
> the License.

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
