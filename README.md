# relayout

Typed a whole sentence in the wrong keyboard language? Select it, hold **⌘** and tap **Fn/Globe**, and relayout retypes it in your other layout — in place, in any app — then switches your keyboard language to match.

Ever typed `akuo` when you meant `שלום`? Or `ghbdtn` instead of `привет`?

```
akuo      ⌘Fn →   שלום
ghbdtn    ⌘Fn →   привет
שלום      ⌘Fn →   akuo
```

relayout is a tiny macOS menu bar utility. It is **layout-agnostic**: it reads the actual keyboard layouts you have enabled in System Settings (Hebrew, Russian, Greek, Arabic, French AZERTY, …) and remaps character-by-character between them using the system's own key layout data. Nothing is hardcoded.

## How it works

1. You select text and press the hotkey (default: **⌘ Fn** — hold ⌘, tap the Fn/Globe key — or **⌘ ?**; both are armed out of the box, so keyboards whose Fn key is invisible to macOS work automatically).
2. relayout copies the selection (simulated ⌘C), figures out which of your enabled layouts the text was typed in, retypes each character in the *next* enabled layout, and pastes the result back (simulated ⌘V).
3. It also **switches your active input source** to the target layout, so you can just keep typing in the right language.
4. Your previous clipboard text is restored afterwards.

Because it detects the source layout automatically, the same hotkey converts in both directions.

## Install

Requires macOS 10.15 (Catalina) or newer — Apple Silicon and Intel — and **at least two keyboard layouts enabled** in System Settings → Keyboard → Input Sources (on macOS 12 and earlier: System Preferences → Keyboard → Input Sources; the Accessibility permission lives under System Preferences → Security & Privacy → Privacy).

### Easiest — the app (no terminal, no developer tools)

1. Download **relayout.app.zip** from the [latest release](https://github.com/znavezz/relayout/releases/latest), unzip, and drag **relayout.app** into Applications.
2. Open it. The first time, macOS blocks apps from unidentified developers — go to **System Settings → Privacy & Security** and click **"Open Anyway"**. (This one-time step exists because relayout isn't notarized with a paid Apple developer subscription; the full source is right here if you want to audit or build it yourself.)
3. Enable **relayout** under **Privacy & Security → Accessibility** when prompted.

That's everything: it starts at login by itself, installs the Quick Action for native apps, and the **⇄** menu bar icon manages the shortcut.

### Terminal one-liner — prebuilt, still no developer tools

```sh
curl -L https://github.com/znavezz/relayout/releases/latest/download/relayout-macos.tar.gz | tar xz
cd relayout-macos && ./install.sh
```

### From source

Needs the Xcode command line tools (`xcode-select --install`).

```sh
git clone https://github.com/znavezz/relayout.git
cd relayout
```

Then pick one of the two ways to run it:

### Option A — Background agent (recommended: works in every app)

One command installs the binary (to `~/.local/bin`, no sudo), starts the agent now, and registers it to start at login:

```sh
make install-agent
```

macOS will show **one permission prompt** ("relayout would like to control this computer using accessibility features") — click *Open System Settings* and switch **relayout** on. That's the only setup: relayout detects the grant within seconds and arms itself. The permission is needed to simulate ⌘C/⌘V on your selection.

The default hotkey is **⌘ Fn** *or* **⌘ ?** — both are active. The second exists because some non-Apple keyboards handle Fn internally and never report it to macOS. (⌘? globally replaces the rarely-used Help-menu-search shortcut while relayout runs.) Presets for other combos — and a **Custom…** option where you type any shortcut you like — are two clicks away in the **⇄** menu bar icon → **Shortcut**.

### Option B — Quick Action (no background process, native apps only)

Installs a macOS Service instead: macOS runs it on demand, nothing stays resident, and **no permission is needed at all**.

```sh
make install-quick-action
```

The shortcut **⌃⌘M** is assigned automatically — nothing to configure. To pick a different one, either pass it at install time (`make install-quick-action SERVICE_SHORTCUT='~@k'` — `@`=cmd `^`=ctrl `~`=alt `$`=shift) or change it later in System Settings → Keyboard → Keyboard Shortcuts → Services → Text → "Convert Keyboard Layout". Apps that were already running see the new service after they're relaunched.

> Avoid plain ⌘-letter shortcuts here (⌘M, ⌘J, …): the frontmost app's own menu shortcuts take priority over Services, so they'll silently do the app's thing instead.

Caveat: Services only work in apps that support the macOS Services menu — most native apps (Safari, Mail, Notes, Xcode, …) but **not** Chromium/Electron apps like Chrome or VS Code. If you type in those, use Option A.

#### Changing the hotkey

Click the **⇄** menu bar icon → **Shortcut** and pick one — it applies instantly, persists across restarts, and needs no configuration files. The default ("Auto") arms **⌘ Fn** and **⌘ ?** at once. Other presets: both ⌘ keys, both ⇧ keys, ⌃⌘M — plus **Custom…**, where you type any combo (e.g. `ctrl+alt+k`).

The menu also shows a **⚠️ Grant Accessibility Access…** item whenever the permission is missing (e.g. after rebuilding the binary) — click it to jump to the right settings pane; relayout detects the grant automatically, no relaunch needed.

For scripting or `--no-menubar` setups, the flag still works and overrides the menu choice:

```sh
relayout --hotkey ctrl+alt+m
relayout --hotkey "cmd+?"      # the second default
relayout --hotkey cmd+fn       # modifier-only chord using the fn/Globe key
relayout --hotkey cmd+cmd      # both Command keys together
relayout --hotkey shift+shift  # both Shift keys together
```

Modifiers: `cmd`, `ctrl`, `alt`, `shift` (at least one required). Keys: `a`–`z`, `0`–`9`, punctuation (`/ ? . , ; ' [ ] \ - =` and backtick), `space`, `tab`, `f1`–`f12`.

Modifier-only chords (`cmd+fn`, `cmd+alt`, `cmd+cmd`, `shift+shift`, …) use no regular key at all. They fire when the listed keys are **released together** — and never when another key was pressed in between, so chords that begin real shortcuts (⌥⌘Esc, ⌥⌘I, …) don't clash with them.

#### Start at login

`make install-agent` already registers this (via `~/Library/LaunchAgents/com.relayout.plist`). To pass flags like `--no-menubar` or a fixed `--hotkey`, add them to the `ProgramArguments` array in that file and run `launchctl kickstart -k gui/$(id -u)/com.relayout`.

## Command line use

```sh
relayout --convert "akuo"           # prints: שלום
echo "akuo" | relayout --convert    # same, reading stdin
relayout --switch --convert "akuo"  # also switches the active layout
relayout --layouts                  # lists the layouts relayout detected
```

(The default install puts the binary in `~/.local/bin`, which may not be on your `PATH` — add it, or install with `sudo make install PREFIX=/usr/local`.)

## Limitations

- Works in apps where ⌘C/⌘V work on the selection (i.e. almost everywhere, but not in password fields or apps that block synthetic events).
- Only plain-text clipboard contents are preserved across a conversion.
- Input methods without a fixed key map (Chinese, Japanese, Korean IMEs) are skipped; only real key layouts participate.
- With three or more layouts enabled, conversion cycles to the *next* layout in system order — press again to keep cycling.

## Troubleshooting

**"Permission denied … LaunchAgents/com.relayout.plist" during install** — your `~/Library/LaunchAgents` folder is owned by root (leftovers of some old `sudo` command). Fix the ownership once, then rerun the installer:

```sh
sudo chown -R "$USER" ~/Library/LaunchAgents
```

**"relayout can't be opened because Apple cannot check it for malicious software"** — the normal first-open warning for apps not notarized with a paid Apple developer subscription. Right-click (Control-click) the app → **Open** → **Open**; needed once only. If no Open button appears: System Settings → Privacy & Security → **Open Anyway** (older macOS: System Preferences → Security & Privacy → General).

**`xcrun: error: unable to find utility "xctest"` (or other build errors)** — your developer tools can't build from source. You don't need them: install a prebuilt build from the [releases page](https://github.com/znavezz/relayout/releases/latest) instead.

**The hotkey does nothing** — click the **⇄** menu bar icon: if it shows *⚠️ Grant Accessibility Access*, the permission is missing or went stale (this happens when the binary is replaced by an update — remove the relayout entry in the Accessibility list with **–**, then relaunch and approve the fresh prompt). If there's no ⇄ icon at all, check you're on macOS 10.15+.

**Something else** — check `~/Library/Logs/relayout.log`; every hotkey press, conversion, and permission problem is logged there.

## Uninstall

```sh
make uninstall     # stops the agent, removes the binary, plist, and Quick Action
```

Then remove relayout from System Settings → Privacy & Security → Accessibility (if you used Option A).

## License

[MIT](LICENSE) — fork away.

Maintained by [znavezz](https://github.com/znavezz) · znavez@gmail.com
