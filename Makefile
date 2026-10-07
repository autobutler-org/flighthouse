SHELL := bash
.SHELLFLAGS = -e -c
.DEFAULT_GOAL := help
.ONESHELL:
.SILENT:

unexport GIT_DIR
unexport GIT_INDEX_FILE
unexport GIT_WORK_TREE
unexport GIT_PREFIX

FIXTURES := test/fixtures

.PHONY: help
help: ## List targets
	grep -hE '^[a-zA-Z0-9_/.-]+:.*## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*## "}; {printf "  %-28s %s\n", $$1, $$2}'

.PHONY: setup
setup: setup/hooks setup/deps ## Install hooks and resolve dependencies

.PHONY: setup/hooks
setup/hooks: ## Install git hooks
	ln -sf "$(PWD)/git/hooks/pre-commit" .git/hooks/pre-commit
	ln -sf "$(PWD)/git/hooks/commit-msg" .git/hooks/commit-msg
	echo "Git hooks installed"

.PHONY: setup/deps
setup/deps: ## Resolve the workspace
	dart pub get

.PHONY: check
check: check/format check/lint ## The whole gate: format and analyze

.PHONY: check/format
check/format: ## Fail on unformatted Dart
	dart format --output=none --set-exit-if-changed .

.PHONY: check/lint
check/lint: ## Analyze with strict options, infos are fatal
	dart analyze --fatal-infos

.PHONY: check/pana
check/pana: ## Score the package the way pub.dev does
	dart pub global activate pana >/dev/null
	dart pub global run pana --exit-code-threshold 0 .

.PHONY: check/publish
check/publish: ## Validate the package for pub.dev with no warnings
	dart pub publish --dry-run

.PHONY: fix
fix: ## Format and apply analyzer fixes
	dart fix --apply
	dart format .

.PHONY: test
test: ## Run every unit, fixture, and end-to-end test
	dart test

.PHONY: test/cli
test/cli: ## Run the CLI's collect and ci commands against recorded fixtures
	dart run bin/flighthouse.dart --config $(FIXTURES)/e2e/flighthouse.yaml collect
	dart run bin/flighthouse.dart --config $(FIXTURES)/e2e/flighthouse.yaml ci
