APP_NAME = Voicer
BUNDLE_ID = com.voicer.app
BUILD_DIR = .build
APP_BUNDLE = $(BUILD_DIR)/$(APP_NAME).app
BINARY = $(BUILD_DIR)/release/Voicer

.PHONY: build run install clean

build:
	swift build -c release
	mkdir -p "$(APP_BUNDLE)/Contents/MacOS"
	mkdir -p "$(APP_BUNDLE)/Contents/Resources"
	cp "$(BINARY)" "$(APP_BUNDLE)/Contents/MacOS/$(APP_NAME)"
	cp Resources/Info.plist "$(APP_BUNDLE)/Contents/Info.plist"
	codesign --force --deep --sign - "$(APP_BUNDLE)"

run: build
	open "$(APP_BUNDLE)"

install: build
	cp -r "$(APP_BUNDLE)" /Applications/

clean:
	rm -rf "$(BUILD_DIR)"
	swift package clean
