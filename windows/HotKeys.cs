namespace Relayout;

/// A parsed global hotkey, e.g. "ctrl+alt+/" or "pause".
sealed record HotKeySpec(uint Modifiers, uint Vk, string Display)
{
    /// Parses strings like "ctrl+alt+k", "ctrl+shift+9", "pause".
    /// Modifier names: ctrl, alt, shift, win. The last token is the key.
    public static HotKeySpec? Parse(string text)
    {
        var normalized = text.Trim().ToLowerInvariant();
        var tokens = normalized.Split('+', StringSplitOptions.RemoveEmptyEntries);
        if (tokens.Length == 0) return null;

        uint modifiers = 0;
        for (int i = 0; i < tokens.Length - 1; i++)
        {
            switch (tokens[i])
            {
                case "ctrl" or "control": modifiers |= Native.MOD_CONTROL; break;
                case "alt": modifiers |= Native.MOD_ALT; break;
                case "shift": modifiers |= Native.MOD_SHIFT; break;
                case "win": modifiers |= Native.MOD_WIN; break;
                default: return null;
            }
        }

        var keyToken = tokens[^1];
        if (keyToken == "?") // shift+/ on the physical keyboard
        {
            keyToken = "/";
            modifiers |= Native.MOD_SHIFT;
        }
        if (!VkByName.TryGetValue(keyToken, out var vk)) return null;
        // A bare key is only allowed for keys that can't collide with typing.
        if (modifiers == 0 && keyToken != "pause") return null;
        return new HotKeySpec(modifiers, vk, normalized);
    }

    static readonly Dictionary<string, uint> VkByName = BuildVkByName();

    static Dictionary<string, uint> BuildVkByName()
    {
        var map = new Dictionary<string, uint>
        {
            ["space"] = 0x20, ["tab"] = 0x09, ["pause"] = 0x13,
            [";"] = 0xBA, ["="] = 0xBB, [","] = 0xBC, ["-"] = 0xBD,
            ["."] = 0xBE, ["/"] = 0xBF, ["`"] = 0xC0,
            ["["] = 0xDB, ["\\"] = 0xDC, ["]"] = 0xDD, ["'"] = 0xDE,
        };
        for (char c = 'a'; c <= 'z'; c++) map[c.ToString()] = (uint)char.ToUpperInvariant(c);
        for (char c = '0'; c <= '9'; c++) map[c.ToString()] = c;
        for (int f = 1; f <= 12; f++) map[$"f{f}"] = (uint)(0x70 + f - 1);
        return map;
    }
}

/// Registers a system-wide hotkey and raises Pressed when it fires.
sealed class HotKeyManager : NativeWindow, IDisposable
{
    const int HotKeyId = 1;
    public event Action? Pressed;
    bool registered;

    public HotKeyManager()
    {
        CreateHandle(new CreateParams());
    }

    /// Replaces the current registration; returns false if Windows refused
    /// the combo (usually because another app owns it).
    public bool Apply(HotKeySpec spec)
    {
        if (registered) Native.UnregisterHotKey(Handle, HotKeyId);
        registered = Native.RegisterHotKey(
            Handle, HotKeyId, spec.Modifiers | Native.MOD_NOREPEAT, spec.Vk);
        Log.Write(registered
            ? $"hotkey: registered {spec.Display}"
            : $"hotkey: Windows refused {spec.Display} (taken by another app?)");
        return registered;
    }

    protected override void WndProc(ref Message m)
    {
        if (m.Msg == Native.WM_HOTKEY && (int)m.WParam == HotKeyId)
        {
            Pressed?.Invoke();
        }
        base.WndProc(ref m);
    }

    public void Dispose()
    {
        if (registered) Native.UnregisterHotKey(Handle, HotKeyId);
        DestroyHandle();
    }
}
