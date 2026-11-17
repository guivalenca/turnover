# Build, install and test Turnover. Only Xcode is needed, except for `make project`.
#
#   make install     build, sign ad hoc, install to /Applications, enable the Finder menu, launch
#   make uninstall   quit, disable and unregister everything `make install` set up
#   make app         build build/Turnover.app only (ad hoc signed; install removes it again)
#   make test        run the TurnoverKit and CLI tests
#   make project     regenerate Turnover.xcodeproj from project.yml (needs `brew install xcodegen`)

APP_ID      := com.guivalenca.turnover
EXTENSION_ID := com.guivalenca.turnover.finder
DERIVED     := build/DerivedData
BUILT       := $(DERIVED)/Build/Products/Release/Turnover.app
PRODUCT     := build/Turnover.app
INSTALLED   := /Applications/Turnover.app
EXTENSION   := Contents/PlugIns/TurnoverFinder.appex
LSREGISTER  := /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
# The XcodeGen CI checks Turnover.xcodeproj with (.github/workflows/ci.yml); keep them in step.
XCODEGEN_VERSION := 2.47.0
XCODEGEN    ?= xcodegen

.PHONY: app install uninstall test project clean

# Xcode registers what it builds with LaunchServices and pluginkit. Turnover's URL scheme and
# Finder extension must resolve to one copy only, so the build copy is moved out of
# DerivedData and unregistered; only the installed app stays registered.
app:
	xcodebuild -project Turnover.xcodeproj -scheme Turnover -configuration Release \
		-derivedDataPath $(DERIVED) -quiet build
	-pluginkit -r "$(BUILT)/$(EXTENSION)" 2>/dev/null
	-$(LSREGISTER) -u "$(BUILT)" 2>/dev/null
	rm -rf "$(PRODUCT)"
	ditto "$(BUILT)" "$(PRODUCT)"
	rm -rf "$(BUILT)"
	codesign --verify --deep --strict "$(PRODUCT)"
	@echo "Built $(PRODUCT)"

# Re-running upgrades in place: the old copy is quit and replaced, and Finder restarts the
# extension from the new one.
install: app
	@pkill -x Turnover || true
	@pkill -x TurnoverFinder || true
	rm -rf "$(INSTALLED)"
	ditto "$(PRODUCT)" "$(INSTALLED)"
	@# LaunchServices notices app bundles on disk by itself; leave only the installed copy.
	-@$(LSREGISTER) -u "$(PRODUCT)" 2>/dev/null
	rm -rf "$(PRODUCT)"
	$(LSREGISTER) -f -R -trusted "$(INSTALLED)"
	pluginkit -a "$(INSTALLED)/$(EXTENSION)"
	@for attempt in 1 2 3 4 5 6 7 8 9 10; do \
		pluginkit -m -i $(EXTENSION_ID) | grep -q $(EXTENSION_ID) && break; sleep 1; \
	done
	pluginkit -e use -i $(EXTENSION_ID)
	open -g "$(INSTALLED)"
	@echo "Installed $(INSTALLED). Right-click a photo or video in Finder: Turnover ›"

# macOS keeps the extension's empty sandbox container (~/Library/Containers/$(EXTENSION_ID))
# and won't let a shell without Full Disk Access delete it; remove it in Finder if you like.
uninstall:
	@pkill -x Turnover || true
	-pluginkit -e ignore -i $(EXTENSION_ID)
	@pkill -x TurnoverFinder || true
	-pluginkit -r "$(INSTALLED)/$(EXTENSION)"
	-$(LSREGISTER) -u "$(INSTALLED)"
	rm -rf "$(INSTALLED)"
	-tccutil reset All $(APP_ID) >/dev/null
	@echo "Uninstalled Turnover."

test:
	swift test

# XcodeGen names the package's folder reference after the folder it runs in, so it runs through
# a link named "turnover" (left in a new temporary folder): every clone, whatever its folder is
# called, then gets the same project.
project:
	@$(XCODEGEN) --version | grep -q "$(XCODEGEN_VERSION)" || \
		echo "warning: CI checks the project with XcodeGen $(XCODEGEN_VERSION); this is $$($(XCODEGEN) --version)"
	@link="$$(mktemp -d)/turnover" && ln -s "$(CURDIR)" "$$link" && \
		$(XCODEGEN) generate --spec "$$link/project.yml"

clean:
	rm -rf build
