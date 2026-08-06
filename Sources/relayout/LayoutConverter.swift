import Carbon
import Foundation

/// A physical key press: hardware key code + whether Shift is held.
struct KeyStroke: Hashable {
    let keyCode: UInt16
    let shift: Bool
}

/// One enabled keyboard layout, with maps between key strokes and the
/// characters they produce, derived from the system's own layout data.
final class Layout {
    let inputSource: TISInputSource
    let inputSourceID: String
    let localizedName: String
    private(set) var charForStroke: [KeyStroke: Character] = [:]
    private(set) var strokeForChar: [Character: KeyStroke] = [:]

    init?(source: TISInputSource) {
        inputSource = source
        guard
            let id: String = Layout.property(source, kTISPropertyInputSourceID),
            let name: String = Layout.property(source, kTISPropertyLocalizedName),
            let layoutData: Data = Layout.property(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }

        inputSourceID = id
        localizedName = name

        let kbdType = UInt32(LMGetKbdType())
        layoutData.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            guard let layoutPtr = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return }
            for keyCode: UInt16 in 0..<128 {
                for shift in [false, true] {
                    // UCKeyTranslate expects (EventModifiers >> 8) & 0xFF; shiftKey is 0x200.
                    let modifiers: UInt32 = shift ? UInt32((shiftKey >> 8) & 0xFF) : 0
                    var deadKeyState: UInt32 = 0
                    var length = 0
                    var chars = [UniChar](repeating: 0, count: 4)
                    let status = UCKeyTranslate(
                        layoutPtr,
                        keyCode,
                        UInt16(kUCKeyActionDown),
                        modifiers,
                        kbdType,
                        UInt32(1 << kUCKeyTranslateNoDeadKeysBit),
                        &deadKeyState,
                        chars.count,
                        &length,
                        &chars
                    )
                    guard status == noErr, length == 1,
                          let scalar = UnicodeScalar(chars[0]),
                          scalar.value >= 0x20, scalar.value != 0x7F
                    else { continue }

                    let ch = Character(scalar)
                    let stroke = KeyStroke(keyCode: keyCode, shift: shift)
                    charForStroke[stroke] = ch
                    if strokeForChar[ch] == nil {
                        strokeForChar[ch] = stroke
                    }
                }
            }
        }

        if strokeForChar.isEmpty { return nil }
    }

    private static func property<T>(_ source: TISInputSource, _ key: CFString!) -> T? {
        guard let ptr = TISGetInputSourceProperty(source, key) else { return nil }
        let value = Unmanaged<AnyObject>.fromOpaque(ptr).takeUnretainedValue()
        if T.self == Data.self {
            return (value as? Data) as? T
        }
        return value as? T
    }
}

enum LayoutConverter {

    /// All keyboard layouts the user has enabled in System Settings, in the
    /// system's ordering. Input methods (e.g. Chinese, Japanese) have no
    /// static key map and are skipped.
    static func enabledLayouts() -> [Layout] {
        let filter = [kTISPropertyInputSourceType: kTISTypeKeyboardLayout] as CFDictionary
        guard let cfList = TISCreateInputSourceList(filter, false)?.takeRetainedValue() else {
            return []
        }
        let sources = cfList as! [TISInputSource]
        var layouts: [Layout] = []
        for source in sources {
            if let layout = Layout(source: source) {
                // Skip duplicates that map to an already-seen input source.
                if !layouts.contains(where: { $0.inputSourceID == layout.inputSourceID }) {
                    layouts.append(layout)
                }
            }
        }
        return layouts
    }

    struct Conversion {
        let text: String
        let target: Layout
    }

    /// Re-types `text` from the layout it appears to have been written in
    /// into the next enabled layout, cycling through the user's layouts.
    /// Returns nil when fewer than two layouts are enabled.
    static func convert(_ text: String) -> Conversion? {
        let layouts = enabledLayouts()
        guard layouts.count >= 2 else { return nil }

        let sourceIndex = bestSourceLayout(for: text, in: layouts)
        let source = layouts[sourceIndex]
        let target = layouts[(sourceIndex + 1) % layouts.count]

        var result = ""
        result.reserveCapacity(text.count)
        for ch in text {
            if let stroke = source.strokeForChar[ch],
               let mapped = target.charForStroke[stroke] {
                result.append(mapped)
            } else {
                result.append(ch)
            }
        }
        return Conversion(text: result, target: target)
    }

    /// Picks the layout whose key map covers the most characters of `text` —
    /// i.e. the layout the text was most plausibly typed in.
    private static func bestSourceLayout(for text: String, in layouts: [Layout]) -> Int {
        var bestIndex = 0
        var bestScore = -1
        for (index, layout) in layouts.enumerated() {
            var score = 0
            for ch in text where layout.strokeForChar[ch] != nil {
                score += 1
            }
            if score > bestScore {
                bestScore = score
                bestIndex = index
            }
        }
        return bestIndex
    }
}
