# OpenDisplay — local developer entry points.
#
# Local-first: build and test the platform-independent packages with a Swift 6
# toolchain. On macOS that's Xcode 16+ (Swift 6); on Linux use `make bootstrap`
# to install the toolchain, then `make test`.
#
# The macOS app, providers, rescue utility, CLI, and SwiftUI design system are
# built from the Xcode project on a Mac (see Apps/OpenDisplay).

SWIFT ?= swift

.DEFAULT_GOAL := test

.PHONY: help
help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) \
		| awk 'BEGIN{FS=":.*?## "}{printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}'

.PHONY: bootstrap
bootstrap: ## Install a Swift 6 toolchain (Linux); on macOS just checks for Xcode/Swift
	@./scripts/bootstrap-swift.sh

.PHONY: build
build: ## Build the cross-platform packages (debug)
	$(SWIFT) build

.PHONY: test
test: ## Build and run the full unit/state-machine test suite
	$(SWIFT) test --parallel

.PHONY: release
release: ## Build the packages in release configuration
	$(SWIFT) build -c release

.PHONY: lint
lint: ## Run SwiftLint if available
	@if command -v swiftlint >/dev/null 2>&1; then swiftlint lint; \
	else echo "swiftlint not installed (brew install swiftlint / apt). Skipping."; fi

.PHONY: format
format: ## Run swift-format in place if available
	@if command -v swift-format >/dev/null 2>&1; then \
		swift-format format -i -r Packages Providers Apps Tools; \
	else echo "swift-format not installed. Skipping."; fi

.PHONY: xcode
xcode: ## Generate OpenDisplay.xcodeproj (XcodeGen) for the macOS app/providers/CLI
	@./scripts/generate-xcodeproj.sh

.PHONY: clean
clean: ## Remove build artifacts
	$(SWIFT) package clean || true
	rm -rf .build

bundle-helper: ## Bundle the opendisplay CLI into OpenDisplay.app/Contents/Helpers (for experimental rotation)
	@./scripts/bundle-helper.sh $(CONFIG)

.PHONY: release-signed
release-signed: ## Build, sign (Developer ID + hardened runtime), notarize, staple, and zip a release .app
	@./scripts/release-signed.sh
