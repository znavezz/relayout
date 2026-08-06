PREFIX ?= /usr/local
SERVICES_DIR = $(HOME)/Library/Services
WORKFLOW = Convert Keyboard Layout.workflow

.PHONY: build install install-quick-action uninstall clean

build:
	swift build -c release

install: build
	install -d $(PREFIX)/bin
	install .build/release/cmd-m $(PREFIX)/bin/cmd-m

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
	rm -f $(PREFIX)/bin/cmd-m
	rm -rf "$(SERVICES_DIR)/$(WORKFLOW)"

clean:
	swift package clean
