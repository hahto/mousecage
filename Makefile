APP_NAME   := Mousecage
EXECUTABLE := mousecage
BUNDLE_ID  ?= dev.eetu.mousecage
VERSION    := 0.0.1
 
# "-" = ad-hoc. Use a fixed self-signed cert name here to keep Accessibility
# access across rebuilds: make SIGN_ID="mousecage-dev"
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
ICNS       := $(BUILD)/AppIcon.icns
ICONSET    := $(BUILD)/AppIcon.iconset
ZIP        := $(BUILD)/$(APP_NAME)-$(VERSION).zip
DMG        := $(BUILD)/$(APP_NAME)-$(VERSION).dmg
DMG_STAGE  := $(BUILD)/dmg
 
.PHONY: all app cli run zip dmg clean reset-tcc
 
all: app cli
 
app: $(APP_BUNDLE)
cli: $(CLI)
 
$(BUILD):
	mkdir -p $@
 
# ---- objects ----
 
$(BUILD)/core.o: src/core.c src/core.h | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@
 
$(BUILD)/core_debug.o: src/core.c src/core.h | $(BUILD)
	$(CC) $(CFLAGS) -DML_DEBUG -c $< -o $@
 
$(BUILD)/cli.o: src/cli.c src/core.h | $(BUILD)
	$(CC) $(CFLAGS) -c $< -o $@
 
$(BUILD)/app.o: src/app.m src/core.h | $(BUILD)
	$(CC) $(OBJCFLAGS) -c $< -o $@
 
# ---- CLI (debug build) ----
 
$(CLI): $(BUILD)/cli.o $(BUILD)/core_debug.o
	$(CC) $(LDFLAGS) $^ -framework ApplicationServices -o $@
 
# ---- icon ----
 
$(ICNS): res/icon.png | $(BUILD)
	rm -rf $(ICONSET) && mkdir $(ICONSET)
	for size in 16 32 128 256 512; do \
	  sips -z $$size $$size $< --out $(ICONSET)/icon_$${size}x$${size}.png >/dev/null; \
	  sips -z $$((size*2)) $$((size*2)) $< --out $(ICONSET)/icon_$${size}x$${size}@2x.png >/dev/null; \
	done
	iconutil -c icns $(ICONSET) -o $@
 
# ---- app bundle ----
 
$(APP_BUNDLE): $(BUILD)/app.o $(BUILD)/core.o $(ICNS) res/Info.plist Makefile
	rm -rf $@
	mkdir -p $@/Contents/MacOS $@/Contents/Resources
	$(CC) $(LDFLAGS) $(BUILD)/app.o $(BUILD)/core.o \
	    -framework Cocoa -framework ApplicationServices \
	    -o $@/Contents/MacOS/$(EXECUTABLE)
	cp $(ICNS) $@/Contents/Resources/AppIcon.icns
	sed -e 's/@VERSION@/$(VERSION)/g' \
	    -e 's/@BUNDLE_ID@/$(BUNDLE_ID)/g' \
	    -e 's/@EXECUTABLE@/$(EXECUTABLE)/g' \
	    -e 's/@APP_NAME@/$(APP_NAME)/g' \
	    res/Info.plist > $@/Contents/Info.plist
	plutil -lint $@/Contents/Info.plist
	codesign --force --sign "$(SIGN_ID)" $@
 
# ---- run / package ----
 
run: app
	-pkill -x $(EXECUTABLE); while pgrep -x $(EXECUTABLE) >/dev/null; do sleep 0.1; done
	open $(APP_BUNDLE)
 
zip: app
	rm -f $(ZIP)
	ditto -c -k --keepParent $(APP_BUNDLE) $(ZIP)
 
dmg: app
	rm -rf $(DMG_STAGE) $(DMG)
	mkdir -p $(DMG_STAGE)
	ditto $(APP_BUNDLE) $(DMG_STAGE)/$(APP_NAME).app
	ln -s /Applications $(DMG_STAGE)/Applications
	hdiutil create -volname "$(APP_NAME)" -srcfolder $(DMG_STAGE) -ov -format UDZO $(DMG)
	rm -rf $(DMG_STAGE)
 
reset-tcc:
	tccutil reset Accessibility $(BUNDLE_ID)
 
clean:
	rm -rf $(BUILD)
