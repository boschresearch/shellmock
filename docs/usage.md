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

# Usage

To be able to use Shellmock, you need to load the library in your tests.
To do so, `load` it in your `setup` function.
Please make sure to load Shellmock in the `setup` function instead of the
`setup_file` function.
You can also test your download of Shellmock and whether it can be loaded like
this:

```bash
setup() {
  load ${PATH_TO_SHELLMOCK_LIBRARY}/shellmock
}

@test "shellmock can be used" {
  shellmock help
}
```

Put this in a file called `test.bats` and run it as `bats ./test.bats`, making
sure to replace `${PATH_TO_SHELLMOCK_LIBRARY}` appropriately.

## Command Reference

<!-- shellmock-helptext-start -->

You can access all functionality of Shellmock via the `shellmock` command.
It is implemented as a shell function with the following sub-commands:

- `new`: Create a new mock for an executable.
- `config`: Configure a previously-created mock by defining expectations.
- `assert`: Assert based on previously-configured expectations.
- `global-config`: Configure global behaviour of Shellmock itself.
- `help`: Provide a help text.

<!-- shellmock-helptext-end -->

The more complex sub-commands will be described below in detail.

### new

<!-- shellmock-helptext-start -->

Syntax: `shellmock new <name>`

The `new` command creates a new mock executable called `name`.
It is created in a directory in your `PATH` that is controlled by Shellmock.
You need to create a mock before you can configure it or make assertions on it.

<!-- shellmock-helptext-end -->

The `new` command takes exactly one argument: the name of the executable to be
mocked.
For example:

```bash
shellmock new git
```

This will create a mock executable for `git`.
That mock executable will be used instead of the one installed on the system
from that point forward, assuming no code changes `PATH`.

### config

<!-- shellmock-helptext-start -->

Syntax: `shellmock config <name> <exit_code> [1:<argspec> [...]]`

The `config` command defines expectations for calls to your mocked executable.
You need to define expectations before you can make assertions on your mock.

<!-- shellmock-helptext-end -->

The `config` command takes at least two arguments:

1. the `name` of the mock you wish you define expectations for, and
2. the mock's `exit_code` for invocations matching the expectations configured
   with this call.

Every following argument to the `config` command is a so-called `argspec` (see
below).

The `config` command can also define a command's standard output.
Everything read from standard input will be echoed by the mock to its standard
output verbatim.
There is no way to have the mock write something to standard error.

#### Example

This example simulates a call to `git branch` that:

- returns with exit code `0`
- expects to be called with the single argument `branch`
- and will output `* main` to stdout

```bash
shellmock config git 0 1:branch <<< "* main"
```

**Note:** The example shows one possible way to define the output of the mock.
In the example it uses a _here string_ to define the input to shellmock.
There are different ways to write to standard input, which even depend on the
used shell.
Here strings are known to work for `bash` and `zsh`, for example.

#### argspec Interpretation

An argspec defines expectations for arguments.
Only calls to the mock whose arguments match all given expectations will have
the given exit code and stdout.
Any call to a mock that has at least one argument not matching an argspec will
be considered an error (also see [killparent](#killparent)).

Note that matches only happen for given argspecs.
That is, if you do not provide an argspec for a positional argument, any value
can be there.
For example, the line `shellmock config git 0` will cause _any_ invocation of
the `git` mock to have a zero exit code, _irrespective of any arguments_ because
no argspecs were given.

Argspec sets as defined via `config` are matched in order of definition.
The first one found that matches the given arguments will be used by the mock
executable.

#### argspec Definitions

There are two _kinds_ of argspecs: exact string matches and regex-based string
matches.
Exact string matches should be preferred whenever possible.

There are also two _types_ of argspecs: position-dependent ones and
position-independent ones.
Position-dependent argspecs should be preferred whenever possible.

##### Position-Dependent argspec

A position-dependent exact string match looks like `n:value` where `n` is a
position indicator and `value` is a literal string value.
This argspec matches if the argument at position `n` has exactly the value
`value`.
For example, the argspec `1:branch` expects the first argument to be exactly
`branch`.
As you can see, counting of arguments starts at 1.
As another example, the argspec `3:some-fancy-value` expects argument 3 to be
exactly `some-fancy-value`.

Normal shell-quoting rules apply to argspecs.
That is, to specify an argument with spaces, you need to quote the argspec.
We recommend quoting only the value because it is easier to read.
The last example could thus be changed like this: `3:"some fancy value"`.

Note that you can also replace the numeric value indicating the expected
position of an argument by the letter `i`.
That letter will automatically be replaced by the value used for the previous
argspec increased by 1.
If the first argspec uses the `i` placeholder, it will be replaced by `1`.
Note that `i` must not follow `any` (see below).
Thus, to define the expectation of having the command:

```bash
git checkout -b my-branch
```

You can use the following calls to `shellmock`:

```bash
shellmock new git
# The first "i" will be replaced by 1 and each subsequent "i" will be one
# larger than the previous one.
shellmock config git 0 i:checkout i:-b i:my-branch
```

##### Position-Independent argspec

A position-independent argspec replaces the position indicator by the literal
word `any`.
Thus, if we did not care at which position the `branch` keyword were in the
first example, we could use: `any:branch`.

A regex-based argspec prefixes the position indicator by the literal word
`regex-` (mind the hyphen!).
With such an argspec, `value` will be re-interpreted as a _bash regular
expression_ matched via the comparison `[[ ${argument} =~ ${value} ]]`.
You can also use the position indicator `regex-any` to have a
position-independent regex match.
You _cannot_ use `regex-i`, though.

We _strongly recommend against_ using `regex-1:^branch$` instead of the exact
string match `1:branch` because of the many special characters in regular
expressions.
It is very easy to input a character that is interpreted as a special one
without realising that.

### assert

<!-- shellmock-helptext-start -->

Syntax: `shellmock assert <type> <name>`

The `assert` command can be used to check whether expectations previously
defined via the `config` command have been fulfilled for a mock or not.
The `assert` command takes exactly two arguments, the `type` of assertion that
shall be performed and the `name` of the mock that shall be asserted on.
We recommend to always use `expectations` as assertion type.

<!-- shellmock-helptext-end -->

Example:

```bash
shellmock assert expectations git
```

The `assert` command will have a non-zero exit code in case the assertion had
not been fulfilled.

#### Assertion Types

There are currently the following types of assertions.

- `only-expected-calls`:
  This assertion will check that the mock has not had calls that had not been
  configured beforehand.
  That is, if this assertion succeeds, the mock could find a set of argspecs
  matching its actual arguments for every time it had been called.
- `call-correspondence`:
  This assertion will check that each set of argspecs defined for it had been
  used at least once.
- `expectations`:
  This assertion will first perform the following assertions in sequence:
  `only-expected-calls`, and `call-correspondence`.
  It is a convenience assertion type combining all other assertions.

### global-config

<!-- shellmock-helptext-start -->

Syntax:

- `shellmock global-config <getval> <setting>`
- `shellmock global-config <setval> <setting> <value>`

<!-- shellmock-helptext-end -->

The `global-config` command can be used to modify Shellmock globally in some
ways.
As argument, `global-config` can have one of the two sub-commands `setval` or
`getval`.

- With `setval`, you can define some global behaviour.
  Using `setval` requires a `value` which the `setting` is set to.
- With `getval`, on the other hand, you can retrieve information about a current
  global `setting`.

<!-- shellmock-helptext-start -->

There are currently the following settings:

- `checkpath`
- `killparent`

<!-- shellmock-helptext-end -->

#### checkpath

Shellmock injects mock executables by prepending a directory that it controls to
`PATH`.
However, the tested code can still make modifications to its `PATH`, which could
cause Shellmock's mocks to not be called.
Thus, every call to the `shellmock` command will check whether the `PATH`
variable has been changed since Shellmock was loaded via `load shellmock`.
An error will be written to standard error in case such a change is detected.

The default value is 1.
Use `shellmock global-config setval checkpath 0` to disable.
Use `shellmock global-config getval checkpath` to retrieve the current setting.

#### killparent

By default, a mock that is called with arguments for which no expectations have
been defined will kill its parent process.
That is, it will send `SIGTERM` to its parent process.
This behaviour means to ensure that tests do not progress past an unexpected
call to the mock.
If the mock were simply to exit with a non-zero exit code, there would be no
difference to defining an non-zero return value.
Such a case could easily be caught by the parent process and cause the test to
take unexpected paths through the code.

Take the following snippet as an example where we mock `curl`.

```bash
if ! curl http://some.url; then
  echo "Curl command failed, trying different URL" >&2
  curl http://some.other.url
fi
```

Assume the `curl` mock did not kill its parent process but we forgot to define
expectations for the first call to `curl`.
That would cause the shell code to enter the `then` branch above, even though we
would rather have our test fail then and there.
To avoid that, we kill the parent process, which means the `then` branch will
not be executed.

The default value is 1.
Use `shellmock global-config setval killparent 0` to disable.
Use `shellmock global-config getval killparent` to retrieve the current setting.
