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

ifndef TEST_SHELL
SHELL := /bin/bash -euo pipefail
else
SHELL := $(TEST_SHELL)
endif

default: build

.PHONY: check-dependencies
check-dependencies:
	command -v bash &>/dev/null || (echo "ERROR, please install bash" >&2; exit 1)
	command -v bats &>/dev/null || (echo "ERROR, please install bats" >&2; exit 1)
	command -v shellcheck &>/dev/null || (echo "ERROR, please install shellcheck" >&2; exit 1)
	command -v shfmt &>/dev/null || (echo "ERROR, please install shfmt" >&2; exit 1)
	command -v jq &>/dev/null || (echo "ERROR, please install jq" >&2; exit 1)
	command -v mdslw &>/dev/null || (echo "ERROR, please install mdslw" >&2; exit 1)

SHELLCHECK_OPTS := --external-sources --enable=add-default-case,avoid-nullary-conditions,quote-safe-variables,require-variable-braces
SHFMT_OPTS := --space-redirects --binary-next-line --indent 2

.PHONY: lint
lint:
	shellcheck $(SHELLCHECK_OPTS) ./bin/* ./lib/* ./tests/*
	shfmt --diff $(SHFMT_OPTS) --language-dialect bash ./bin/* ./lib/*
	shfmt --diff $(SHFMT_OPTS) --language-dialect bats ./tests/*
	mdslw --mode=check --report=diff-meyers --diff-pager=cat .

format:
	shfmt --write --simplify $(SHFMT_OPTS) --language-dialect bash ./bin/* ./lib/*
	shfmt --write --simplify $(SHFMT_OPTS) --language-dialect bats ./tests/*
	mdslw --mode=format .
	shellcheck --format=diff $(SHELLCHECK_OPTS) bin/* lib/* tests/* | git apply --allow-empty

# Run tests under all possible combinations of some shell options.
.PHONY: test
test: build
	echo >&2 "Running tests for version $${BASH_VERSION}."
	bats --jobs "$$(nproc --all)" --print-output-on-failure ./tests/*.bats

DOWNLOAD_URL_PREFIX := https://mirror.kumi.systems/gnu/bash/

.PHONY: build-bash-version
build-bash-version:
	# Ensure that the arguments have been set.
	[[ -n "$(BASH_VERSION)" && -n "$(BASH_PATH)" ]]
	cd "$(BASH_PATH)" && \
	curl -fL -o bash.tar.gz "$(DOWNLOAD_URL_PREFIX)/bash-$(BASH_VERSION).tar.gz" && \
	tar -xvzf bash.tar.gz && \
	cd "bash-$(BASH_VERSION)" && \
	./configure && \
	attempt=0 && while [[ "$${attempt}" -lt 3 ]]; do \
		make --jobs "$$(nproc --all)" && break; \
		attempt=$$((attempt+1)); \
	done && \
	if ! [[ "$${attempt}" -lt 3 ]]; then \
		echo "Failed to build $(BASH_VERSION)"; exit 1; \
	fi && \
	mv bash "$(BASH_PATH)"

.PHONY: test-bash-version
test-bash-version:
	# Ensure that the temp dir will be removed afterwards.
	tmp=$$(mktemp -d) && trap "rm -rf '$${tmp}'" EXIT && \
	$(MAKE) build-bash-version BASH_PATH="$${tmp}" && \
	export PATH="$${tmp}:$${PATH}" && \
	echo >&2 "INFO: using $$(which bash) @ $$(bash -c 'echo $${BASH_VERSION}')" && \
	$(MAKE) test TEST_SHELL="$$(which bash)"

SUPPORTED_VERSIONS ?= 5.2 5.1 5.0 4.4

.PHONY: test-bash-versions
test-bash-versions: build
	rm -f .failed .bash-*_test.log
	for version in $(SUPPORTED_VERSIONS); do \
		$(MAKE) test-bash-version BASH_VERSION="$${version}" || exit 1; \
	done

COVERAGE_FAILED_MESSAGE := \
	Cannot generate coverage reports as root user because kcov is not \
	compatible with current versions of bash when run as root, also see \
	https://github.com/SimonKagstrom/kcov/issues/234\#issuecomment-453929674

coverage: test
	command -v kcov &>/dev/null || (echo "ERROR, please install kcov" >&2; exit 1)
	if [[ "$$(id -ru)" == 0 ]]; then \
		echo >&2 "$(COVERAGE_FAILED_MESSAGE)"; exit 1; \
	fi
	# Generate coverage reports.
	kcov --bash-dont-parse-binary-dir --clean --include-path=. ./.coverage \
		bats --print-output-on-failure ./tests/*.bats
	# Analyse output of coverage reports and fail if not all files have been
	# covered of if coverage is not high enough.
	gawk \
	  -v min_cov="91" \
	  -v tot_num_files="2" \
	  'BEGIN{num_files=0; cov=0;} \
	  $$1 ~ /"file":/{num_files++} \
	  $$1 ~ /"covered_lines":/{cov=$$2} \
	  $$1 ~ /"total_lines":/{tot_cov=$$2} \
	  END{ \
	    if(num_files!=tot_num_files){ \
	      printf("Not all files covered: %d != %d\n", num_files, tot_num_files); exit 1 \
	    } \
	  } \
	  END{ \
	    if(cov/tot_cov < min_cov/100){ \
	      printf("Coverage too low: %.2f < %.2f\n", cov/tot_cov, min_cov/100); exit 1 \
	    } else { \
	      printf("Coverage is OK at %d%%.\n", 100*cov/tot_cov); \
	    } \
	  }' < <(jq < $$(ls -d1 .coverage/bats.*/coverage.json) | sed 's/,$$//')

build:
	./generate_deployable.sh

clean:
	rm -f shellmock.bash
	rm -fr .coverage
