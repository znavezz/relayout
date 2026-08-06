# cmd-m

Typed a whole sentence in the wrong keyboard language? Select it, hold **⌘** and tap **Fn/Globe**, and cmd-m retypes it in your other layout — in place, in any app — then switches your keyboard language to match.

```
akuo    ⌘Fn →   שלום
שלום    ⌘Fn →   akuo
```

cmd-m is a tiny macOS menu bar utility. It is **layout-agnostic**: it reads the actual keyboard layouts you have enabled in System Settings (Hebrew, Russian, Greek, Arabic, French AZERTY, …) and remaps character-by-character between them using the system's own key layout data. Nothing is hardcoded.

## How it works

1. You select text and press the hotkey (default **⌘ Fn** — hold ⌘, tap the Fn/Globe key).
2. cmd-m copies the selection (simulated ⌘C), figures out which of your enabled layouts the text was typed in, retypes each character in the *next* enabled layout, and pastes the result back (simulated ⌘V).
3. It also **switches your active input source** to the target layout, so you can just keep typing in the right language.
4. Your previous clipboard text is restored afterwards.

Because it detects the source layout automatically, the same hotkey converts in both directions.

## Install

Requires macOS 13+, Xcode command line tools (`xcode-select --install`), and **at least two keyboard layouts enabled** in System Settings → Keyboard → Input Sources.

```sh
git clone https://github.com/znavezz/cmd-m.git
cd cmd-m
```

Then pick one of the two ways to run it:

### Option A — Background agent (recommended: works in every app)

One command installs the binary (to `~/.local/bin`, no sudo), starts the agent now, and registers it to start at login:

```sh
make install-agent
```

macOS will show **one permission prompt** ("cmd-m would like to control this computer using accessibility features") — click *Open System Settings* and switch **cmd-m** on. That's the only setup: cmd-m detects the grant within seconds and arms itself. The permission is needed to simulate ⌘C/⌘V on your selection.

The default hotkey is **⌘ Fn** — a chord that clashes with no system or app shortcut. If your keyboard has no usable Fn/Globe key (some non-Apple keyboards handle Fn internally), click the **⇄** menu bar icon → **Shortcut** and pick another combo like ⌃⌘M.

### Option B — Quick Action (no background process, native apps only)

Installs a macOS Service instead: macOS runs it on demand, nothing stays resident, and **no permission is needed at all**.

```sh
make install-quick-action
```

The shortcut **⌃⌘M** is assigned automatically — nothing to configure. To pick a different one, either pass it at install time (`make install-quick-action SERVICE_SHORTCUT='~@k'` — `@`=cmd `^`=ctrl `~`=alt `$`=shift) or change it later in System Settings → Keyboard → Keyboard Shortcuts → Services → Text → "Convert Keyboard Layout". Apps that were already running see the new service after they're relaunched.

> Avoid plain ⌘-letter shortcuts here (⌘M, ⌘J, …): the frontmost app's own menu shortcuts take priority over Services, so they'll silently do the app's thing instead.

Caveat: Services only work in apps that support the macOS Services menu — most native apps (Safari, Mail, Notes, Xcode, …) but **not** Chromium/Electron apps like Chrome or VS Code. If you type in those, use Option A.

#### Changing the hotkey

Click the **⇄** menu bar icon → **Shortcut** and pick one — it applies instantly, persists across restarts, and needs no configuration files. The default, **⌘ Fn**, is a modifier-only chord that no app or system shortcut uses; the other presets are there for keyboards where Fn isn't available.

The menu also shows a **⚠️ Grant Accessibility Access…** item whenever the permission is missing (e.g. after rebuilding the binary) — click it to jump to the right settings pane; cmd-m detects the grant automatically, no relaunch needed.

For scripting or `--no-menubar` setups, the flag still works and overrides the menu choice:

```sh
cmd-m --hotkey ctrl+alt+m
cmd-m --hotkey cmd+fn       # modifier-only chord using the fn/Globe key
```

Modifiers: `cmd`, `ctrl`, `alt`, `shift` (at least one required). Keys: `a`–`z`, `0`–`9`, `space`, `tab`, `f1`–`f12`.

A chord containing `fn` (or `globe`) uses no regular key at all — it fires when the listed modifiers are held together (e.g. `cmd+fn`). Nothing in macOS uses these combinations, so they never clash with app shortcuts like ⌘M = minimize. Works on Apple keyboards; some third-party keyboards handle fn internally and never report it to macOS.

#### Start at login

`make install-agent` already registers this (via `~/Library/LaunchAgents/com.cmd-m.plist`). To pass flags like `--no-menubar` or a fixed `--hotkey`, add them to the `ProgramArguments` array in that file and run `launchctl kickstart -k gui/$(id -u)/com.cmd-m`.

## Command line use

```sh
cmd-m --convert "akuo"           # prints: שלום
echo "akuo" | cmd-m --convert    # same, reading stdin
cmd-m --switch --convert "akuo"  # also switches the active layout
cmd-m --layouts                  # lists the layouts cmd-m detected
```

(The default install puts the binary in `~/.local/bin`, which may not be on your `PATH` — add it, or install with `sudo make install PREFIX=/usr/local`.)

## Limitations

- Works in apps where ⌘C/⌘V work on the selection (i.e. almost everywhere, but not in password fields or apps that block synthetic events).
- Only plain-text clipboard contents are preserved across a conversion.
- Input methods without a fixed key map (Chinese, Japanese, Korean IMEs) are skipped; only real key layouts participate.
- With three or more layouts enabled, conversion cycles to the *next* layout in system order — press again to keep cycling.

## Uninstall

```sh
make uninstall     # stops the agent, removes the binary, plist, and Quick Action
```

Then remove cmd-m from System Settings → Privacy & Security → Accessibility (if you used Option A).

## License

[MIT](LICENSE) — fork away.

Maintained by [znavezz](https://github.com/znavezz) · znavez@gmail.com
