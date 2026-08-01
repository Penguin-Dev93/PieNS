APP_NAME := PieNS
BUNDLE_ID := com.penguin-dev93.PieNS
HELPER_LABEL := com.penguin-dev93.PieNS.Helper
CONFIGURATION ?= release
BUILD_DIR := build
APP_BUNDLE := $(BUILD_DIR)/$(APP_NAME).app
SWIFT_CONFIG := $(if $(filter release,$(CONFIGURATION)),-c release,)
SWIFT_FLAGS := --disable-sandbox --cache-path "$(PWD)/.build/swiftpm-cache"
SWIFT_ENV := HOME="$(PWD)/.build/home" CLANG_MODULE_CACHE_PATH="$(PWD)/.build/module-cache"
SWIFT_BIN_DIR := .build/$(CONFIGURATION)

.PHONY: all clean test icon app run

all: app

test:
	$(SWIFT_ENV) swift test $(SWIFT_FLAGS)

icon:
	$(SWIFT_ENV) swift Tools/generate_icon.swift

app: icon
	$(SWIFT_ENV) swift build $(SWIFT_FLAGS) $(SWIFT_CONFIG)
	rm -rf "$(APP_BUNDLE)"
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	cp "$(SWIFT_BIN_DIR)/$(APP_NAME)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	cp "Resources/Info.plist" "$(APP_BUNDLE)/Contents/Info.plist"
	cp "Resources/PkgInfo" "$(APP_BUNDLE)/Contents/PkgInfo"
	cp "Resources/PieNS.icns" "$(APP_BUNDLE)/Contents/Resources/PieNS.icns"
	codesign --force --deep --sign - "$(APP_BUNDLE)"
	@echo "Built $(APP_BUNDLE)"

run: app
	open "$(APP_BUNDLE)"

clean:
	rm -rf "$(BUILD_DIR)" .build
