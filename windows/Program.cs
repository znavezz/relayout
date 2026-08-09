using Microsoft.Win32;

namespace Relayout;

static class Program
{
    [STAThread]
    static void Main()
    {
        using var singleInstance = new Mutex(true, @"Local\relayout", out bool isFirst);
        if (!isFirst)
        {
            Log.Write("another relayout instance is already running — exiting");
            return;
        }

        ApplicationConfiguration.Initialize();
        Application.Run(new TrayApp());
    }
}

sealed class TrayApp : ApplicationContext
{
    const string DefaultCombo = "alt+/";
    const string SettingsKeyPath = @"Software\relayout";
    const string RunKeyPath = @"Software\Microsoft\Windows\CurrentVersion\Run";

    static readonly (string Title, string Combo)[] Presets =
    {
        ("Alt+/  (default)", "alt+/"),
        ("Ctrl+Alt+/", "ctrl+alt+/"),
        ("Ctrl+Alt+K", "ctrl+alt+k"),
        ("Pause key", "pause"),
    };

    readonly NotifyIcon trayIcon;
    readonly HotKeyManager hotKeys = new();
    string currentCombo = DefaultCombo;

    public TrayApp()
    {
        hotKeys.Pressed += SelectionConverter.ConvertSelection;
        ApplyHotKey(LoadSetting("hotkey") ?? DefaultCombo);
        EnableAutostartOnFirstRun();

        trayIcon = new NotifyIcon
        {
            Icon = System.Drawing.SystemIcons.Application,
            Visible = true,
            ContextMenuStrip = new ContextMenuStrip(),
        };
        trayIcon.ContextMenuStrip.Opening += (_, _) => RebuildMenu();
        RebuildMenu();
    }

    void RebuildMenu()
    {
        var menu = trayIcon.ContextMenuStrip!;
        menu.Items.Clear();

        menu.Items.Add($"Convert Selection ({currentCombo})", null,
            (_, _) => SelectionConverter.ConvertSelection());

        var shortcutMenu = new ToolStripMenuItem("Shortcut");
        foreach (var (title, combo) in Presets)
        {
            var entry = new ToolStripMenuItem(title) { Checked = combo == currentCombo };
            entry.Click += (_, _) => { SaveSetting("hotkey", combo); ApplyHotKey(combo); };
            shortcutMenu.DropDownItems.Add(entry);
        }
        if (Array.TrueForAll(Presets, p => p.Combo != currentCombo))
        {
            shortcutMenu.DropDownItems.Add(
                new ToolStripMenuItem($"Custom: {currentCombo}") { Checked = true, Enabled = false });
        }
        shortcutMenu.DropDownItems.Add(new ToolStripSeparator());
        shortcutMenu.DropDownItems.Add(new ToolStripMenuItem("Custom…", null,
            (_, _) => ChooseCustomShortcut()));
        menu.Items.Add(shortcutMenu);

        var autostart = new ToolStripMenuItem("Start with Windows") { Checked = IsAutostartEnabled() };
        autostart.Click += (_, _) => SetAutostart(!IsAutostartEnabled());
        menu.Items.Add(autostart);

        menu.Items.Add(new ToolStripSeparator());
        menu.Items.Add("Quit relayout", null, (_, _) => Quit());
    }

    void ApplyHotKey(string combo)
    {
        var spec = HotKeySpec.Parse(combo) ?? HotKeySpec.Parse(DefaultCombo)!;
        currentCombo = spec.Display;
        if (!hotKeys.Apply(spec) && spec.Display != DefaultCombo)
        {
            // Combo owned by another app — fall back so the tool still works.
            ApplyHotKey(DefaultCombo);
        }
        if (trayIcon is not null) trayIcon.Text = $"relayout — convert selection ({currentCombo})";
    }

    void ChooseCustomShortcut()
    {
        using var dialog = new Form
        {
            Text = "relayout — Custom Shortcut",
            FormBorderStyle = FormBorderStyle.FixedDialog,
            StartPosition = FormStartPosition.CenterScreen,
            MinimizeBox = false, MaximizeBox = false,
            ClientSize = new System.Drawing.Size(320, 110),
            TopMost = true,
        };
        var hint = new Label
        {
            Text = "Modifiers ctrl / alt / shift / win joined with \"+\", then a key.\nExamples: ctrl+alt+k · ctrl+shift+9 · pause",
            AutoSize = false, Dock = DockStyle.Top, Height = 40,
        };
        var field = new TextBox { Dock = DockStyle.Top, Text = currentCombo };
        var ok = new Button { Text = "Set", DialogResult = DialogResult.OK, Dock = DockStyle.Bottom };
        dialog.Controls.AddRange(new Control[] { ok, field, hint });
        dialog.AcceptButton = ok;

        if (dialog.ShowDialog() != DialogResult.OK) return;
        var spec = HotKeySpec.Parse(field.Text);
        if (spec is null)
        {
            MessageBox.Show(
                $"Couldn't understand \"{field.Text}\". Use forms like ctrl+alt+k.",
                "relayout", MessageBoxButtons.OK, MessageBoxIcon.Warning);
            return;
        }
        SaveSetting("hotkey", spec.Display);
        ApplyHotKey(spec.Display);
    }

    // -- Autostart via the per-user Run registry key (no admin rights). --

    void EnableAutostartOnFirstRun()
    {
        if (LoadSetting("installed") is null)
        {
            SetAutostart(true);
            SaveSetting("installed", "1");
        }
    }

    static bool IsAutostartEnabled()
    {
        using var key = Registry.CurrentUser.OpenSubKey(RunKeyPath);
        return key?.GetValue("relayout") is not null;
    }

    static void SetAutostart(bool enabled)
    {
        using var key = Registry.CurrentUser.CreateSubKey(RunKeyPath);
        if (enabled) key.SetValue("relayout", $"\"{Application.ExecutablePath}\"");
        else key.DeleteValue("relayout", throwOnMissingValue: false);
    }

    // -- Settings in HKCU\Software\relayout. --

    static string? LoadSetting(string name)
    {
        using var key = Registry.CurrentUser.OpenSubKey(SettingsKeyPath);
        return key?.GetValue(name) as string;
    }

    static void SaveSetting(string name, string value)
    {
        using var key = Registry.CurrentUser.CreateSubKey(SettingsKeyPath);
        key.SetValue(name, value);
    }

    void Quit()
    {
        trayIcon.Visible = false;
        hotKeys.Dispose();
        Application.Exit();
    }
}
