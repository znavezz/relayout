using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;

namespace Relayout;

/// A physical key press: hardware scan code + whether Shift is held.
/// Scan codes (not virtual keys) make conversion positional, matching the
/// macOS implementation — so QWERTY↔AZERTY etc. convert by key position.
readonly record struct KeyStroke(uint Scan, bool Shift);

/// One installed keyboard layout, with maps between key strokes and the
/// characters they produce, derived from the system's own layout data.
sealed class KeyboardLayout
{
    public IntPtr Hkl { get; }
    public string Name { get; }
    public Dictionary<KeyStroke, char> CharForStroke { get; } = new();
    public Dictionary<char, KeyStroke> StrokeForChar { get; } = new();

    // The typing-area scan codes: digit row, three letter rows with their
    // punctuation neighbors, backslash, backtick, and space.
    static readonly uint[] MappedScanCodes = BuildScanCodes();

    static uint[] BuildScanCodes()
    {
        var scans = new List<uint> { 0x29, 0x2B, 0x39 }; // ` \ space
        for (uint sc = 0x02; sc <= 0x0D; sc++) scans.Add(sc); // 1..0 - =
        for (uint sc = 0x10; sc <= 0x1B; sc++) scans.Add(sc); // q..p [ ]
        for (uint sc = 0x1E; sc <= 0x28; sc++) scans.Add(sc); // a..l ; '
        for (uint sc = 0x2C; sc <= 0x35; sc++) scans.Add(sc); // z..m , . /
        return scans.ToArray();
    }

    public KeyboardLayout(IntPtr hkl)
    {
        Hkl = hkl;
        Name = LayoutName(hkl);

        var state = new byte[256];
        var buffer = new StringBuilder(8);
        foreach (var scan in MappedScanCodes)
        {
            uint vk = Native.MapVirtualKeyEx(scan, Native.MAPVK_VSC_TO_VK_EX, hkl);
            if (vk == 0) continue;
            foreach (var shift in new[] { false, true })
            {
                Array.Clear(state);
                if (shift) state[0x10] = 0x80; // VK_SHIFT
                buffer.Clear();
                // 0x4: don't change kernel keyboard state (Win10 1607+), so
                // probing dead keys can't corrupt the user's typing.
                int rc = Native.ToUnicodeEx(vk, scan, state, buffer, buffer.Capacity, 0x4, hkl);
                if (rc != 1) continue; // dead key (<0), nothing (0), or multi-char
                char ch = buffer[0];
                if (ch < 0x20 || ch == 0x7F) continue;

                var stroke = new KeyStroke(scan, shift);
                CharForStroke[stroke] = ch;
                if (!StrokeForChar.ContainsKey(ch)) StrokeForChar[ch] = stroke;
            }
        }
    }

    static string LayoutName(IntPtr hkl)
    {
        try
        {
            int langId = (int)hkl & 0xFFFF;
            return CultureInfo.GetCultureInfo(langId).DisplayName;
        }
        catch
        {
            return $"0x{(long)hkl:X}";
        }
    }
}

sealed record Conversion(string Text, IntPtr TargetHkl, string TargetName);

static class LayoutConverter
{
    /// All keyboard layouts installed for this user, in system order.
    public static List<KeyboardLayout> InstalledLayouts()
    {
        int count = Native.GetKeyboardLayoutList(0, null);
        if (count <= 0) return new List<KeyboardLayout>();
        var hkls = new IntPtr[count];
        Native.GetKeyboardLayoutList(count, hkls);
        var layouts = new List<KeyboardLayout>();
        foreach (var hkl in hkls)
        {
            var layout = new KeyboardLayout(hkl);
            if (layout.StrokeForChar.Count > 0) layouts.Add(layout);
        }
        return layouts;
    }

    /// Re-types `text` from the layout it appears to have been written in
    /// into the next installed layout, cycling. Null when fewer than two
    /// layouts are installed.
    public static Conversion? Convert(string text) => ConvertWith(text, InstalledLayouts());

    /// Same conversion against an explicit layout list — lets tests exercise
    /// language pairs in isolation, regardless of what the machine has loaded.
    public static Conversion? ConvertWith(string text, List<KeyboardLayout> layouts)
    {
        if (layouts.Count < 2) return null;

        int sourceIndex = BestSourceLayout(text, layouts);
        var source = layouts[sourceIndex];
        var target = layouts[(sourceIndex + 1) % layouts.Count];

        var result = new StringBuilder(text.Length);
        foreach (char ch in text)
        {
            if (source.StrokeForChar.TryGetValue(ch, out var stroke)
                && target.CharForStroke.TryGetValue(stroke, out var mapped))
            {
                result.Append(mapped);
            }
            else
            {
                result.Append(ch);
            }
        }
        return new Conversion(result.ToString(), target.Hkl, target.Name);
    }

    /// The layout whose key map covers the most characters of `text` —
    /// i.e. the layout the text was most plausibly typed in.
    static int BestSourceLayout(string text, List<KeyboardLayout> layouts)
    {
        int bestIndex = 0, bestScore = -1;
        for (int i = 0; i < layouts.Count; i++)
        {
            int score = 0;
            foreach (char ch in text)
                if (layouts[i].StrokeForChar.ContainsKey(ch)) score++;
            if (score > bestScore) { bestScore = score; bestIndex = i; }
        }
        return bestIndex;
    }
}
