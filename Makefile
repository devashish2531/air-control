# Air Control — developer entry points. All targets work without `sudo xcode-select`.
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
XCODEGEN ?= $(shell command -v xcodegen 2>/dev/null || echo $(CURDIR)/tools/bin/xcodegen)
SIM ?= platform=iOS Simulator,name=iPhone 17 Pro
NOSIGN = CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=
XCB = xcodebuild -quiet

.PHONY: all gen kit-build kit-test ios-build ios-test mac-build mac-test build test clean

all: build

gen:
	cd apps/AirControl-iOS && "$(XCODEGEN)" generate --quiet
	cd apps/AirControl-Mac && "$(XCODEGEN)" generate --quiet

kit-build:
	cd Packages/AirControlKit && swift build

kit-test:
	cd Packages/AirControlKit && swift test

ios-build: gen
	$(XCB) -project apps/AirControl-iOS/AirControl.xcodeproj -scheme AirControl -destination '$(SIM)' $(NOSIGN) build

ios-test: gen
	$(XCB) -project apps/AirControl-iOS/AirControl.xcodeproj -scheme AirControl -destination '$(SIM)' $(NOSIGN) test -only-testing:AirControlTests

mac-build: gen
	$(XCB) -project apps/AirControl-Mac/AirControlHelper.xcodeproj -scheme AirControlHelper -destination 'platform=macOS' $(NOSIGN) build

mac-test: gen
	$(XCB) -project apps/AirControl-Mac/AirControlHelper.xcodeproj -scheme AirControlHelper -destination 'platform=macOS' $(NOSIGN) test

build: kit-build ios-build mac-build
test: kit-test ios-test mac-test

clean:
	rm -rf Packages/AirControlKit/.build apps/*/*.xcodeproj

# Build the Mac helper, clear its (now stale) Accessibility grant, and launch it. Every rebuild changes the
# ad-hoc code signature, so macOS silently ignores the previous grant (decisions A10 / spec §5.2). Re-grant
# Accessibility when the onboarding window appears. Stable signing via Config/Local.xcconfig avoids this.
.PHONY: mac-run
mac-run: mac-build
	-pkill -f "AirControl.app/Contents/MacOS/AirControl"
	@APP="$$(ls -d ~/Library/Developer/Xcode/DerivedData/AirControlHelper-*/Build/Products/Debug/AirControl.app | head -1)"; \
	ID="$$(security find-identity -v -p codesigning | grep 'Apple Development:' | grep -m1 -oE '[0-9A-F]{40}')"; \
	if [ -n "$$ID" ]; then \
	  echo "Signing with $$ID"; \
	  codesign --force --options runtime --timestamp=none \
	    --entitlements apps/AirControl-Mac/Sources/AirControlHelper.entitlements --sign "$$ID" "$$APP"; \
	  codesign -dv "$$APP" 2>&1 | grep TeamIdentifier; \
	else echo "No Apple Development identity found; app stays ad-hoc signed (re-grant Accessibility after every rebuild)"; tccutil reset Accessibility com.aircontrol.helper$(BUNDLE_ID_SUFFIX); fi; \
	open "$$APP"

# Build for the first connected iPhone/iPad and install + launch it. Needs an Apple ID signed into Xcode
# and DEVELOPMENT_TEAM / IOS_BUNDLE_ID in Config/Local.xcconfig (the bundle id must be free on your team).
.PHONY: ios-run
ios-run: gen
	@UDID="$$(xcrun devicectl list devices 2>/dev/null | grep -E '\b(connected|available)\b' | grep -oE '[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}' | head -1)"; \
	[ -n "$$UDID" ] || { echo "No connected iOS device found (xcrun devicectl list devices)"; exit 1; }; \
	xcodebuild -quiet -project apps/AirControl-iOS/AirControl.xcodeproj -scheme AirControl -destination "id=$$UDID" \
	  -allowProvisioningUpdates -allowProvisioningDeviceRegistration CODE_SIGN_STYLE=Automatic build && \
	APP="$$(ls -d ~/Library/Developer/Xcode/DerivedData/AirControl-*/Build/Products/Debug-iphoneos/AirControl.app | head -1)"; \
	BUNDLE="$$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$$APP/Info.plist")"; \
	xcrun devicectl device install app --device "$$UDID" "$$APP" >/dev/null && \
	xcrun devicectl device process launch --device "$$UDID" "$$BUNDLE"
