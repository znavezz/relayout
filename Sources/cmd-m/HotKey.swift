import AppKit
import Carbon
import Foundation

/// A parsed global hotkey: modifiers + a key ("cmd+m"), a modifier-only chord
/// involving the fn/Globe key ("cmd+fn"), or a left+right pair of the same
/// modifier ("cmd+cmd", "shift+shift") for keyboards without a visible fn key.
struct HotKeySpec {
    enum Trigger {
        case key(keyCode: UInt32, carbonModifiers: UInt32)
        case modifierChord(NSEvent.ModifierFlags)
        case bothKeys(BothKeys)
    }

    /// Left+right pair of one modifier, told apart via the device-dependent
    /// bits in CGEventFlags (IOLLEvent.h NX_DEVICE*KEYMASK).
    enum BothKeys {
        case command  // 0x08 | 0x10
        case shift    // 0x02 | 0x04

        var deviceBits: UInt64 {
            switch self {
            case .command: return 0x08 | 0x10
            case .shift: return 0x02 | 0x04
            }
        }

        var flag: CGEventFlags {
            switch self {
            case .command: return .maskCommand
            case .shift: return .maskShift
            }
        }
    }

    let trigger: Trigger
    let display: String

    /// Parses strings like "cmd+shift+m", "cmd+fn", "cmd+cmd", "shift+shift".
    static func parse(_ string: String) -> HotKeySpec? {
        let normalized = string.lowercased()
        let tokens = normalized.split(separator: "+").map(String.init)
        guard tokens.count >= 2 else { return nil }

        switch tokens {
        case ["cmd", "cmd"], ["command", "command"]:
            return HotKeySpec(trigger: .bothKeys(.command), display: "cmd+cmd")
        case ["shift", "shift"]:
            return HotKeySpec(trigger: .bothKeys(.shift), display: "shift+shift")
        default:
            break
        }

        if tokens.contains("fn") || tokens.contains("globe") {
            var flags: NSEvent.ModifierFlags = []
            for token in tokens {
                switch token {
                case "cmd", "command": flags.insert(.command)
                case "ctrl", "control": flags.insert(.control)
                case "alt", "opt", "option": flags.insert(.option)
                case "shift": flags.insert(.shift)
                case "fn", "globe": flags.insert(.function)
                default: return nil // fn chords cannot include a regular key
                }
            }
            return HotKeySpec(trigger: .modifierChord(flags), display: normalized)
        }

        guard let keyToken = tokens.last else { return nil }
        var modifiers: UInt32 = 0
        for token in tokens.dropLast() {
            switch token {
            case "cmd", "command": modifiers |= UInt32(cmdKey)
            case "ctrl", "control": modifiers |= UInt32(controlKey)
            case "alt", "opt", "option": modifiers |= UInt32(optionKey)
            case "shift": modifiers |= UInt32(shiftKey)
            default: return nil
            }
        }
        guard modifiers != 0, let keyCode = keyCodes[keyToken] else { return nil }
        return HotKeySpec(
            trigger: .key(keyCode: keyCode, carbonModifiers: modifiers),
            display: normalized
        )
    }

    private static let keyCodes: [String: UInt32] = [
        "a": UInt32(kVK_ANSI_A), "b": UInt32(kVK_ANSI_B), "c": UInt32(kVK_ANSI_C),
        "d": UInt32(kVK_ANSI_D), "e": UInt32(kVK_ANSI_E), "f": UInt32(kVK_ANSI_F),
        "g": UInt32(kVK_ANSI_G), "h": UInt32(kVK_ANSI_H), "i": UInt32(kVK_ANSI_I),
        "j": UInt32(kVK_ANSI_J), "k": UInt32(kVK_ANSI_K), "l": UInt32(kVK_ANSI_L),
        "m": UInt32(kVK_ANSI_M), "n": UInt32(kVK_ANSI_N), "o": UInt32(kVK_ANSI_O),
        "p": UInt32(kVK_ANSI_P), "q": UInt32(kVK_ANSI_Q), "r": UInt32(kVK_ANSI_R),
        "s": UInt32(kVK_ANSI_S), "t": UInt32(kVK_ANSI_T), "u": UInt32(kVK_ANSI_U),
        "v": UInt32(kVK_ANSI_V), "w": UInt32(kVK_ANSI_W), "x": UInt32(kVK_ANSI_X),
        "y": UInt32(kVK_ANSI_Y), "z": UInt32(kVK_ANSI_Z),
        "0": UInt32(kVK_ANSI_0), "1": UInt32(kVK_ANSI_1), "2": UInt32(kVK_ANSI_2),
        "3": UInt32(kVK_ANSI_3), "4": UInt32(kVK_ANSI_4), "5": UInt32(kVK_ANSI_5),
        "6": UInt32(kVK_ANSI_6), "7": UInt32(kVK_ANSI_7), "8": UInt32(kVK_ANSI_8),
        "9": UInt32(kVK_ANSI_9),
        "space": UInt32(kVK_Space), "tab": UInt32(kVK_Tab),
        "f1": UInt32(kVK_F1), "f2": UInt32(kVK_F2), "f3": UInt32(kVK_F3),
        "f4": UInt32(kVK_F4), "f5": UInt32(kVK_F5), "f6": UInt32(kVK_F6),
        "f7": UInt32(kVK_F7), "f8": UInt32(kVK_F8), "f9": UInt32(kVK_F9),
        "f10": UInt32(kVK_F10), "f11": UInt32(kVK_F11), "f12": UInt32(kVK_F12),
    ]
}

/// Registers one or more system-wide hotkeys sharing a single action.
/// Regular key combos use the Carbon hotkey API; modifier chords are detected
/// with a CGEvent tap, which works under the Accessibility permission the app
/// already requires (NSEvent global keyboard monitors would silently need the
/// separate Input Monitoring permission instead).
final class HotKeyCenter {
    private var hotKeyRefs: [EventHotKeyRef] = []
    private var eventHandlerRef: EventHandlerRef?
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var chordMatchers: [(CGEvent) -> Bool] = []
    private var chordFired = false
    private let handler: () -> Void

    private static let relevantFlags: CGEventFlags = [
        .maskCommand, .maskControl, .maskAlternate, .maskShift, .maskSecondaryFn,
    ]

    init(specs: [HotKeySpec], handler: @escaping () -> Void) {
        self.handler = handler

        for spec in specs {
            switch spec.trigger {
            case let .key(keyCode, carbonModifiers):
                registerCarbonHotKey(keyCode: keyCode, carbonModifiers: carbonModifiers)

            case let .modifierChord(chord):
                var flags: CGEventFlags = []
                if chord.contains(.command) { flags.insert(.maskCommand) }
                if chord.contains(.control) { flags.insert(.maskControl) }
                if chord.contains(.option) { flags.insert(.maskAlternate) }
                if chord.contains(.shift) { flags.insert(.maskShift) }
                if chord.contains(.function) { flags.insert(.maskSecondaryFn) }
                chordMatchers.append { event in
                    event.flags.intersection(HotKeyCenter.relevantFlags) == flags
                }

            case let .bothKeys(pair):
                chordMatchers.append { event in
                    event.flags.intersection(HotKeyCenter.relevantFlags) == pair.flag
                        && event.flags.rawValue & pair.deviceBits == pair.deviceBits
                }
            }
        }

        if !chordMatchers.isEmpty {
            installEventTap()
        }
    }

    private func installEventTap() {
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, userInfo in
                if let userInfo {
                    let center = Unmanaged<HotKeyCenter>.fromOpaque(userInfo).takeUnretainedValue()
                    center.handleTapEvent(type: type, event: event)
                }
                return Unmanaged.passUnretained(event)
            },
            userInfo: selfPtr
        )
        guard let eventTap else {
            Log.write("chord: event tap creation failed — Accessibility permission missing or stale")
            return
        }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        CGEvent.tapEnable(tap: eventTap, enable: true)
        Log.write("chord: event tap installed (\(chordMatchers.count) chord(s))")
    }

    private func handleTapEvent(type: CGEventType, event: CGEvent) {
        // macOS disables taps it considers unresponsive; re-enable and move on.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return
        }
        if chordMatchers.contains(where: { $0(event) }) {
            if !chordFired {
                chordFired = true
                Log.write("chord: fired")
                DispatchQueue.main.async { self.handler() }
            }
        } else {
            chordFired = false
        }
    }

    private func registerCarbonHotKey(keyCode: UInt32, carbonModifiers: UInt32) {
        if eventHandlerRef == nil {
            var eventType = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            let selfPtr = Unmanaged.passUnretained(self).toOpaque()
            InstallEventHandler(
                GetEventDispatcherTarget(),
                { _, _, userData -> OSStatus in
                    guard let userData else { return OSStatus(eventNotHandledErr) }
                    let center = Unmanaged<HotKeyCenter>.fromOpaque(userData).takeUnretainedValue()
                    center.handler()
                    return noErr
                },
                1,
                &eventType,
                selfPtr,
                &eventHandlerRef
            )
        }

        let hotKeyID = EventHotKeyID(
            signature: OSType(0x434D_444D), // 'CMDM'
            id: UInt32(hotKeyRefs.count + 1)
        )
        var ref: EventHotKeyRef?
        RegisterEventHotKey(
            keyCode,
            carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &ref
        )
        if let ref {
            hotKeyRefs.append(ref)
        }
    }

    deinit {
        for ref in hotKeyRefs { UnregisterEventHotKey(ref) }
        if let eventHandlerRef { RemoveEventHandler(eventHandlerRef) }
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
            CFMachPortInvalidate(eventTap)
        }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
    }
}
