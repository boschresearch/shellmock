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

# Some of the tests below use a fake executable called "my_exe" as a placeholder
# for any other executable you may want to test. You can test often-used
# executables such as "git", "ls", "find", "curl", "sed", "cat", and any other
# executable you can call from within a shell script.

setup_file() {
  # Ensure we use the minimum required bats version and fail with a nice error
  # if not.
  bats_require_minimum_version 1.5.0
}

setup() {
  load ../shellmock
}

@test "we can mock an executable" {
  # Executable not yet present. This test uses a fake executable called
  # "my_exe".
  run ! command -v my_exe
  # Create mock for "my_exe".
  shellmock new my_exe
  # Configure mock for "my_exe" to have an exit code of 0. Not specifying any
  # args means we do not want to make any assertions on args.
  shellmock config my_exe 0
  # Executable now present.
  command -v my_exe
  # Executable can be executed.
  my_exe
}

@test "a concrete example" {
  # This concrete example uses the "git" executable with the "checkout" command.
  # You could mock it like this analogous to the previous test.
  shellmock new git
  shellmock config git 0 1:checkout
  # Git mock can be called with the checkout command.
  git checkout
}

@test "we can mock a function" {
  # When calling an identifier, e.g. "git", the shell will give precedence to
  # functions. That is, if there is a function called "git" and an executable in
  # PATH of the same name, then the function will be used. The executable will
  # be shadowed (same effect in different words).
  #
  # Shellmock's mocks are executables. Thus, to be able to mock shell functions,
  # we need to unset functions we want to mock. Otherwise, the function would
  # always shadow our mock executable. This test showcases that.

  # Identifier "my_func" not yet present.
  run ! command -v my_func
  # Define function.
  my_func() {
    echo "I am a function"
    return 1
  }
  # Identifier "my_func" present and is a function.
  command -v my_func
  [[ $(type -t my_func) == function ]]

  # Create and configure mock. This will automatically unset the function
  # "my_func" that we want to mock for the reasons given above.
  shellmock new my_func
  shellmock config my_func 0
  # The identifier "my_func" is still present but now as an executable file
  # (i.e. identified as "type file". The function has been unset automatically
  # and no longer shadows our mock executable, as explained above.
  command -v my_func
  [[ $(type -t my_func) == file ]]
  # Mock executable can be executed.
  my_func
}

@test "unexpected call failing mock" {
  shellmock new my_exe
  # We configure the mock to have an exit code of 0 but only if the first
  # argument is "muhaha". Any other argument fails the mock and has it kill its
  # parent process.
  shellmock config my_exe 0 1:muhaha

  # We succeed when using the expected argument.
  my_exe muhaha
  # We fail when using an unexpected argument. Call within a separate "sh"
  # process to prevent the mock from killing the "bats" executable running the
  # tests, which would fail the test suite. Here, the separate "sh" instance
  # will be killed instead.
  if sh -c "my_exe asdf"; then
    # Shell running "my_exe asdf" exits with status code 0, which is a failure
    # for this test.
    echo >&2 "Call did not fail."
    exit 1
  fi
}

@test "mocks translate to sub-processes" {
  shellmock new my_exe
  shellmock config my_exe 0

  sh -c "my_exe"
}

@test "unexpected call kills parent process unless disabled" {
  shellmock new my_exe
  shellmock config my_exe 0 1:muhaha

  # Explicitly enable killing the parent process if the mock detects an
  # unexpected call. This makes the test fail even if the exit code of the mock
  # is ignored by the caller using the "';" in this case. This is the default
  # behaviour.
  shellmock global-config setval killparent 1
  if output=$(sh -c 'my_exe asdf; echo stuff'); then
    # The unexpected call to "my_exe" did not kill the process, the echo was run
    # and "sh" exited successfully. That is a failure for this test.
    echo >&2 "Call did not fail."
    exit 1
  fi
  [[ $(shellmock global-config getval killparent) -eq 1 ]]
  # Nothing has been written to the output.
  [[ -z ${output} ]]

  # Disable killing the parent process if an unexpected call is detected. This
  # allows the caller to catch such a case.
  shellmock global-config setval killparent 0
  # In this case, the use of ";" causes the exit code of the call to "my_exe"
  # not to influence the exit code of the call to "sh".
  output=$(sh -c 'my_exe asdf; echo stuff')
  [[ $(shellmock global-config getval killparent) -eq 0 ]]
  [[ ${output} == "stuff" ]]
}

@test "non-zero exit code" {
  shellmock new my_exe
  shellmock config my_exe 2

  run -2 my_exe
}

@test "unexpected call being reported" {
  # To catch the effect of an unexpected call, we must not kill the parent
  # process, i.e. the "bats" executable running the tests.
  shellmock global-config setval killparent 0

  shellmock new my_exe
  shellmock config my_exe 0 1:muhaha

  run my_exe asdf

  # Expectations cannot be asserted because they were not fulfilled. Thus,
  # ensure that expectations really have not been fulfilled.
  if shellmock assert expectations my_exe; then
    # Expectations could be asserted successfully, which is a failure in the
    # scope of this test.
    echo >&2 "Call did not fail."
    exit 1
  fi

  # Gather the report for the expectations but ignore the command failing. The
  # command will fail as soon as not all expectations could be asserted. The bit
  # "|| :" will ignore the exit code of the assertion. The report is written to
  # stderr, which means we have to redirect to stdout to capture it.
  report="$(shellmock assert expectations my_exe 2>&1 || :)"

  grep "^SHELLMOCK: unexpected call to '.*my_exe asdf'" <<< "${report}"
  grep -x "SHELLMOCK: got at least one unexpected call for .*my_exe\." <<< "${report}"
}

@test "missing call being reported if one configured" {
  # To catch the effect of a missing call, we must not kill the parent process.
  shellmock global-config setval killparent 0

  shellmock new my_exe
  shellmock config my_exe 0 1:muhaha

  # We deliberately don't call the executable here.

  # Expectations cannot be asserted because they were not fulfilled. Thus,
  # ensure that expectations really have not been fulfilled.
  if shellmock assert expectations my_exe; then
    # Expectations could be asserted successfully, which is a failure in the
    # scope of this test.
    echo >&2 "Call did not fail."
    exit 1
  fi

  # Gather the report for the expectations but ignore the command failing. The
  # command will fail as soon as not all expectations could be asserted. The bit
  # "|| :" will ignore the exit code of the assertion. The report is written to
  # stderr, which means we have to redirect to stdout to capture it.
  report="$(shellmock assert expectations my_exe 2>&1 || :)"

  grep "^SHELLMOCK: cannot find call for argspec: 1:muhaha" <<< "${report}"
  grep -x "SHELLMOCK: at least one expected call was not issued\." \
    <<< "${report}"
}

@test "missing call being reported if multiple configured" {
  shellmock global-config setval killparent 0

  shellmock new my_exe
  shellmock config my_exe 0 1:muhaha
  shellmock config my_exe 0 1:asdf

  # We deliberately call the executable here only once.
  my_exe asdf

  if shellmock assert expectations my_exe; then
    echo >&2 "Call did not fail."
    exit 1
  fi

  report="$(shellmock assert expectations my_exe 2>&1 || :)"

  grep "^SHELLMOCK: cannot find call for argspec: 1:muhaha" <<< "${report}"
  grep -x "SHELLMOCK: at least one expected call was not issued\." \
    <<< "${report}"
}

@test "allow arguments at any position" {
  shellmock new my_exe
  shellmock config my_exe 0 any:muhaha any:blub

  run my_exe muhaha asdf blub 42

  shellmock assert expectations my_exe
}

@test "positional arguments" {
  shellmock new my_exe
  shellmock config my_exe 0 1:muhaha 2:blub 3:asdf

  run my_exe muhaha blub asdf

  shellmock assert expectations my_exe
}

@test "positional arguments with gaps" {
  shellmock new my_exe
  shellmock config my_exe 0 1:muhaha 3:asdf 5:blub

  run my_exe muhaha ANYTHING asdf ANYTHING blub

  shellmock assert expectations my_exe
}

@test "multiple calls" {
  shellmock new my_exe
  shellmock config my_exe 0 1:muhaha
  shellmock config my_exe 0 1:blub

  my_exe muhaha
  my_exe blub
  my_exe blub

  shellmock assert expectations my_exe
}

@test "positional arguments not found" {
  shellmock new my_exe
  shellmock config my_exe 0 1:muhaha 2:blub 3:asdf

  run my_exe muhaha 42 asdf

  if shellmock assert expectations my_exe; then
    echo >&2 "Call did not fail."
    exit 1
  fi
}

@test "arguments determine exit code" {
  shellmock new my_exe
  shellmock config my_exe 0 1:muhaha
  shellmock config my_exe 2 1:asdf

  run -0 my_exe muhaha
  run -2 my_exe asdf

  shellmock assert expectations my_exe
}

@test "providing stdout" {
  shellmock new my_exe
  # Stdout for a mock is read verbatim from stdin when configuring. Stderr
  # cannot be mocked at the moment. This test uses so-called here-strings to
  # write a string to stdin of the shellmock command.
  shellmock config my_exe 0 1:first_call <<< "This is some output."
  shellmock config my_exe 0 1:second_call <<< "This is a different output."

  [[ "$(my_exe first_call)" == "This is some output." ]]
  [[ "$(my_exe second_call)" == "This is a different output." ]]

  shellmock assert expectations my_exe
}

@test "positional arguments matched with bash regexes" {
  shellmock new my_exe
  shellmock config my_exe 0 regex-1:"[0-9]*_muhaha$"

  # All these calls match the above bash regex.
  run -0 my_exe _muhaha
  run -0 my_exe 7_muhaha
  run -0 my_exe 42_muhaha
  run -0 my_exe blub_42_muhaha

  shellmock assert expectations my_exe
}

@test "arguments matched with bash regexes at any position" {
  shellmock new my_exe
  shellmock config my_exe 0 regex-any:"[0-9]*_muhaha$"

  # All these calls match the above bash regex.
  run -0 my_exe _muhaha
  run -0 my_exe ANYTHING ANYTHING 7_muhaha ANYTHING
  run -0 my_exe ANYTHING 42_muhaha
  run -0 my_exe blub_42_muhaha

  shellmock assert expectations my_exe
}

@test "easy arg counter increment" {
  shellmock new my_exe
  # Using "i" as location increases previous counter by 1, starting at 1 for the
  # first "i".
  shellmock config my_exe 0 i:muhaha i:asdf i:blub

  run my_exe muhaha asdf blub

  shellmock assert expectations my_exe
}

@test "easy arg counter increment with unsuitable base" {
  shellmock new my_exe
  # Using "i" as location increases previous counter by 1, starting at 1 for the
  # first "i". But this one fails because "any" is not a suitable numeric base
  # for incrementing.
  local stderr
  if stderr="$(
    shellmock config my_exe 0 any:muhaha i:asdf i:blub 2>&1 1> /dev/null
  )"; then
    echo >&2 "Call did not fail."
    exit 1
  fi

  [[ ${stderr} == "Cannot use non-numerical last counter as increment base." ]]
}
