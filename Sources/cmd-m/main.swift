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

var hotKeySpec = HotKeySpec.default
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
                "Invalid hotkey. Example: --hotkey cmd+shift+m (modifiers: cmd, ctrl, alt, shift)\n".utf8))
            exit(1)
        }
        hotKeySpec = spec
        index += 1

    default:
        FileHandle.standardError.write(Data("Unknown argument: \(argument)\n".utf8))
        printUsage()
        exit(1)
    }
    index += 1
}

// MARK: - Menu bar app

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let spec: HotKeySpec
    private let showMenuBarItem: Bool
    private let converter = SelectionConverter()
    private var hotKeyCenter: HotKeyCenter?
    private var statusItem: NSStatusItem?

    init(spec: HotKeySpec, showMenuBarItem: Bool) {
        self.spec = spec
        self.showMenuBarItem = showMenuBarItem
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        requestAccessibilityIfNeeded()

        hotKeyCenter = HotKeyCenter(spec: spec) { [weak self] in
            self?.converter.convertSelection()
        }

        guard showMenuBarItem else { return }

        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⇄"
        item.button?.toolTip = "cmd-m — convert selection (\(spec.display))"

        let menu = NSMenu()
        let convertItem = NSMenuItem(
            title: "Convert Selection (\(spec.display))",
            action: #selector(convertNow),
            keyEquivalent: ""
        )
        convertItem.target = self
        menu.addItem(convertItem)
        menu.addItem(.separator())
        let quitItem = NSMenuItem(title: "Quit cmd-m", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quitItem)
        item.menu = menu
        statusItem = item
    }

    @objc private func convertNow() {
        // Small delay so the menu closes and focus returns to the previous app.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.converter.convertSelection()
        }
    }

    private func requestAccessibilityIfNeeded() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if !AXIsProcessTrustedWithOptions(options) {
            print("""
            cmd-m needs Accessibility permission to read and replace the selection.
            Grant it in System Settings → Privacy & Security → Accessibility, then relaunch.
            """)
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate(spec: hotKeySpec, showMenuBarItem: showMenuBarItem)
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
