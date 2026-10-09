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
VERSION := $(shell sed -n 's/^version: //p' pubspec.yaml)
RELEASE_TAG := v-$(VERSION)

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

.PHONY: run/cli
run/cli: ## Run the CLI (CLI_ARGS supplies the command and options)
	dart run bin/flighthouse.dart $(CLI_ARGS)

.PHONY: release
release: ## Tag the pubspec version on main and push the tag, which publishes it
	git fetch --quiet --tags origin main
	if [ "$$(git rev-parse HEAD)" != "$$(git rev-parse origin/main)" ] || [ -n "$$(git status --porcelain)" ]; then
		echo "Release from a clean, current main: git checkout main && git pull" >&2
		exit 1
	fi
	if git rev-parse --quiet --verify "refs/tags/$(RELEASE_TAG)" >/dev/null; then
		echo "Tag $(RELEASE_TAG) already exists. Bump the version in pubspec.yaml and CHANGELOG.md in a PR first" >&2
		exit 1
	fi
	git tag "$(RELEASE_TAG)"
	git push origin "$(RELEASE_TAG)"
	echo "Pushed $(RELEASE_TAG); the Publish workflow takes it from here"

.PHONY: test/cli
test/cli: test/quark ## Run the CLI's collect and ci commands against recorded fixtures
	dart run bin/flighthouse.dart --config $(FIXTURES)/e2e/flighthouse.yaml collect
	dart run bin/flighthouse.dart --config $(FIXTURES)/e2e/flighthouse.yaml ci

.PHONY: test/quark
test/quark: ## Run the CI gate against real quark page audits
	dart run bin/flighthouse.dart --config $(FIXTURES)/quark/48a76ae/flighthouse.yaml collect
	dart run bin/flighthouse.dart --config $(FIXTURES)/quark/48a76ae/flighthouse.yaml ci

.PHONY: run/chrome-acquire
run/chrome-acquire: ## Download the pinned Chrome and print its version
	dart run tool/chrome_smoke.dart --acquire-only

.PHONY: run/chrome-smoke
run/chrome-smoke: ## Launch pinned Chrome, inject axe, and write the result
	dart run tool/chrome_smoke.dart

.PHONY: run/web-fixture
run/web-fixture: ## Collect the Flutter web fixture and exercise the CI gate
	integration/web_fixture/tool/run_fixture.sh
