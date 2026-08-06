import AppKit
import Carbon
import Foundation
import ServiceManagement

// MARK: - Command line interface

let arguments = Array(CommandLine.arguments.dropFirst())

func printUsage() {
    print("""
    relayout — retype selected text in your next keyboard layout

    Usage:
      relayout                     Run in the menu bar (default hotkey: cmd+fn)
      relayout --hotkey <combo>    Run with a custom hotkey, e.g. --hotkey ctrl+alt+m
                                or a fn/Globe chord, e.g. --hotkey cmd+fn
      relayout --no-menubar        Run without a menu bar icon (pure background agent)
      relayout --convert [text]    Convert text and print it; reads stdin if no text given
      relayout --switch --convert  Also switch the active layout (used by the Quick Action)
      relayout --layouts           List the enabled keyboard layouts relayout sees
      relayout --help              Show this help

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
    private var currentCombo = "auto"
    private var axPollTimer: Timer?

    // Explicit domain (~/Library/Preferences/com.relayout.plist): an unbundled
    // binary has no bundle ID, so UserDefaults.standard is not predictable.
    private static let defaults = UserDefaults(suiteName: "com.relayout") ?? .standard
    private static let hotkeyDefaultsKey = "hotkey"

    // "auto" arms both defaults at once, so keyboards whose fn key is
    // invisible to macOS still work out of the box via ⌘?.
    private static let autoCombos = ["cmd+fn", "cmd+?"]
    private static let presets: [(title: String, combo: String)] = [
        ("Auto  — ⌘ Fn or ⌘ ?", "auto"),
        ("⌘ Fn", "cmd+fn"),
        ("⌘ ?", "cmd+?"),
        ("Both ⌘ keys", "cmd+cmd"),
        ("Both ⇧ keys", "shift+shift"),
        ("⌃⌘M", "ctrl+cmd+m"),
    ]

    init(cliSpec: HotKeySpec?, showMenuBarItem: Bool) {
        self.cliSpec = cliSpec
        self.showMenuBarItem = showMenuBarItem
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if let cliSpec {
            applyHotKey(combo: cliSpec.display)
        } else {
            applyHotKey(combo: Self.defaults.string(forKey: Self.hotkeyDefaultsKey) ?? "auto")
        }
        setUpAppBundleExtrasIfNeeded()
        requestAccessibilityIfNeeded()

        guard showMenuBarItem else { return }
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⇄"
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        statusItem = item
    }

    private func specs(for combo: String) -> [HotKeySpec] {
        if combo == "auto" {
            return Self.autoCombos.compactMap(HotKeySpec.parse)
        }
        if let cliSpec, combo == cliSpec.display {
            return [cliSpec]
        }
        return HotKeySpec.parse(combo).map { [$0] } ?? []
    }

    private func applyHotKey(combo: String) {
        let specs = specs(for: combo)
        guard !specs.isEmpty else {
            applyHotKey(combo: "auto")
            return
        }
        currentCombo = combo
        hotKeyCenter = nil
        Log.write("hotkey: applying \(combo) (accessibility trusted: \(AXIsProcessTrusted()))")
        hotKeyCenter = HotKeyCenter(specs: specs) { [weak self] in
            self?.converter.convertSelection()
        }
        statusItem?.button?.toolTip = "relayout — convert selection (\(combo))"
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
            title: "Convert Selection (\(currentCombo))",
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
            entry.state = preset.combo == currentCombo ? .on : .off
            shortcutMenu.addItem(entry)
        }
        if !Self.presets.contains(where: { $0.combo == currentCombo }) {
            let entry = NSMenuItem(title: "Custom: \(currentCombo)", action: nil, keyEquivalent: "")
            entry.state = .on
            shortcutMenu.addItem(entry)
        }
        shortcutMenu.addItem(.separator())
        let customItem = NSMenuItem(title: "Custom…", action: #selector(chooseCustomShortcut), keyEquivalent: "")
        customItem.target = self
        shortcutMenu.addItem(customItem)
        let shortcutItem = NSMenuItem(title: "Shortcut", action: nil, keyEquivalent: "")
        shortcutItem.submenu = shortcutMenu
        menu.addItem(shortcutItem)

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit relayout", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func selectPreset(_ sender: NSMenuItem) {
        guard let combo = sender.representedObject as? String else { return }
        Self.defaults.set(combo, forKey: Self.hotkeyDefaultsKey)
        applyHotKey(combo: combo)
    }

    @objc private func chooseCustomShortcut() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Custom Shortcut"
        alert.informativeText = """
        Type a combo using cmd, ctrl, alt, shift, fn joined with "+", ending in a key.
        Examples: ctrl+alt+k · cmd+shift+9 · cmd+? · cmd+fn (modifier-only chord)
        """
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "e.g. ctrl+alt+k"
        field.stringValue = currentCombo == "auto" ? "" : currentCombo
        alert.accessoryView = field
        alert.addButton(withTitle: "Set")
        alert.addButton(withTitle: "Cancel")
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let combo = field.stringValue.trimmingCharacters(in: .whitespaces).lowercased()
        if combo == "auto" || HotKeySpec.parse(combo) != nil {
            Self.defaults.set(combo, forKey: Self.hotkeyDefaultsKey)
            applyHotKey(combo: combo)
        } else {
            let error = NSAlert()
            error.alertStyle = .warning
            error.messageText = "Couldn't understand \"\(combo)\""
            error.informativeText = "Use forms like ctrl+alt+k or cmd+? — modifiers joined with \"+\", ending in a single key (or a modifier-only chord like cmd+fn)."
            error.runModal()
        }
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

    /// When running as a double-clicked relayout.app (rather than a CLI
    /// binary managed by launchd), set up start-at-login and the Quick
    /// Action automatically — the app download needs zero terminal steps.
    private func setUpAppBundleExtrasIfNeeded() {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return }

        if #available(macOS 13.0, *) {
            if SMAppService.mainApp.status != .enabled {
                do {
                    try SMAppService.mainApp.register()
                    Log.write("app: registered as login item")
                } catch {
                    Log.write("app: login item registration failed: \(error.localizedDescription)")
                }
            }
        } else {
            installLoginLaunchAgentFallback()
        }
        installBundledQuickActionIfNeeded()
    }

    /// Pre-macOS 13 has no SMAppService; a LaunchAgent plist pointing into
    /// the app bundle gives the same start-at-login behavior.
    private func installLoginLaunchAgentFallback() {
        guard let executable = Bundle.main.executableURL?.path else { return }
        let agentsDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents")
        let plist = agentsDir.appendingPathComponent("com.relayout.plist")
        guard !FileManager.default.fileExists(atPath: plist.path) else { return }
        let content = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.relayout</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(executable)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <dict>
                <key>SuccessfulExit</key>
                <false/>
            </dict>
        </dict>
        </plist>
        """
        try? FileManager.default.createDirectory(at: agentsDir, withIntermediateDirectories: true)
        try? content.write(to: plist, atomically: true, encoding: .utf8)
        Log.write("app: login LaunchAgent written (pre-macOS 13)")
    }

    private func installBundledQuickActionIfNeeded() {
        let fm = FileManager.default
        guard let source = Bundle.main.url(forResource: "Convert Keyboard Layout", withExtension: "workflow") else { return }
        let servicesDir = fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Services")
        let target = servicesDir.appendingPathComponent("Convert Keyboard Layout.workflow")
        guard !fm.fileExists(atPath: target.path) else { return }

        do {
            try fm.createDirectory(at: servicesDir, withIntermediateDirectories: true)
            try fm.copyItem(at: source, to: target)
        } catch {
            Log.write("app: quick action install failed: \(error.localizedDescription)")
            return
        }
        // Pre-assign ⌃⌘M; the key must be passed plist-quoted or `defaults`
        // tries to parse the leading "(" as an array.
        runTool("/usr/bin/defaults", [
            "write", "pbs", "NSServicesStatus", "-dict-add",
            "\"(null) - Convert Keyboard Layout - runWorkflowAsService\"",
            "{key_equivalent = \"^@m\"; enabled_services_menu = 1;}",
        ])
        runTool("/System/Library/CoreServices/pbs", ["-update"])
        Log.write("app: quick action installed")
    }

    private func runTool(_ path: String, _ arguments: [String]) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        try? process.run()
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
            self.applyHotKey(combo: self.currentCombo)
        }
    }
}

// Single-instance guard: someone may have both the .app and a launchd agent
// installed — two live instances would each register the hotkey and convert
// the selection twice. First one wins; later ones exit quietly.
let lockDir = FileManager.default.homeDirectoryForCurrentUser
    .appendingPathComponent("Library/Application Support/relayout")
try? FileManager.default.createDirectory(at: lockDir, withIntermediateDirectories: true)
let lockFD = open(lockDir.appendingPathComponent("instance.lock").path, O_CREAT | O_RDWR, 0o644)
if lockFD >= 0, flock(lockFD, LOCK_EX | LOCK_NB) != 0 {
    Log.write("another relayout instance is already running — exiting")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate(cliSpec: cliHotKeySpec, showMenuBarItem: showMenuBarItem)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
