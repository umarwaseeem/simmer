# Simmer developer shortcuts. Run `make help` for the list.
SHELL := /bin/bash
DIST ?= $(CURDIR)/dist
APP  := $(DIST)/Simmer.app

.PHONY: help build test project app fast dmg release install-helper uninstall-helper raycast clean

help: ## Show this help
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk -F ':.*## ' '{printf "  \033[1m%-17s\033[0m %s\n", $$1, $$2}'

build: ## Build the shared library, simmerd and simmerctl (debug, SwiftPM)
	swift build

test: ## Run the unit tests
	swift test

project: ## Generate Simmer.xcodeproj with XcodeGen
	xcodegen generate

app: ## Build the universal, ad-hoc signed dist/Simmer.app
	DIST="$(DIST)" scripts/build.sh

fast: ## Build dist/Simmer.app for this Mac's architecture only
	DIST="$(DIST)" ARCHS="$$(uname -m)" scripts/build.sh

dmg: ## Package dist/Simmer.app into dist/Simmer-<version>.dmg
	DIST="$(DIST)" scripts/make-dmg.sh

release: ## Build a release: make release VERSION=1.2.0
	@test -n "$(VERSION)" || { echo "usage: make release VERSION=x.y.z"; exit 64; }
	scripts/release.sh "$(VERSION)"

install-helper: ## Install the root helper from dist/Simmer.app (asks for your password)
	sudo "$(APP)/Contents/Resources/install-helper.sh" "$(APP)"

uninstall-helper: ## Remove the root helper and restore default charging
	sudo "$(APP)/Contents/Resources/uninstall-helper.sh"

raycast: ## Install deps and start the Raycast extension in dev mode
	cd raycast && npm install && npm run dev

clean: ## Remove build output
	rm -rf .build dist Simmer.xcodeproj
