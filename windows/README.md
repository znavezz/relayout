# relayout for Windows

The Windows port of [relayout](../README.md): select text typed in the wrong
keyboard layout, press the hotkey (default **Ctrl+Alt+/**), and it's retyped
in your next installed layout — and the window's input language switches to
match. Same algorithm as the macOS version, same `akuo ⇄ שלום` behavior.

**Status: beta — needs testing on real Windows machines.** The converter
logic is a direct port of the proven macOS implementation, but the tray app
has not been field-tested yet. Reports welcome.

## Build & run

Requires the [.NET SDK](https://dotnet.microsoft.com/download) (6.0+) on
Windows:

```powershell
cd windows
dotnet run -c Release
```

To produce a standalone `relayout.exe` (no .NET runtime needed on the target
machine):

```powershell
dotnet publish -c Release -r win-x64 --self-contained -p:PublishSingleFile=true
```

## How it works

- A tray icon hosts the menu: convert now, change the shortcut (presets or
  any custom combo), toggle "Start with Windows", quit.
- The global hotkey is registered with `RegisterHotKey`; conversion simulates
  Ctrl+C, remaps every character between installed layouts using the
  system's own key tables (`ToUnicodeEx`), pastes with Ctrl+V, restores your
  old clipboard, and switches the input language of the focused window.
- Start-at-login uses the per-user `Run` registry key — no admin rights
  anywhere.
- Diagnostics land in `%LOCALAPPDATA%\relayout.log`.

## Windows-specific notes

- **No permission prompts** — unlike macOS, Windows needs no Accessibility
  grant for this.
- Keystrokes cannot be injected into windows running **as administrator**
  (Windows blocks that by design), so conversion won't work there.
- The default Ctrl+Alt+/ avoids AltGr collisions on layouts that use them;
  if some app owns your chosen combo, relayout falls back to the default and
  logs it.
