#!/bin/sh
# relayout installer — works with the prebuilt release (no developer tools
# needed) or from a source checkout (builds first if swift is available).
set -e
cd "$(dirname "$0")"

BIN_DIR="$HOME/.local/bin"
PLIST="$HOME/Library/LaunchAgents/com.relayout.plist"

if [ ! -f relayout ]; then
  if command -v swift >/dev/null 2>&1; then
    echo "No prebuilt binary here — building from source…"
    swift build -c release
    cp .build/release/relayout relayout
  else
    echo "error: no 'relayout' binary found next to install.sh" >&2
    exit 1
  fi
fi

mkdir -p "$BIN_DIR"
install -m 755 relayout "$BIN_DIR/relayout"
# Clear the browser-download quarantine flag, if any.
xattr -d com.apple.quarantine "$BIN_DIR/relayout" 2>/dev/null || true

# Background agent: start now and at every login.
AGENTS_DIR="$HOME/Library/LaunchAgents"
mkdir -p "$AGENTS_DIR" 2>/dev/null || true
if [ ! -w "$AGENTS_DIR" ] || { [ -e "$PLIST" ] && [ ! -w "$PLIST" ]; }; then
  echo "" >&2
  echo "Cannot write to $AGENTS_DIR — it is owned by another user" >&2
  echo "(usually leftovers from an old 'sudo' command). Fix it with:" >&2
  echo "" >&2
  echo "    sudo chown -R \"\$USER\" \"$AGENTS_DIR\"" >&2
  echo "" >&2
  echo "then run ./install.sh again." >&2
  exit 1
fi
sed "s|/usr/local/bin/relayout|$BIN_DIR/relayout|" "resources/com.relayout.plist" > "$PLIST"
launchctl bootout "gui/$(id -u)/com.relayout" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST" || { sleep 2; launchctl bootstrap "gui/$(id -u)" "$PLIST"; }

# Quick Action for native apps, with its shortcut (⌃⌘M) pre-assigned.
mkdir -p "$HOME/Library/Services"
rm -rf "$HOME/Library/Services/Convert Keyboard Layout.workflow"
cp -R "resources/Convert Keyboard Layout.workflow" "$HOME/Library/Services/"
defaults write pbs NSServicesStatus -dict-add '"(null) - Convert Keyboard Layout - runWorkflowAsService"' '{key_equivalent = "^@m"; enabled_services_menu = 1;}'
/System/Library/CoreServices/pbs -update 2>/dev/null || true

echo ""
echo "relayout is installed and running (⇄ in the menu bar)."
echo ""
echo "One last step — macOS asks for Accessibility permission:"
echo "  System Settings → Privacy & Security → Accessibility → enable \"relayout\""
echo ""
echo "Then select wrong-layout text anywhere and press ⌘Fn (or ⌘?)."
