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

	"golang.org/x/exp/maps"
	shell "mvdan.cc/sh/v3/syntax"
)

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
	keys := maps.Keys(commands)
	slices.Sort(keys)
	for _, cmd := range keys {
		count := commands[cmd]
		fmt.Printf("%s:%d\n", cmd, count)
	}
}
