using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;

namespace Relayout;

/// A physical key press: virtual-key code + whether Shift is held.
readonly record struct KeyStroke(uint Vk, bool Shift);

/// One installed keyboard layout, with maps between key strokes and the
/// characters they produce, derived from the system's own layout data.
sealed class KeyboardLayout
{
    public IntPtr Hkl { get; }
    public string Name { get; }
    public Dictionary<KeyStroke, char> CharForStroke { get; } = new();
    public Dictionary<char, KeyStroke> StrokeForChar { get; } = new();

    // Letters, digits, space, and the OEM punctuation keys — every key that
    // can produce a layout-specific character.
    static readonly uint[] MappedVks = BuildMappedVks();

    static uint[] BuildMappedVks()
    {
        var vks = new List<uint> { 0x20 }; // space
        for (uint vk = 0x30; vk <= 0x39; vk++) vks.Add(vk); // 0-9
        for (uint vk = 0x41; vk <= 0x5A; vk++) vks.Add(vk); // A-Z
        for (uint vk = 0xBA; vk <= 0xC0; vk++) vks.Add(vk); // ;=,-./`
        for (uint vk = 0xDB; vk <= 0xDE; vk++) vks.Add(vk); // [\]'
        return vks.ToArray();
    }

    public KeyboardLayout(IntPtr hkl)
    {
        Hkl = hkl;
        Name = LayoutName(hkl);

        var state = new byte[256];
        var buffer = new StringBuilder(8);
        foreach (var vk in MappedVks)
        {
            foreach (var shift in new[] { false, true })
            {
                Array.Clear(state);
                if (shift) state[0x10] = 0x80; // VK_SHIFT
                buffer.Clear();
                uint scan = Native.MapVirtualKeyEx(vk, Native.MAPVK_VK_TO_VSC, hkl);
                // 0x4: don't change kernel keyboard state (Win10 1607+), so
                // probing dead keys can't corrupt the user's typing.
                int rc = Native.ToUnicodeEx(vk, scan, state, buffer, buffer.Capacity, 0x4, hkl);
                if (rc != 1) continue; // dead key (<0), nothing (0), or multi-char
                char ch = buffer[0];
                if (ch < 0x20 || ch == 0x7F) continue;

                var stroke = new KeyStroke(vk, shift);
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
    public static Conversion? Convert(string text)
    {
        var layouts = InstalledLayouts();
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
