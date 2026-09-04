# Air Mouse — developer entry points. All targets work without `sudo xcode-select`.
export DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
XCODEGEN ?= $(shell command -v xcodegen 2>/dev/null || echo $(CURDIR)/tools/bin/xcodegen)
SIM ?= platform=iOS Simulator,name=iPhone 17 Pro
NOSIGN = CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=
XCB = xcodebuild -quiet

.PHONY: all gen kit-build kit-test ios-build ios-test mac-build mac-test build test clean

all: build

gen:
	cd apps/AirMouse-iOS && "$(XCODEGEN)" generate --quiet
	cd apps/AirMouse-Mac && "$(XCODEGEN)" generate --quiet

kit-build:
	cd Packages/AirMouseKit && swift build

kit-test:
	cd Packages/AirMouseKit && swift test

ios-build: gen
	$(XCB) -project apps/AirMouse-iOS/AirMouse.xcodeproj -scheme AirMouse -destination '$(SIM)' $(NOSIGN) build

ios-test: gen
	$(XCB) -project apps/AirMouse-iOS/AirMouse.xcodeproj -scheme AirMouse -destination '$(SIM)' $(NOSIGN) test -only-testing:AirMouseTests

mac-build: gen
	$(XCB) -project apps/AirMouse-Mac/AirMouseHelper.xcodeproj -scheme AirMouseHelper -destination 'platform=macOS' $(NOSIGN) build

mac-test: gen
	$(XCB) -project apps/AirMouse-Mac/AirMouseHelper.xcodeproj -scheme AirMouseHelper -destination 'platform=macOS' $(NOSIGN) test

build: kit-build ios-build mac-build
test: kit-test ios-test mac-test

clean:
	rm -rf Packages/AirMouseKit/.build apps/*/*.xcodeproj
