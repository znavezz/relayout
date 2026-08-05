PREFIX ?= /usr/local
SERVICES_DIR = $(HOME)/Library/Services
WORKFLOW = Convert Keyboard Layout.workflow

.PHONY: build install install-quick-action uninstall clean

build:
	swift build -c release

install: build
	install -d $(PREFIX)/bin
	install .build/release/cmd-m $(PREFIX)/bin/cmd-m

# Installs the Quick Action so a shortcut can be assigned in
# System Settings -> Keyboard -> Keyboard Shortcuts -> Services -> Text.
install-quick-action: install
	mkdir -p "$(SERVICES_DIR)"
	rm -rf "$(SERVICES_DIR)/$(WORKFLOW)"
	cp -R "resources/$(WORKFLOW)" "$(SERVICES_DIR)/"
	-/System/Library/CoreServices/pbs -update

uninstall:
	rm -f $(PREFIX)/bin/cmd-m
	rm -rf "$(SERVICES_DIR)/$(WORKFLOW)"

clean:
	swift package clean
