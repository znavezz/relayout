# relayout for Windows

The Windows port of [relayout](../README.md): select text typed in the wrong
keyboard layout, press the hotkey (default **Alt+/** — hold Alt, tap the `?`
key), and it's retyped in your next installed layout — and the window's input
language switches to match. Same algorithm as the macOS version, same
`akuo ⇄ שלום` behavior.

**Status: beta — needs testing on real Windows machines.** The converter
logic is a direct port of the proven macOS implementation, but the tray app
has not been field-tested yet. Reports welcome.

## Install & run

There is no prebuilt download yet (that comes once the beta is field-tested),
so for now it runs from source. Full steps, from a blank Windows machine:

1. **Install the [.NET SDK](https://dotnet.microsoft.com/download)** (6.0 or
   newer) — Microsoft's free build tool.
2. **Get the code** — either:
   ```powershell
   git clone https://github.com/znavezz/relayout.git
   ```
   or, without git: on the [repository page](https://github.com/znavezz/relayout)
   click **Code → Download ZIP** and unzip it.
3. **Build and start it** from wherever the code landed:
   ```powershell
   cd relayout\windows
   dotnet run -c Release
   ```

A tray icon appears; the default hotkey **Alt+/** is live immediately —
no permission prompts on Windows. "Start with Windows" is enabled on first
run (toggle it in the tray menu).

To produce a standalone `relayout.exe` (runs on machines without .NET):

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
- The default Alt+/ is registered globally, so it wins over apps that use
  the combo locally; if Windows refuses your chosen combo (another global
  hotkey owns it), relayout falls back to the default and logs it.
