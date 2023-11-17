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

SHELL := /bin/bash -euo pipefail

default: build

.PHONY: check-dependencies
check-dependencies:
	command -v bash &>/dev/null || (echo "ERROR, please install bash" >&2; exit 1)
	command -v bats &>/dev/null || (echo "ERROR, please install bats" >&2; exit 1)
	command -v find &>/dev/null || (echo "ERROR, please install find" >&2; exit 1)
	command -v shellcheck &>/dev/null || (echo "ERROR, please install shellcheck" >&2; exit 1)
	command -v shfmt &>/dev/null || (echo "ERROR, please install shfmt" >&2; exit 1)
	command -v jq &>/dev/null || (echo "ERROR, please install jq" >&2; exit 1)
	command -v kcov &>/dev/null || (echo "ERROR, please install kcov " >&2; exit 1)

SHELLCHECK_OPTS := --enable=add-default-case,avoid-nullary-conditions,quote-safe-variables,require-variable-braces
export SHELLCHECK_OPTS

.PHONY: lint
lint:
	shellcheck ./bin/* ./lib/* ./tests/*
	$(MAKE) check-format

.PHONY: test
test: build
	bats --print-output-on-failure ./tests/*.bats

DOWNLOAD_URL_PREFIX := https://mirror.kumi.systems/gnu/bash/

.PHONY: build-bash-version
build-bash-version:
	# Ensure that the arguments have been set.
	[[ -n "$(BASH_VERSION)" && -n "$(BASH_PATH)" ]]
	cd "$(BASH_PATH)" && \
	curl -sSfL -o bash.tar.gz "$(DOWNLOAD_URL_PREFIX)/bash-$(BASH_VERSION).tar.gz" && \
	tar -xvzf bash.tar.gz && \
	cd "bash-$(BASH_VERSION)" && \
	./configure && \
	make && \
	mv bash "$(BASH_PATH)"

.PHONY: test-bash-version
test-bash-version:
	# Ensure that the temp dir will be removed afterwards.
	tmp=$$(mktemp -d) && trap "rm -rf '$${tmp}'" EXIT && \
	$(MAKE) build-bash-version BASH_PATH="$${tmp}" && \
	export PATH="$${tmp}:$${PATH}" && \
	echo "INFO: using $$(which bash) @ $$(bash -c 'echo $${BASH_VERSION}')" && \
	bats --print-output-on-failure ./tests/*.bats

SUPPORTED_VERSIONS := 5.2 5.1 5.0 4.4

.PHONY: test-bash-versions
test-bash-versions: build
	rm -f .failed .bash-*_test.log
	for version in $(SUPPORTED_VERSIONS); do \
		$(MAKE) test-bash-version BASH_VERSION="$${version}" 2>&1 \
		| tee ".bash-$${version}_test.log" \
		|| echo "$${version}" >> .failed & \
	done; \
	wait
	if [[ -s .failed ]]; then \
		echo "Failed versions: $$(sort .failed | tr -s '[:space:]' ' ')"; \
	fi
	[[ ! -s .failed ]]

COVERAGE_FAILED_MESSAGE := \
	Cannot generate coverage reports as root user because kcov is not \
	compatible with current versions of bash when run as root, also see \
	https://github.com/SimonKagstrom/kcov/issues/234\#issuecomment-453929674

coverage: test
	if [[ "$$(id -ru)" -eq 0 ]]; then \
		echo >&2 "$(COVERAGE_FAILED_MESSAGE)"; exit 1; \
	fi
	# Generate coverage reports.
	kcov --bash-dont-parse-binary-dir --clean --include-path=. ./.coverage \
		bats --print-output-on-failure ./tests/*.bats
	# Analyse output of coverage reports and fail if not all files have been
	# covered of if coverage is not high enough.
	gawk \
	  -v min_cov="92" \
	  -v tot_num_files="1" \
	  'BEGIN{num_files=0; cov=0;} \
	  $$1 ~ /"file":/{num_files++} \
	  $$1 ~ /"covered_lines":/{cov=$$2} \
	  $$1 ~ /"total_lines":/{tot_cov=$$2} \
	  END{ \
	    if(num_files!=tot_num_files){ \
	      printf("Not all files covered: %d < %d\n", num_files, tot_num_files); exit 1 \
	    } \
	  } \
	  END{ \
	    if(cov/tot_cov < min_cov/100){ \
	      printf("Coverage too low: %.2f < %.2f\n", cov/tot_cov, min_cov/100); exit 1 \
	    } else { \
	      printf("Coverage is OK at %d%%.\n", 100*cov/tot_cov); \
	    } \
	  }' < <(jq < $$(ls -d1 .coverage/bats.*/coverage.json) | sed 's/,$$//')

format:
	shfmt -w -bn -i 2 -sr -ln bash ./bin/* ./lib/*
	shfmt -w -bn -i 2 -sr -ln bats ./tests/*
	mdslw --mode=format --upstream="prettier --parser=markdown" .

check-format:
	shfmt -d -bn -i 2 -sr -ln bash ./bin/* ./lib/*
	shfmt -d -bn -i 2 -sr -ln bats ./tests/*
	mdslw --mode=check --upstream="prettier --parser=markdown" .

build:
	./generate_deployable.sh

clean:
	rm -f shellmock.bash
	rm -fr .coverage
