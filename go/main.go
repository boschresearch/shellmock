// Copyright (c) 2022 - for information on the respective copyright owner
// see the NOTICE file or the repository
// https://github.com/boschresearch/shellmock
//
// Licensed under the Apache License, Version 2.0 (the "License"); you may not
// use this file except in compliance with the License. You may obtain a copy of
// the License at
//
//   http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
// WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the
// License for the specific language governing permissions and limitations under
// the License.

package main

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"log"
	"os"
	"slices"
	"strings"
	"unicode"

	shell "mvdan.cc/sh/v3/syntax"
)

const (
	commentChar      = "#"
	directiveSep     = ":"
	directiveStart   = "shellmock"
	usesCmdDirective = "uses-command="
)

func sortedKeys(data map[string]int) []string {
	result := make([]string, 0, len(data))
	for key := range data {
		result = append(result, key)
	}
	slices.Sort(result)
	return result
}

// Determine all commands executed by a script.
func findCommands(shellCode shell.Node) map[string]int {
	result := map[string]int{}

	shell.Walk(
		shellCode, func(node shell.Node) bool {
			// Simple commands.
			if expr, ok := node.(*shell.CallExpr); ok {
				if len(expr.Args) == 0 || len(expr.Args[0].Parts) == 0 {
					// Ignore empty commands and continue searching.
					return true
				}
				// We do not detect cases where a command is an argument. We also do not detect
				// cases where the command we seek is hidden in a command substitution or shell
				// expansion.
				if cmd, ok := expr.Args[0].Parts[0].(*shell.Lit); ok {
					result[cmd.Value]++
				}
			}
			// Continue searching.
			return true
		},
	)

	return result
}

func findCommandsFromDirectives(shellCode string) map[string]int {
	result := map[string]int{}
	for lineIdx, orgLine := range strings.Split(shellCode, "\n") {
		line := orgLine
		isDirectiveLine := true
		// First, detect comment lines. Then, detect lines with shellmock directives. Then, detect
		// lines with the expected directive. Skip if any of the preconditions are not fulfilled.
		for idx, prefix := range []string{commentChar, directiveStart, usesCmdDirective} {
			line = strings.TrimSpace(strings.TrimPrefix(strings.TrimSpace(line), directiveSep))
			if !strings.HasPrefix(line, prefix) {
				if idx >= 2 {
					log.Printf(
						"WARNING: found unknown shellmock directive in line %d: %s",
						lineIdx+1, orgLine,
					)
				}
				isDirectiveLine = false
				break
			}
			line = strings.TrimPrefix(line, prefix)
		}
		if !isDirectiveLine {
			continue
		}
		for _, cmd := range strings.Split(line, ",") {
			// Stop if after some whitespace there is something starting with a comment character.
			// That way, users can still add comments following the directive and executables
			// containing whitespace are supported. The only thing we do not support is adding
			// executables this way whose names contain a comment character following some space. We
			// also do not support adding executables this way whose names contain commas.
			idx := strings.Index(cmd, commentChar)
			if idx > 0 && unicode.IsSpace(rune(cmd[idx-1])) {
				// Make sure to add the last command before the trailing comment.
				result[strings.TrimSpace(cmd[:idx])]++
				break
			}
			if len(cmd) != 0 {
				result[cmd]++
			}
		}
	}
	return result
}

func main() {
	content, err := io.ReadAll(bufio.NewReader(os.Stdin))
	if err != nil {
		log.Fatalf("failed to read from stdin: %s", err.Error())
	}
	parsed, err := shell.NewParser().Parse(bytes.NewReader(content), "")
	if err != nil {
		log.Fatalf("failed to parse shell code: %s", err.Error())
	}
	commands := findCommands(parsed)
	// Also find commands that are noted by shellmock directives.
	moreCommands := findCommandsFromDirectives(string(content))
	for cmd, count := range moreCommands {
		commands[cmd] += count
	}
	for _, cmd := range sortedKeys(commands) {
		count := commands[cmd]
		fmt.Printf("%s:%d\n", cmd, count)
	}
}
