//
//  全局快捷键管理
//  快速剪贴
//
//  创建者：Brian He（2025/12/9）
//

import AppKit
import Carbon
import SwiftData
import ApplicationServices

class HotKeyManager {
    private var modelContext: ModelContext
    private var menuBarManager: MenuBarManager?
    private var hotKeyRefs: [UUID: EventHotKeyRef] = [:]
    private var hotKeyIDs: [UUID: EventHotKeyID] = [:]
    private var eventHandler: EventHandlerRef?
    private static var shared: HotKeyManager?

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        HotKeyManager.shared = self
        checkAccessibilityPermission()
        setupEventHandler()
    }

    private func checkAccessibilityPermission() {
        let options: NSDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)

        if accessEnabled {
            print("✅ Accessibility permission granted")
        } else {
            print("⚠️ Accessibility permission is required for global hotkeys")
            print("Go to: System Settings > Privacy & Security > Accessibility, then add QuickClip")
        }
    }

    func setMenuBarManager(_ manager: MenuBarManager) {
        self.menuBarManager = manager
    }

    private func setupEventHandler() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))

        let callback: EventHandlerUPP = { (nextHandler, theEvent, userData) -> OSStatus in
            var hotKeyID = EventHotKeyID()
            let error = GetEventParameter(
                theEvent,
                UInt32(kEventParamDirectObject),
                UInt32(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            if error == noErr {
                HotKeyManager.shared?.handleHotKey(id: hotKeyID)
            }

            return noErr
        }

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            nil,
            &eventHandler
        )
    }

    func registerAllHotKeys() {
        print("🔄 Registering all hotkeys...")
        unregisterAllHotKeys()

        let fetchDescriptor = FetchDescriptor<Snippet>()

        do {
            let snippets = try modelContext.fetch(fetchDescriptor)
            print("📋 Found \(snippets.count) snippets")

            var registeredCount = 0
            for snippet in snippets {
                if let shortcut = snippet.shortcutKey, !shortcut.isEmpty {
                    print("🔑 Registering hotkey: \(shortcut) for '\(snippet.title)'")
                    registerHotKey(for: snippet, shortcut: shortcut)
                    registeredCount += 1
                }
            }
            print("✅ Registered \(registeredCount) hotkeys")
        } catch {
            print("❌ Failed to fetch snippets: \(error)")
        }
    }

    private func registerHotKey(for snippet: Snippet, shortcut: String) {
        guard let (keyCode, modifiers) = parseShortcut(shortcut) else {
            print("❌ Failed to parse shortcut: \(shortcut)")
            return
        }

        print("  Parsed - keyCode: \(keyCode), modifiers: \(modifiers)")

        var hotKeyRef: EventHotKeyRef?

        // 安全地将 UUID 转换为 UInt32
        let uuidString = snippet.id.uuidString
        let hash = abs(uuidString.hashValue)
        let safeID = UInt32(truncatingIfNeeded: hash)

        let hotKeyID = EventHotKeyID(signature: OSType(0x48545259), id: safeID)
        print("  Generated HotKey ID: \(safeID)")

        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr, let hotKeyRef = hotKeyRef {
            hotKeyRefs[snippet.id] = hotKeyRef
            hotKeyIDs[snippet.id] = hotKeyID
            print("  ✅ Hotkey registered")
        } else {
            print("  ❌ Hotkey registration failed (status: \(status)) for: \(snippet.title)")
        }
    }

    func unregisterAllHotKeys() {
        for (_, hotKeyRef) in hotKeyRefs {
            UnregisterEventHotKey(hotKeyRef)
        }
        hotKeyRefs.removeAll()
        hotKeyIDs.removeAll()
    }

    private func handleHotKey(id: EventHotKeyID) {
        print("⌨️ Hotkey triggered! ID: \(id.id)")

        guard let snippetId = hotKeyIDs.first(where: { $0.value.id == id.id })?.key else {
            print("❌ No matching snippet ID found")
            return
        }

        print("📝 Found snippet ID: \(snippetId)")

        let fetchDescriptor = FetchDescriptor<Snippet>(
            predicate: #Predicate { $0.id == snippetId }
        )

        do {
            if let snippet = try modelContext.fetch(fetchDescriptor).first {
                print("✅ Copied snippet to clipboard: \(snippet.title)")
                ClipboardHelper.copyToClipboard(snippet.content)
                menuBarManager?.showCopyFeedback()
            }
        } catch {
            print("❌ Failed to fetch snippet: \(error)")
        }
    }

    private func parseShortcut(_ shortcut: String) -> (keyCode: Int, modifiers: Int)? {
        var modifiers = 0
        var keyString = shortcut

        if shortcut.contains("⌘") {
            modifiers |= cmdKey
            keyString = keyString.replacingOccurrences(of: "⌘", with: "")
        }
        if shortcut.contains("⇧") {
            modifiers |= shiftKey
            keyString = keyString.replacingOccurrences(of: "⇧", with: "")
        }
        if shortcut.contains("⌥") {
            modifiers |= optionKey
            keyString = keyString.replacingOccurrences(of: "⌥", with: "")
        }
        if shortcut.contains("⌃") {
            modifiers |= controlKey
            keyString = keyString.replacingOccurrences(of: "⌃", with: "")
        }

        guard let keyCode = keyCodeForCharacter(keyString) else {
            return nil
        }

        return (keyCode, modifiers)
    }

    private func keyCodeForCharacter(_ character: String) -> Int? {
        let keyCodeMap: [String: Int] = [
            "A": 0, "B": 11, "C": 8, "D": 2, "E": 14, "F": 3, "G": 5, "H": 4,
            "I": 34, "J": 38, "K": 40, "L": 37, "M": 46, "N": 45, "O": 31,
            "P": 35, "Q": 12, "R": 15, "S": 1, "T": 17, "U": 32, "V": 9,
            "W": 13, "X": 7, "Y": 16, "Z": 6,
            "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23,
            "6": 22, "7": 26, "8": 28, "9": 25,
            " ": 49, "SPACE": 49,
            "RETURN": 36, "ENTER": 36,
            "DELETE": 51, "BACKSPACE": 51,
            "TAB": 48,
            "ESCAPE": 53, "ESC": 53,
            "-": 27, "=": 24, "[": 33, "]": 30, "\\": 42,
            ";": 41, "'": 39, ",": 43, ".": 47, "/": 44,
            "`": 50
        ]

        return keyCodeMap[character.uppercased()]
    }

    deinit {
        unregisterAllHotKeys()
        if let eventHandler = eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}
