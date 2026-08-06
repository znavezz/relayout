import AppKit
import Carbon
import Foundation

// MARK: - Command line interface

let arguments = Array(CommandLine.arguments.dropFirst())

func printUsage() {
    print("""
    cmd-m — retype selected text in your next keyboard layout

    Usage:
      cmd-m                     Run in the menu bar (default hotkey: cmd+m)
      cmd-m --hotkey <combo>    Run with a custom hotkey, e.g. --hotkey ctrl+alt+m
                                or a fn/Globe chord, e.g. --hotkey cmd+fn
      cmd-m --no-menubar        Run without a menu bar icon (pure background agent)
      cmd-m --convert [text]    Convert text and print it; reads stdin if no text given
      cmd-m --switch --convert  Also switch the active layout (used by the Quick Action)
      cmd-m --layouts           List the enabled keyboard layouts cmd-m sees
      cmd-m --help              Show this help

    Note: --switch must come before --convert; everything after --convert is text.
    """)
}

var cliHotKeySpec: HotKeySpec?
var showMenuBarItem = true
var switchLayoutAfterConvert = false

var index = 0
while index < arguments.count {
    let argument = arguments[index]
    switch argument {
    case "--help", "-h":
        printUsage()
        exit(0)

    case "--layouts":
        let layouts = LayoutConverter.enabledLayouts()
        if layouts.isEmpty {
            print("No keyboard layouts found.")
        }
        for layout in layouts {
            print("\(layout.localizedName)  (\(layout.inputSourceID))")
        }
        exit(0)

    case "--switch":
        switchLayoutAfterConvert = true

    case "--no-menubar":
        showMenuBarItem = false

    case "--convert":
        let rest = arguments[(index + 1)...]
        let fromStdin = rest.isEmpty
        let text: String
        if fromStdin {
            let data = FileHandle.standardInput.readDataToEndOfFile()
            text = String(data: data, encoding: .utf8) ?? ""
        } else {
            text = rest.joined(separator: " ")
        }
        if text.isEmpty { exit(0) }
        guard let conversion = LayoutConverter.convert(text) else {
            FileHandle.standardError.write(Data(
                "Need at least two keyboard layouts enabled in System Settings → Keyboard → Input Sources.\n".utf8))
            exit(1)
        }
        if fromStdin {
            // Byte-exact output: the Quick Action pastes this over the selection,
            // so no trailing newline may be added.
            FileHandle.standardOutput.write(Data(conversion.text.utf8))
        } else {
            print(conversion.text)
        }
        if switchLayoutAfterConvert {
            TISSelectInputSource(conversion.target.inputSource)
        }
        exit(0)

    case "--hotkey":
        guard index + 1 < arguments.count, let spec = HotKeySpec.parse(arguments[index + 1]) else {
            FileHandle.standardError.write(Data(
                "Invalid hotkey. Examples: --hotkey cmd+shift+m, --hotkey cmd+fn\n".utf8))
            exit(1)
        }
        cliHotKeySpec = spec
        index += 1

    default:
        FileHandle.standardError.write(Data("Unknown argument: \(argument)\n".utf8))
        printUsage()
        exit(1)
    }
    index += 1
}

// MARK: - Menu bar app

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    /// Hotkey from the command line; overrides the saved choice when present.
    private let cliSpec: HotKeySpec?
    private let showMenuBarItem: Bool
    private let converter = SelectionConverter()
    private var hotKeyCenter: HotKeyCenter?
    private var statusItem: NSStatusItem?
    private var currentSpec = HotKeySpec.default
    private var axPollTimer: Timer?

    // Explicit domain (~/Library/Preferences/com.cmd-m.plist): an unbundled
    // binary has no bundle ID, so UserDefaults.standard is not predictable.
    private static let defaults = UserDefaults(suiteName: "com.cmd-m") ?? .standard
    private static let hotkeyDefaultsKey = "hotkey"
    private static let presets: [(title: String, combo: String)] = [
        ("⌘ Fn  — clashes with nothing", "cmd+fn"),
        ("⌃⌘M", "ctrl+cmd+m"),
        ("⌃⌥M", "ctrl+alt+m"),
        ("⌘M  — overrides Minimize", "cmd+m"),
    ]

    init(cliSpec: HotKeySpec?, showMenuBarItem: Bool) {
        self.cliSpec = cliSpec
        self.showMenuBarItem = showMenuBarItem
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        let saved = Self.defaults.string(forKey: Self.hotkeyDefaultsKey)
            .flatMap(HotKeySpec.parse)
        applyHotKey(cliSpec ?? saved ?? .default)
        requestAccessibilityIfNeeded()

        guard showMenuBarItem else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⇄"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    private func applyHotKey(_ spec: HotKeySpec) {
        currentSpec = spec
        hotKeyCenter = nil
        Log.write("hotkey: applying \(spec.display) (accessibility trusted: \(AXIsProcessTrusted()))")
        hotKeyCenter = HotKeyCenter(spec: spec) { [weak self] in
            self?.converter.convertSelection()
        }
        statusItem?.button?.toolTip = "cmd-m — convert selection (\(spec.display))"
    }

    // Rebuilt every time the menu opens, so the permission warning and the
    // checkmark on the active shortcut stay current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        if !AXIsProcessTrusted() {
            let warn = NSMenuItem(
                title: "⚠️ Grant Accessibility Access…",
                action: #selector(openAccessibilitySettings),
                keyEquivalent: ""
            )
            warn.target = self
            menu.addItem(warn)
            menu.addItem(.separator())
        }

        let convertItem = NSMenuItem(
            title: "Convert Selection (\(currentSpec.display))",
            action: #selector(convertNow),
            keyEquivalent: ""
        )
        convertItem.target = self
        menu.addItem(convertItem)

        let shortcutMenu = NSMenu()
        for preset in Self.presets {
            let entry = NSMenuItem(title: preset.title, action: #selector(selectPreset(_:)), keyEquivalent: "")
            entry.target = self
            entry.representedObject = preset.combo
            entry.state = preset.combo == currentSpec.display ? .on : .off
            shortcutMenu.addItem(entry)
        }
        let shortcutItem = NSMenuItem(title: "Shortcut", action: nil, keyEquivalent: "")
        shortcutItem.submenu = shortcutMenu
        menu.addItem(shortcutItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit cmd-m", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let combo = sender.representedObject as? String,
              let spec = HotKeySpec.parse(combo) else { return }
        Self.defaults.set(combo, forKey: Self.hotkeyDefaultsKey)
        applyHotKey(spec)
    }

    @objc private func openAccessibilitySettings() {
        let pane = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        if let url = URL(string: pane) {
            NSWorkspace.shared.open(url)
        }
    }

    @objc private func convertNow() {
        // Small delay so the menu closes and focus returns to the previous app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.converter.convertSelection()
        }
    }

    private func requestAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        guard !AXIsProcessTrustedWithOptions(options) else { return }

        // Event monitors installed before the permission was granted never
        // fire, so watch for the grant and re-register — no relaunch needed.
        axPollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] timer in
            guard let self, AXIsProcessTrusted() else { return }
            timer.invalidate()
            self.axPollTimer = nil
            self.applyHotKey(self.currentSpec)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate(cliSpec: cliHotKeySpec, showMenuBarItem: showMenuBarItem)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
