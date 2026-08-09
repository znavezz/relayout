namespace Relayout;

/// Minimal append-only log at %LOCALAPPDATA%\relayout.log, for diagnosing
/// hotkey and conversion issues that have no visible error surface.
static class Log
{
    static readonly string Path = System.IO.Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
        "relayout.log");

    public static void Write(string message)
    {
        try
        {
            File.AppendAllText(Path, $"{DateTime.Now:yyyy-MM-dd HH:mm:ss} {message}{Environment.NewLine}");
        }
        catch
        {
            // Logging must never take the app down.
        }
    }
}
