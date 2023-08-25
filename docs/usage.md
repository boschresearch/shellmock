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
- `calls`: Log past calls to mocks and suggest mock configs to reproduce.
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
You can add multiple configurations for the same mock by calling the `config`
command multiple times.
When called, the mock will use the first configuration that matches.

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

** Example**: A call to `git branch` that

- returns with exit code `0`, indicating success,
- expects to be called with `branch` as first argument, and
- will output `* main` to stdout.

```bash
shellmock config git 0 1:branch <<< "* main"
```

**Note:** The example shows one possible way to define the output of the mock.
The example uses a _here string_ to define the input to shellmock.
There are different ways to write to standard input, which even depend on the
used shell.
Here strings are known to work for `bash` and `zsh`, for example.

#### argspec Interpretation

An argspec defines expectations for arguments.
Only calls to the mock whose arguments match all given expectations will have
the given exit code and stdout.
Any call to a mock that has at least one argument not matching any argspec will
be considered an error (also see [killparent](#killparent)).

Note that matches only happen for given argspecs.
That is, if you do not provide an argspec for a positional argument, any value
can be there.
For example, the line `shellmock config git 0` will cause _any_ invocation of
the `git` mock to have a zero exit code, _irrespective of any arguments_ because
no argspecs were given.
Furthermore, you must not specify multiple argspecs for the same index.
For example, the line `shellmock config git 0 1:branch 1:checkout` would never
match any call and is thus rejected.

Argspec sets as defined via `config` are matched in order of definition.
The first one found that matches the given arguments will be used by the mock
executable.

** Example**: Catch-all mock configuration

```bash
shellmock new git
shellmock config git 0 <<< "catchall"
shellmock config git 0 1:branch <<< "branch"

# Executing git branch.
output=$(git branch)
# Output is "catchall".
if [[ ${output} != catchall ]]; then
  echo >&2 "output not as expected: ${output}"
  exit 1
fi
```

#### argspec Definitions

There are three _types_ of argspecs: two position-dependent ones (numeric and
incremental) and one position-independent (flexible) one.
Position-dependent types should be preferred whenever possible.

There are also two _kinds_ of argspecs: exact string matches and regex-based
string matches.
Exact string matches should be preferred whenever possible.

The _types_ and _kinds_ of argspecs can be combined to create, for example,
a regex-based position-independent argspec.

In general, an argspec looks like this: `<position>:<value>`.
Normal shell-quoting rules apply to argspecs, especially to the `value` part.
That is, to specify an argument with spaces, you need to quote the argspec.
We recommend quoting only the value because it is easier to read.
Providing a value containing white space should look like this:
`3:"some fancy value"`.

##### Numeric Position-Dependent argspec

A _numeric position-dependent_ argspec looks like `n:value` where `n` is a
numeric position indicator and `value` is a literal string value.
This argspec matches if the argument at position `n` has exactly the value
`value`.
Argument counting starts at 1.
Arguments at undefined positions can be anything.

** Example**: Only specified argspecs matter

```bash
shellmock new git
shellmock config git 0 1:branch
# Would match the following commands, for example:
git branch
git branch -r

shellmock config git 0 2:develop
# Would match the following commands, for example:
git checkout develop
git diff develop main
```

While the order of numeric argspecs has no influence, we recommend to define
numeric argspecs in ascending order.

** Example**: Numeric argspec order

```bash
# these mocks are equivalent
shellmock config git 0 1:checkout 2:develop 3:master
shellmock config git 0 1:checkout 3:master 2:develop
```

##### Incremental Position-Dependent argspec

You can also replace the numeric value indicating the expected
position of an argument by the letter `i`.
That letter will automatically be replaced by the value used for the previous
argspec increased by 1.
If the first argspec uses the `i` placeholder, it will be replaced by `1`.
Numeric and incremental position indicators can be mixed.

** Example**: Incremental argspec

```bash
shellmock new git
shellmock config git 0 i:checkout i:-b i:my-branch
# Would match the following command, for example:
git checkout -b my-branch master

shellmock config git 0 2:my-branch i:develop
# Would match the following commands, for example:
git diff my-branch develop
git rebase my-branch develop
```

##### Flexible Position-Independent argspec

A flexible position-independent argspec replaces the position indicator by the
literal word `any`.
Thus, if we did not care at which position the `branch` keyword were in the
first example, we could use: `any:branch`.

** Example**: Position-independent argspec

```bash
shellmock new git
shellmock config git 0 any:develop
# Would match the following commands, for example:
git checkout develop
git push origin develop
git diff develop main
```

You can combine position-independent and position-dependent argspecs.
Note that the position indicator `i` cannot directly follow `any`.

** Example**: Combining position-independent and dependent argspecs

```bash
shellmock new git
shellmock config git 0 1:checkout any:feature
# Would match the following commands, for example:
git checkout feature
git checkout -b feature
```

Note that the flexible position independent argspec matches any position.
That is, even if it precedes a numeric argspec, it can still match later
arguments.

** Example**: Flexible argspecs match anywhere

```bash
shellmock new git
shellmock config git 0 any:feature 3:master
# Would match the following commands, for example:
git checkout feature master    # -> any matches at position 2
git diff --raw master feature  # -> any matches at position 4
```

#### Regex-Based argspec

A regex-based argspec prefixes the numeric or flexible position indicator by the
literal word `regex-` (mind the hyphen!).
Specify the argspec as `regex-n:value` (with n being a positive integer) or
`regex-any:value`.
You _cannot_ combine it with the flexible position indicator `i`, though.

With such an argspec, `value` will be re-interpreted as a _bash regular
expression_ matched via the comparison `[[ ${argument} =~ ${value} ]]`.

** Example**: Regex-based argspecs

```bash
shellmock new git
shellmock config git 0 regex-2:^feature
# Would match the following commands, for example:
git checkout feature/foobar
git merge feature/barbaz

shellmock config git 0 regex-any:^feature
# Would match the following commands, for example:
git checkout -b feature/foobar
git merge feature/barbaz
```

We _strongly recommend against_ using `regex-1:^branch$` instead of the exact
string match `1:branch` because of the many special characters in regular
expressions.
It is very easy to input a character that is interpreted as a special one
without realizing that.
You can, of course, combine string and regex based argspecs.

** Example**: Combining string-based and regex-based argspecs

```bash
shellmock new git
shellmock config git 0 1:checkout regex-any:^feature
# Would match the following commands, for example:
git checkout feature/foobar
git checkout -b feature/barbaz master
```

### assert

<!-- shellmock-helptext-start -->

Syntax: `shellmock assert <type> <name>`

The `assert` command can be used to check whether expectations previously
defined via the `config` command have been fulfilled for a mock or not.
The `assert` command takes exactly two arguments, the `type` of assertion that
shall be performed and the `name` of the mock that shall be asserted on.
We recommend to always use `expectations` as assertion type.

<!-- shellmock-helptext-end -->

** Example**: Asserting expectations

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

- `shellmock global-config getval <setting>`
- `shellmock global-config setval <setting> <value>`

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

### calls

<!-- shellmock-helptext-start -->

Syntax: `shellmock calls <name> [--plain|--json]`

The `calls` command retrieves information about past calls to your mock.
The `calls` command is useful when developing mocks.

<!-- shellmock-helptext-end -->

The `calls` command takes one mandatory and one optional argument.
The first, mandatory argument is the name of the mock executable for which you
wish to retrieve call details.
The second, optional argument specifies the output format.
The output format defaults to `--plain`, but you can also choose JSON, which
simplifies automated processing or may be easier to view.

#### Example

This example specifies a generic mock, calls it four times with different
arguments and stdin, and then retrieves the information about all four calls.
The output of `shellmock calls` also suggests a `shellmock config` call that
would configure the mock to accept the given call.

```bash
# A mock configured like this accepts any argument and always exits with
# success.
shellmock new git
shellmock config git 0
# Call the mock several times, simulating a script to be tested.
git branch -l              # List existing branches
git checkout -b new-branch # Create a new branch and check it out.
git branch -l <<< "null"   # List branches again.
git branch -d new-branch   # Delete the branch again.
# Retrieve call details in plain text format. The command will always exit with
# an error code, thus failing the test. Bats writes the output of a failed test
# to the terminal for the developer to see.
shellmock calls git --plain
```

Design your actual mocks based on the output of the failing test above.
The output for this example contains all details about all of the calls.
The output would be:

<!-- prettier-ignore-start -->
```
name:       git
id:         1
args:       branch -l
stdin:      
suggestion: shellmock config git 0 1:branch 2:-l

name:       git
id:         2
args:       checkout -b new-branch
stdin:      
suggestion: shellmock config git 0 1:checkout 2:-b 3:new-branch

name:       git
id:         3
args:       branch -l
stdin:      null
suggestion: shellmock config git 0 1:branch 2:-l <<< null

name:       git
id:         4
args:       branch -d new-branch
stdin:      
suggestion: shellmock config git 0 1:branch 2:-d 3:new-branch
```
<!-- prettier-ignore-end -->

If you were to replace `--plain` by `--json` in the call to `shellmock calls`,
the output would be as follows instead:

<!-- prettier-ignore-start -->
```json
[
  {
    "name": "git",
    "id": "1",
    "args": [
      "branch",
      "-l"
    ],
    "stdin": "",
    "suggestion": "shellmock config git 0 1:branch 2:-l"
  },
  {
    "name": "git",
    "id": "2",
    "args": [
      "checkout",
      "-b",
      "new-branch"
    ],
    "stdin": "",
    "suggestion": "shellmock config git 0 1:checkout 2:-b 3:new-branch"
  },
  {
    "name": "git",
    "id": "3",
    "args": [
      "branch",
      "-l"
    ],
    "stdin": "null",
    "suggestion": "shellmock config git 0 1:branch 2:-l <<< null"
  },
  {
    "name": "git",
    "id": "4",
    "args": [
      "branch",
      "-d",
      "new-branch"
    ],
    "stdin": "",
    "suggestion": "shellmock config git 0 1:branch 2:-d 3:new-branch"
  }
]
```
<!-- prettier-ignore-end -->
