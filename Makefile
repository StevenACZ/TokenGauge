.PHONY: tools format lint script-check build test stage install-dev ci-check

.DEFAULT_GOAL := ci-check

tools:
	@xcrun --find swift-format >/dev/null
	@swift --version >/dev/null

format: tools
	xcrun swift-format format --in-place --recursive --parallel --configuration .swift-format Sources Tests

lint: tools
	xcrun swift-format lint --strict --recursive --parallel --configuration .swift-format Sources Tests

script-check:
	bash -n scripts/build_and_run.sh scripts/install_dev.sh scripts/install_claude_statusline.sh scripts/usage_history.sh scripts/package-release.sh scripts/generate-appcast.sh scripts/verify-update-key.sh scripts/verify-release.sh

build:
	swift build -c release

test:
	swift test

stage:
	./scripts/build_and_run.sh stage

install-dev:
	./scripts/install_dev.sh

ci-check: lint script-check build test
	@printf "ci-check: passed\n"

.PHONY: package-release appcast
package-release:
	./scripts/package-release.sh

appcast:
	./scripts/generate-appcast.sh

.PHONY: verify-release screenshots
verify-release:
	./scripts/verify-release.sh "$(ARTIFACT)"

screenshots:
	TOKENGAUGE_SCREENSHOT_DIR="$(CURDIR)/docs/images" swift test --filter ScreenshotTests
