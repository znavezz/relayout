using Relayout;

// Headless conversion tests that run on a real Windows machine (CI):
// load the US and Hebrew layouts explicitly, then verify the converter
// against the canonical examples from the README.

Native.LoadKeyboardLayout("00000409", 0); // English (US)
Native.LoadKeyboardLayout("0000040D", 0); // Hebrew

var layouts = LayoutConverter.InstalledLayouts();
Console.WriteLine($"layouts: {string.Join(", ", layouts.Select(l => l.Name))}");
if (layouts.Count < 2)
{
    Console.WriteLine("FAIL: fewer than two layouts available");
    return 1;
}

int failures = 0;
failures += Expect("akuo", "שלום");
failures += Expect("שלום", "akuo");
failures += Expect("buuv", "נווה");
failures += Expect("akuo veo!", "שלום הקם!"); // matches the macOS implementation

return failures == 0 ? 0 : 1;

static int Expect(string input, string expected)
{
    var conversion = LayoutConverter.Convert(input);
    if (conversion?.Text == expected)
    {
        Console.WriteLine($"PASS: \"{input}\" -> \"{conversion.Text}\"");
        return 0;
    }
    Console.WriteLine($"FAIL: \"{input}\" -> \"{conversion?.Text ?? "<null>"}\" (expected \"{expected}\")");
    return 1;
}
