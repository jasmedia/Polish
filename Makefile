# Polish developer commands. Run `make help` for the list.
.DEFAULT_GOAL := help
SUBSYSTEM := com.jasmedia.polish

.PHONY: help build app run test test-core test-app logs eval-setup eval-swift check-model icon release clean

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

build: ## Compile the app (debug), no bundle
	swift build --product Polish

app: ## Build and sign .build/app/Polish.app (CONFIG=release for release)
	scripts/bundle.sh

run: ## Rebuild, relaunch Polish.app
	scripts/run.sh

test: test-core test-app ## Run all tests

test-core: ## PolishCore engine tests
	swift test --package-path Packages/PolishCore

test-app: ## App target tests
	swift test

logs: ## Stream the app's logs
	log stream --level debug --style compact --predicate 'subsystem == "$(SUBSYSTEM)"'

eval-setup: ## Create the Python eval environment (eval/)
	uv sync --project eval

eval-swift: ## Golden set through the Swift pipeline (polish-cli), writes eval/runs/*.jsonl
	swift run -c release --package-path Packages/PolishCore polish-cli golden

check-model: ## Smoke-test the on-device model via fm and the Python SDK
	fm respond "Reply with the single word: ready"
	uv run --project eval python eval/check_model.py

icon: ## Redraw App/Resources/AppIcon.icns and the README logo docs/icon.png (scripts/make-icon.swift)
	swift scripts/make-icon.swift
	sips -s format png App/Resources/AppIcon.icns --out docs/icon.png >/dev/null
	sips -Z 256 docs/icon.png >/dev/null

release: ## DMG for a GitHub release, ad-hoc signed (NOTARIZE=1 for a notarized Developer ID build)
	scripts/release.sh

clean: ## Remove build products
	swift package clean
	swift package --package-path Packages/PolishCore clean
	rm -rf .build/app
