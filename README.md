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

- [Installation](#installation)
  - [Dependencies](#dependencies)
- [Documentation Overview](#documentation-overview)
- [Feedback](#feedback)
- [About](#about)
  - [Maintainers](#maintainers)
  - [License](#license)

This is the `shellmock` project, a mocking framework for shell scripts.
It works well with the [bats-core] testing framework.
You can find our documentation [below](#documentation-overview).
Inspiration for `shellmock` was taken from testing frameworks such as `pytest`
and `golang/mock`.

[bats-core]: https://bats-core.readthedocs.io/ "bats core website"

## Installation

To get started, just head over to the [releases] and download the
[latest release][latest-release].
Then, you can write your [bats-core]-based tests.
Just make sure to use `load shellmock` in your `setup` function.
See [below](#documentation-overview) for `shellmock`'s documentation.

### Dependencies

The following tools are needed to use `shellmock`:

- `base32`
- `bash` (at least version 4.4)
- `cat`
- `chmod`
- `mkdir`
- `mktemp`
- `rm`

On Debian-based systems, they can be installed via:

```bash
sudo apt install -yqq bash coreutils
```

You also need the [bats-core] testing framework that
[can be installed via npm following its docs][bats-npm-install].
We recommend an installation via `npm` instead of an installation via `apt`.
The reason is that many system packages provide comparatively old versions while
the version installable via `npm` is up to date.

To run the [`commands` command](./docs/usage.md#commands), you also need a
[Golang][golang] toolchain.
For optimal performance, install `flock`, which is contained within the
`util-linux` package on Debian-based systems.

[bats-npm-install]: https://bats-core.readthedocs.io/en/stable/installation.html#any-os-npm
[golang]: https://go.dev/doc/install

## Documentation Overview

- Usage documentation:
  - [Quickstart guide](./docs/quickstart.md):
    Read this page if this is your first time using `shellmock` and you want to
    get started.
  - [How to](./docs/howto.md):
    Read this page if you want to know how to go about creating your tests with
    `shellmock` in general.
  - [Detailed example](./docs/example.md):
    Read this page if you want to see how `shellmock` can be used to create
    extensive tests of a script of medium complexity.
  - [Command reference](./docs/usage.md):
    Read this page if you want to know about all of `shellmock`'s features or
    have questions about a specific command.
  - [shellmock's own tests][shellmock-tests]:
    Read this code if you want see how `shellmock` itself is being tested using
    [bats-core].
    Those tests also showcase `shellmock`'s features.
    This is a non-exhaustive list of examples you can find in the tests:
    - Mock an executable
    - Mock a function
    - Mock with non-zero exit code
    - Match positional arguments, both with fixed and flexible positions
    - Create a mock that is writing a fixed string to stdout
    - Fail a test by killing the parent process when there is an unexpected call
- Technical documentation:
  - [Building shellmock](./docs/build.md):
    Read this page if you want to know how to generate the release artefacts.

[shellmock-tests]: ./tests/main.bats "shellmock tests"
[releases]: https://github.com/boschresearch/shellmock/releases "releases"
[latest-release]: https://github.com/boschresearch/shellmock/releases/latest "latest release"

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

> Copyright (c) 2022 - for information on the respective copyright owner see the
> NOTICE file or the repository https://github.com/boschresearch/shellmock
>
> Licensed under the Apache License, Version 2.0 (the "License"); you may not
> use this file except in compliance with the License.
> You may obtain a copy of the License at
>
> http://www.apache.org/licenses/LICENSE-2.0
>
> Unless required by applicable law or agreed to in writing, software
> distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
> WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
> See the License for the specific language governing permissions and
> limitations under the License.

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
