# Installs under the user's home by default so no sudo is ever needed.
# Use PREFIX=/usr/local (with sudo) if you want relayout on the default PATH.
PREFIX ?= $(HOME)/.local
SERVICES_DIR = $(HOME)/Library/Services
WORKFLOW = Convert Keyboard Layout.workflow
AGENT_PLIST = $(HOME)/Library/LaunchAgents/com.relayout.plist

.PHONY: build install install-agent install-quick-action uninstall clean

build:
	swift build -c release

install: build
	install -d $(PREFIX)/bin
	install .build/release/relayout $(PREFIX)/bin/relayout

# Installs the background agent: starts now and at every login.
# macOS will show one Accessibility permission prompt — approve it and
# relayout arms itself automatically; no restart needed.
install-agent: install
	mkdir -p "$(HOME)/Library/LaunchAgents"
	sed "s|/usr/local/bin/relayout|$(PREFIX)/bin/relayout|" "resources/com.relayout.plist" > "$(AGENT_PLIST)"
	-launchctl bootout gui/$$(id -u)/com.relayout 2>/dev/null
	launchctl bootstrap gui/$$(id -u) "$(AGENT_PLIST)"

# Installs the Quick Action and pre-assigns its shortcut (default ctrl+cmd+M,
# shown as ^@m; change with SERVICE_SHORTCUT='...' using @=cmd ^=ctrl ~=alt $$=shift).
# The shortcut remains editable in System Settings -> Keyboard -> Keyboard
# Shortcuts -> Services -> Text. Apps already running pick it up after relaunch.
SERVICE_SHORTCUT ?= ^@m

install-quick-action: install
	mkdir -p "$(SERVICES_DIR)"
	rm -rf "$(SERVICES_DIR)/$(WORKFLOW)"
	cp -R "resources/$(WORKFLOW)" "$(SERVICES_DIR)/"
	defaults write pbs NSServicesStatus -dict-add '"(null) - Convert Keyboard Layout - runWorkflowAsService"' '{key_equivalent = "$(SERVICE_SHORTCUT)"; enabled_services_menu = 1;}'
	-/System/Library/CoreServices/pbs -update

uninstall:
	-launchctl bootout gui/$$(id -u)/com.relayout 2>/dev/null
	rm -f $(PREFIX)/bin/relayout "$(AGENT_PLIST)"
	rm -rf "$(SERVICES_DIR)/$(WORKFLOW)"

# Builds a double-clickable relayout.app (menu bar app). When launched as an
# app it registers itself as a login item and installs the Quick Action —
# no terminal steps for end users.
APP = relayout.app

app: build
	rm -rf "$(APP)"
	mkdir -p "$(APP)/Contents/MacOS" "$(APP)/Contents/Resources"
	cp .build/release/relayout "$(APP)/Contents/MacOS/relayout"
	cp resources/Info.plist "$(APP)/Contents/Info.plist"
	cp -R "resources/$(WORKFLOW)" "$(APP)/Contents/Resources/"
	codesign --force --deep -s - "$(APP)"

clean:
	rm -rf "$(APP)"
	swift package clean
