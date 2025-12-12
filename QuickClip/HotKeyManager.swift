import AppKit
import Carbon
import SwiftData

final class HotKeyManager {

    private let modelContext: ModelContext
    private weak var menuBarManager: MenuBarManager?

    private var eventHandler: EventHandlerRef?
    private var hotKeyRefsBySnippetID: [UUID: EventHotKeyRef] = [:]

    // Carbon HotKeyID -> Snippet UUID（O(1) 查找）
    private var carbonIDToSnippetID: [UInt32: UUID] = [:]
    private var nextCarbonID: UInt32 = 1

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        setupEventHandler()
    }

    func setMenuBarManager(_ manager: MenuBarManager) {
        self.menuBarManager = manager
    }

    // MARK: - Event Handler

    private func setupEventHandler() {
        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let callback: EventHandlerUPP = { _, theEvent, userData in
            guard let userData else { return noErr }

            let manager = Unmanaged<HotKeyManager>
                .fromOpaque(userData)
                .takeUnretainedValue()

            var hotKeyID = EventHotKeyID()
            let err = GetEventParameter(
                theEvent,
                UInt32(kEventParamDirectObject),
                UInt32(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )

            if err == noErr {
                manager.handleHotKey(carbonID: hotKeyID.id)
            }
            return noErr
        }

        // 用 userData 传 self（不用 static shared）
        let userData = Unmanaged.passUnretained(self).toOpaque()

        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            userData,
            &eventHandler
        )
    }

    // MARK: - Register / Unregister

    func registerAllHotKeys() {
        unregisterAllHotKeys()

        let fetchDescriptor = FetchDescriptor<Snippet>()
        do {
            let snippets = try modelContext.fetch(fetchDescriptor)
            for snippet in snippets {
                guard let shortcut = snippet.shortcutKey, !shortcut.isEmpty else { continue }
                registerHotKey(for: snippet, shortcut: shortcut)
            }
        } catch {
            print("❌ Failed to fetch snippets: \(error)")
        }
    }

    private func registerHotKey(for snippet: Snippet, shortcut: String) {
        guard let (keyCode, modifiers) = parseShortcut(shortcut) else {
            print("❌ Failed to parse shortcut: \(shortcut)")
            return
        }

        var hotKeyRef: EventHotKeyRef?

        // 分配稳定 carbon ID
        let carbonID = nextCarbonID
        nextCarbonID &+= 1
        carbonIDToSnippetID[carbonID] = snippet.id

        let hotKeyID = EventHotKeyID(signature: OSType(0x48545259), id: carbonID)

        let status = RegisterEventHotKey(
            UInt32(keyCode),
            UInt32(modifiers),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )

        if status == noErr, let hotKeyRef {
            hotKeyRefsBySnippetID[snippet.id] = hotKeyRef
        } else {
            carbonIDToSnippetID.removeValue(forKey: carbonID)
            print("❌ Hotkey registration failed (status: \(status)) for: \(snippet.title)")
        }
    }

    func unregisterAllHotKeys() {
        for (_, ref) in hotKeyRefsBySnippetID {
            UnregisterEventHotKey(ref)
        }
        hotKeyRefsBySnippetID.removeAll()
        carbonIDToSnippetID.removeAll()
        nextCarbonID = 1
    }

    // MARK: - Trigger

    private func handleHotKey(carbonID: UInt32) {
        guard let snippetID = carbonIDToSnippetID[carbonID] else {
            print("❌ No snippet mapping for hotkey id: \(carbonID)")
            return
        }

        let fetchDescriptor = FetchDescriptor<Snippet>(
            predicate: #Predicate { $0.id == snippetID }
        )

        do {
            if let snippet = try modelContext.fetch(fetchDescriptor).first {
                ClipboardHelper.copyToClipboard(snippet.content)
                menuBarManager?.showCopyFeedback()
            }
        } catch {
            print("❌ Failed to fetch snippet: \(error)")
        }
    }

    // MARK: - Shortcut parsing

    private func parseShortcut(_ shortcut: String) -> (keyCode: Int, modifiers: Int)? {
        var modifiers = 0
        var keyString = shortcut

        if shortcut.contains("⌘") { modifiers |= cmdKey;     keyString = keyString.replacingOccurrences(of: "⌘", with: "") }
        if shortcut.contains("⇧") { modifiers |= shiftKey;   keyString = keyString.replacingOccurrences(of: "⇧", with: "") }
        if shortcut.contains("⌥") { modifiers |= optionKey;  keyString = keyString.replacingOccurrences(of: "⌥", with: "") }
        if shortcut.contains("⌃") { modifiers |= controlKey; keyString = keyString.replacingOccurrences(of: "⌃", with: "") }

        guard let keyCode = keyCodeForCharacter(keyString) else { return nil }
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
        return keyCodeMap[character.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()]
    }

    deinit {
        unregisterAllHotKeys()
        if let eventHandler {
            RemoveEventHandler(eventHandler)
        }
    }
}