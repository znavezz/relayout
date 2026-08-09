using System.Media;

namespace Relayout;

/// Converts the current selection in whatever window is focused:
/// simulated Ctrl+C → convert between layouts → simulated Ctrl+V,
/// then switches the focused window's input language to match.
/// Preserves the previous (plain-text) clipboard contents.
static class SelectionConverter
{
    static bool busy;

    public static void ConvertSelection()
    {
        if (busy) return;
        busy = true;
        try
        {
            Run();
        }
        catch (Exception error)
        {
            Log.Write($"convert: unexpected error: {error.Message}");
        }
        finally
        {
            busy = false;
        }
    }

    static void Run()
    {
        string? saved = GetClipboardText();
        uint sequenceBefore = Native.GetClipboardSequenceNumber();

        // The user is still physically holding the hotkey's modifiers;
        // release them synthetically so our Ctrl+C isn't Ctrl+Alt+C.
        Native.SendKeyUp(Native.VK_MENU);
        Native.SendKeyUp(Native.VK_SHIFT);
        Native.SendKeyUp(Native.VK_LWIN);
        Native.SendKeyUp(Native.VK_RWIN);

        Native.SendCombo(Native.VK_CONTROL, (ushort)'C');

        string? selected = null;
        for (int i = 0; i < 20; i++)
        {
            Thread.Sleep(40);
            if (Native.GetClipboardSequenceNumber() != sequenceBefore)
            {
                selected = GetClipboardText();
                break;
            }
        }
        if (string.IsNullOrEmpty(selected))
        {
            Log.Write("convert: copy produced no text (no selection, or the app blocked it)");
            Fail(saved);
            return;
        }

        var conversion = LayoutConverter.Convert(selected);
        if (conversion is null || conversion.Text == selected)
        {
            Log.Write($"convert: nothing to change ({selected.Length} chars, or <2 layouts installed)");
            Fail(saved);
            return;
        }

        SetClipboardText(conversion.Text);
        Native.SendCombo(Native.VK_CONTROL, (ushort)'V');
        Thread.Sleep(150);

        // Switch the focused window's input language to the target layout,
        // so continued typing comes out in the right language.
        Native.PostMessage(
            Native.GetForegroundWindow(),
            Native.WM_INPUTLANGCHANGEREQUEST,
            IntPtr.Zero,
            conversion.TargetHkl);

        Log.Write($"convert: {selected.Length} chars -> {conversion.TargetName}");

        // Give the focused app time to read the pasteboard before restoring.
        Thread.Sleep(250);
        Restore(saved);
    }

    static void Fail(string? saved)
    {
        SystemSounds.Beep.Play();
        Restore(saved);
    }

    static void Restore(string? saved)
    {
        if (saved is not null) SetClipboardText(saved);
    }

    static string? GetClipboardText()
    {
        try
        {
            return Clipboard.ContainsText() ? Clipboard.GetText() : null;
        }
        catch
        {
            return null; // clipboard briefly locked by another process
        }
    }

    static void SetClipboardText(string text)
    {
        for (int attempt = 0; attempt < 3; attempt++)
        {
            try
            {
                Clipboard.SetDataObject(text, copy: true);
                return;
            }
            catch
            {
                Thread.Sleep(50);
            }
        }
        Log.Write("convert: could not write the clipboard");
    }
}
