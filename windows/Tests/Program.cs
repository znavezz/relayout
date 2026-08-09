using Relayout;

// Headless conversion tests that run on a real Windows machine (CI).
// Each language pair is loaded and tested in isolation via ConvertWith,
// so results don't depend on what the machine happens to have installed.

const string English = "00000409";
const string Hebrew = "0000040D";
const string Russian = "00000419";
const string Greek = "00000408";
const string French = "0000040C";

int failures = 0;

// Hebrew — the canonical examples from the README.
failures += TestPair(English, Hebrew, "akuo", "שלום");
failures += TestPair(English, Hebrew, "שלום", "akuo");
failures += TestPair(English, Hebrew, "buuv", "נווה");
failures += TestPair(English, Hebrew, "akuo veo!", "שלום הקם!");

// Digits and unmapped characters pass through; emoji (surrogate pairs) survive.
failures += TestPair(English, Hebrew, "akuo 123", "שלום 123");
failures += TestPair(English, Hebrew, "akuo 😀 tt", "שלום 😀 אא");

// Russian ЙЦУКЕН — the classic wrong-layout "привет".
failures += TestPair(English, Russian, "ghbdtn", "привет");
failures += TestPair(English, Russian, "привет", "ghbdtn");

// Greek.
failures += TestPair(English, Greek, "geia", "γεια");
failures += TestPair(English, Greek, "γεια", "geia");

// French AZERTY — positional conversion (scan codes, not letter names).
failures += TestPair(English, French, "qwerty", "azerty");

Console.WriteLine(failures == 0 ? "ALL PASS" : $"{failures} FAILURES");
return failures == 0 ? 0 : 1;

static int TestPair(string sourceKlid, string targetKlid, string input, string expected)
{
    var layouts = new List<KeyboardLayout>
    {
        new(Native.LoadKeyboardLayout(sourceKlid, 0)),
        new(Native.LoadKeyboardLayout(targetKlid, 0)),
    };
    var conversion = LayoutConverter.ConvertWith(input, layouts);
    if (conversion?.Text == expected)
    {
        Console.WriteLine($"PASS [{layouts[0].Name} ⇄ {layouts[1].Name}]: \"{input}\" -> \"{conversion.Text}\"");
        return 0;
    }
    Console.WriteLine($"FAIL [{layouts[0].Name} ⇄ {layouts[1].Name}]: \"{input}\" -> \"{conversion?.Text ?? "<null>"}\" (expected \"{expected}\")");
    return 1;
}
