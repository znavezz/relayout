import AppKit
import Carbon

/// Converts the current selection in whatever app is frontmost:
/// simulated ⌘C → convert between layouts → simulated ⌘V,
/// preserving the previous (plain-text) clipboard contents.
final class SelectionConverter {
    private let pasteboard = NSPasteboard.general
    private var busy = false

    func convertSelection() {
        guard !busy else { return }
        busy = true

        let savedText = pasteboard.string(forType: .string)
        let changeCountBeforeCopy = pasteboard.changeCount

        postKeyCombo(keyCode: CGKeyCode(kVK_ANSI_C), flags: .maskCommand)

        waitForPasteboardChange(from: changeCountBeforeCopy, timeout: 0.8) { [weak self] changed in
            guard let self else { return }
            defer { self.busy = false }

            guard changed,
                  let selected = self.pasteboard.string(forType: .string),
                  !selected.isEmpty
            else {
                Log.write("convert: copy produced no text (no selection, non-text selection, or ⌘C blocked)")
                NSSound.beep()
                self.restore(savedText)
                return
            }

            guard let conversion = LayoutConverter.convert(selected), conversion.text != selected else {
                Log.write("convert: nothing to change (\(selected.count) chars, or <2 layouts enabled)")
                NSSound.beep()
                self.restore(savedText)
                return
            }
            Log.write("convert: \(selected.count) chars → \(conversion.target.localizedName)")

            self.pasteboard.clearContents()
            self.pasteboard.setString(conversion.text, forType: .string)
            self.postKeyCombo(keyCode: CGKeyCode(kVK_ANSI_V), flags: .maskCommand)

            // Switch the active input source to the layout the text now uses,
            // so continued typing comes out in the right language.
            TISSelectInputSource(conversion.target.inputSource)

            // Give the frontmost app time to read the pasteboard before restoring it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                self.restore(savedText)
            }
        }
    }

    private func restore(_ text: String?) {
        pasteboard.clearContents()
        if let text {
            pasteboard.setString(text, forType: .string)
        }
    }

    private func postKeyCombo(keyCode: CGKeyCode, flags: CGEventFlags) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }

    private func waitForPasteboardChange(
        from changeCount: Int,
        timeout: TimeInterval,
        completion: @escaping (Bool) -> Void
    ) {
        let deadline = Date().addingTimeInterval(timeout)
        func poll() {
            if pasteboard.changeCount != changeCount {
                completion(true)
            } else if Date() >= deadline {
                completion(false)
            } else {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.03, execute: poll)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: poll)
    }
}
