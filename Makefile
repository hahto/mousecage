APP_NAME   := Mouselock
EXECUTABLE := mouselock
BUNDLE_ID  ?= dev.eetu.mouselock
VERSION    := 0.0.1

# "-" = ad-hoc. Use a fixed self-signed cert name here to keep Accessibility
# access across rebuilds: make SIGN_ID="mouselock-dev"
SIGN_ID    ?= -
ARCHS      ?= -arch arm64 -arch x86_64
MIN_OS     := -mmacosx-version-min=13.0

CC        := clang
CFLAGS    := -std=c11 -O2 -Wall -Wextra $(ARCHS) $(MIN_OS)
OBJCFLAGS := -fobjc-arc -O2 -Wall -Wextra $(ARCHS) $(MIN_OS)
LDFLAGS   := $(ARCHS) $(MIN_OS)

BUILD      := build
APP_BUNDLE := $(BUILD)/$(APP_NAME).app
CLI        := $(BUILD)/$(EXECUTABLE)-cli
ZIP        := $(BUILD)/$(APP_NAME)-$(VERSION).zip

.PHONY: all app cli run zip clean reset-tcc

all: app cli

app: $(APP_BUNDLE)
cli: $(CLI)

$(BUILD):
	mkdir -p $@

$(BUILD)/core.o: src/core.c src/core.h | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/core_debug.o: src/core.c src/core.h | $(BUILD)
	$(CC) $(CFLAGS) -DML_DEBUG -c $< -o $@

$(BUILD)/cli.o: src/cli.c src/core.h | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@

$(BUILD)/app.o: src/app.m src/core.h | $(BUILD)
	$(CC) $(OBJCFLAGS) -c $< -o $@

$(CLI): $(BUILD)/cli.o $(BUILD)/core_debug.o
	$(CC) $(LDFLAGS) $^ -framework ApplicationServices -o $@

$(APP_BUNDLE): $(BUILD)/app.o $(BUILD)/core.o res/Info.plist Makefile
	rm -rf $@
	mkdir -p $@/Contents/MacOS
	$(CC) $(LDFLAGS) $(BUILD)/app.o $(BUILD)/core.o \
	    -framework Cocoa -framework ApplicationServices \
	    -o $@/Contents/MacOS/$(EXECUTABLE)
	sed -e 's/@VERSION@/$(VERSION)/g' \
	    -e 's/@BUNDLE_ID@/$(BUNDLE_ID)/g' \
	    -e 's/@EXECUTABLE@/$(EXECUTABLE)/g' \
	    res/Info.plist > $@/Contents/Info.plist
	plutil -lint $@/Contents/Info.plist
	codesign --force --sign "$(SIGN_ID)" $@

run: app
	-pkill -x $(EXECUTABLE)
	open $(APP_BUNDLE)

zip: app
	rm -f $(ZIP)
	ditto -c -k --keepParent $(APP_BUNDLE) $(ZIP)

reset-tcc:
	tccutil reset Accessibility $(BUNDLE_ID)

clean:
	rm -rf $(BUILD)
