# cmd-m

Typed a whole sentence in the wrong keyboard language? Select it, press **⌘M**, and cmd-m retypes it in your other layout — in place, in any app.

```
akuo    ⌘M →   שלום
שלום    ⌘M →   akuo
```

cmd-m is a tiny macOS menu bar utility. It is **layout-agnostic**: it reads the actual keyboard layouts you have enabled in System Settings (Hebrew, Russian, Greek, Arabic, French AZERTY, …) and remaps character-by-character between them using the system's own key layout data. Nothing is hardcoded.

## How it works

1. You select text and press the hotkey (default **⌘M**).
2. cmd-m copies the selection (simulated ⌘C), figures out which of your enabled layouts the text was typed in, retypes each character in the *next* enabled layout, and pastes the result back (simulated ⌘V).
3. It also **switches your active input source** to the target layout, so you can just keep typing in the right language.
4. Your previous clipboard text is restored afterwards.

Because it detects the source layout automatically, the same hotkey converts in both directions.

## Install

Requires macOS 13+, Xcode command line tools (`xcode-select --install`), and **at least two keyboard layouts enabled** in System Settings → Keyboard → Input Sources.

```sh
git clone https://github.com/YOUR-USERNAME/cmd-m.git
cd cmd-m
```

Then pick one of the two ways to run it:

### Option A — Quick Action (no background process)

Installs a macOS Service whose shortcut you assign natively in System Settings. macOS runs it on demand; nothing stays resident and no Accessibility permission is needed.

```sh
make install-quick-action
```

Then: **System Settings → Keyboard → Keyboard Shortcuts → Services → Text → "Convert Keyboard Layout"** — enable it and assign a shortcut.

> Pick a shortcut like **⌃⌘M** here. Plain ⌘M won't work as a Services shortcut, because the frontmost app's own menu shortcuts (⌘M = Minimize) take priority over Services.

Caveat: Services only work in apps that support the macOS Services menu — that's most native apps (Safari, Mail, Notes, Xcode, …) but not all Chromium/Electron apps. If it does nothing in some app, use Option B.

### Option B — Background agent with a global hotkey (works everywhere)

A single small binary that stays running and owns a truly global hotkey (default **⌘M**):

```sh
make install        # builds and copies the binary to /usr/local/bin
cmd-m               # start it (add --no-menubar to hide the menu bar icon)
```

On first launch, macOS will ask you to grant **Accessibility** permission (System Settings → Privacy & Security → Accessibility) — needed to simulate ⌘C/⌘V. Grant it and relaunch.

> **Note:** ⌘M is macOS's default "minimize window" shortcut. While cmd-m is running it takes over ⌘M globally. If you'd rather keep minimize, pick another hotkey (below).

#### Custom hotkey

```sh
cmd-m --hotkey ctrl+alt+m
cmd-m --hotkey cmd+fn       # modifier-only chord using the fn/Globe key
```

Modifiers: `cmd`, `ctrl`, `alt`, `shift` (at least one required). Keys: `a`–`z`, `0`–`9`, `space`, `tab`, `f1`–`f12`.

A chord containing `fn` (or `globe`) uses no regular key at all — it fires when the listed modifiers are held together (e.g. `cmd+fn`). Nothing in macOS uses these combinations, so they never clash with app shortcuts like ⌘M = minimize. Works on Apple keyboards; some third-party keyboards handle fn internally and never report it to macOS.

#### Start at login

```sh
cp resources/com.cmd-m.plist ~/Library/LaunchAgents/
launchctl load ~/Library/LaunchAgents/com.cmd-m.plist
```

Edit the plist first if you want a custom hotkey or no menu bar icon (add the flags to `ProgramArguments`).

## Command line use

```sh
cmd-m --convert "akuo"           # prints: שלום
echo "akuo" | cmd-m --convert    # same, reading stdin
cmd-m --switch --convert "akuo"  # also switches the active layout
cmd-m --layouts                  # lists the layouts cmd-m detected
```

## Limitations

- Works in apps where ⌘C/⌘V work on the selection (i.e. almost everywhere, but not in password fields or apps that block synthetic events).
- Only plain-text clipboard contents are preserved across a conversion.
- Input methods without a fixed key map (Chinese, Japanese, Korean IMEs) are skipped; only real key layouts participate.
- With three or more layouts enabled, conversion cycles to the *next* layout in system order — press again to keep cycling.

## Uninstall

```sh
launchctl unload ~/Library/LaunchAgents/com.cmd-m.plist 2>/dev/null
rm -f ~/Library/LaunchAgents/com.cmd-m.plist /usr/local/bin/cmd-m
rm -rf ~/Library/Services/"Convert Keyboard Layout.workflow"
```

Then remove cmd-m from System Settings → Privacy & Security → Accessibility (if you used Option B).

## License

[MIT](LICENSE) — fork away.
