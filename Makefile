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
COMPANION := packages/flighthouse_flutter
VERSION := $(shell sed -n 's/^version: //p' pubspec.yaml)
RELEASE_TAG := v$(VERSION)

.PHONY: help
help: ## List targets
	grep -hE '^[a-zA-Z0-9_/.-]+:.*## ' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*## "}; {printf "  %-28s %s\n", $$1, $$2}'

.PHONY: setup
setup: setup/hooks setup/deps setup/deps/flutter ## Install hooks and resolve dependencies

.PHONY: setup/hooks
setup/hooks: ## Install git hooks
	ln -sf "$(PWD)/git/hooks/pre-commit" .git/hooks/pre-commit
	ln -sf "$(PWD)/git/hooks/commit-msg" .git/hooks/commit-msg
	echo "Git hooks installed"

.PHONY: setup/deps
setup/deps: ## Resolve the workspace
	dart pub get

.PHONY: setup/deps/flutter
setup/deps/flutter: ## Resolve the Flutter companion package (needs Flutter)
	flutter pub get --directory $(COMPANION)

.PHONY: check
check: check/format check/lint check/flutter ## The whole gate: format and analyze both packages

.PHONY: check/format
check/format: ## Fail on unformatted Dart
	dart format --output=none --set-exit-if-changed .

.PHONY: check/lint
check/lint: setup/deps ## Analyze with strict options, infos are fatal
	dart analyze --fatal-infos

.PHONY: check/flutter
check/flutter: setup/deps/flutter ## Analyze the Flutter companion package (needs Flutter)
	cd $(COMPANION) && dart analyze --fatal-infos

.PHONY: check/pana
check/pana: check/pana/flighthouse check/pana/flutter ## Score both packages the way pub.dev does

.PHONY: check/pana/flighthouse
check/pana/flighthouse: ## Score the flighthouse package the way pub.dev does
	dart pub global activate pana >/dev/null
	dart pub global run pana --exit-code-threshold 0 .

.PHONY: check/pana/flutter
check/pana/flutter: ## Score the Flutter companion package the way pub.dev does (needs Flutter)
	dart pub global activate pana >/dev/null
	dart pub global run pana --exit-code-threshold 0 $(COMPANION)

.PHONY: check/publish
check/publish: ## Validate the package for pub.dev with no warnings
	dart pub publish --dry-run

.PHONY: fix
fix: setup/deps ## Format and apply analyzer fixes
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
test/cli: test/quark test/quark/web ## Run the CLI's collect and ci commands against recorded fixtures
	dart run bin/flighthouse.dart --config $(FIXTURES)/e2e/flighthouse.yaml collect
	dart run bin/flighthouse.dart --config $(FIXTURES)/e2e/flighthouse.yaml ci

.PHONY: test/quark
test/quark: ## Run the CI gate against real quark page audits
	dart run bin/flighthouse.dart --config $(FIXTURES)/quark/48a76ae/flighthouse.yaml collect
	dart run bin/flighthouse.dart --config $(FIXTURES)/quark/48a76ae/flighthouse.yaml ci

.PHONY: test/quark/web
test/quark/web: ## Run the CI gate against the recorded authenticated quark web collection
	dart run bin/flighthouse.dart --config $(FIXTURES)/quark/d8d2618e/flighthouse.yaml collect
	dart run bin/flighthouse.dart --config $(FIXTURES)/quark/d8d2618e/flighthouse.yaml ci

.PHONY: run/quark/web
run/quark/web: ## Collect quark live (needs ../quark, its backend, and FLIGHTHOUSE_* variables)
	dart run bin/flighthouse.dart --config $(FIXTURES)/quark/d8d2618e/collect.yaml collect

# Inputs of tool/e2e_quark/e2e.sh, passed through from `make VAR=value`. An unset one keeps its default.
export QUARK_VERSION QUARK_REPO QUARK_BIN QUARK_URL QUARK_SRC PORT WORK_DIR RUN_DIR CREDENTIALS BASELINE SEED_SCALE KEEP FLUTTER

.PHONY: run/quark/e2e
run/quark/e2e: ## One command: pinned Quark up, seed, web build, collect, report, ci, tear down (KEEP=1 keeps Quark)
	tool/e2e_quark/e2e.sh all

.PHONY: run/quark/up
run/quark/up: ## Start the pinned Quark release on PORT (default 18531) with its own HOME
	tool/e2e_quark/e2e.sh quark-up

.PHONY: run/quark/seed
run/quark/seed: ## Seed the test household idempotently (SEED_SCALE photos, default 6)
	tool/e2e_quark/e2e.sh seed

.PHONY: run/quark/run
run/quark/run: ## Build or reuse Quark's web build, then flighthouse collect against the running Quark
	tool/e2e_quark/e2e.sh web
	tool/e2e_quark/e2e.sh collect

.PHONY: run/quark/report
run/quark/report: ## flighthouse report and ci for the last collect (the first run writes the baseline)
	tool/e2e_quark/e2e.sh report
	tool/e2e_quark/e2e.sh ci

.PHONY: run/quark/down
run/quark/down: ## Stop the harness's Quark (WIPE=1 also removes its data and credentials)
	tool/e2e_quark/e2e.sh quark-down $(if $(filter 1,$(WIPE)),wipe,)

.PHONY: all quark-up seed run report quark-down
all: run/quark/e2e ## Alias of run/quark/e2e
quark-up: run/quark/up ## Alias of run/quark/up
seed: run/quark/seed ## Alias of run/quark/seed
run: run/quark/run ## Alias of run/quark/run
report: run/quark/report ## Alias of run/quark/report
quark-down: run/quark/down ## Alias of run/quark/down

.PHONY: run/chrome-acquire
run/chrome-acquire: ## Download the pinned Chrome and print its version
	dart run tool/chrome_smoke.dart --acquire-only

.PHONY: run/chrome-smoke
run/chrome-smoke: ## Launch pinned Chrome, inject axe, and write the result
	dart run tool/chrome_smoke.dart

.PHONY: run/web-fixture
run/web-fixture: ## Collect the Flutter web fixture and exercise the CI gate
	integration/web_fixture/tool/run_fixture.sh
