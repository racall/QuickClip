//
//  设置功能逻辑
//  快速剪贴
//
//  创建者：Brian He（2025/12/13）
//

import Foundation
import SwiftData
import AppKit
import UniformTypeIdentifiers
import Combine

/// 设置界面业务逻辑
@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var showClearConfirmation: Bool = false
    @Published var statusMessage: String = ""

    private var modelContext: ModelContext
    private var allSnippets: [Snippet]
    private let onDidClearAll: () -> Void

    init(modelContext: ModelContext, allSnippets: [Snippet], onDidClearAll: @escaping () -> Void) {
        self.modelContext = modelContext
        self.allSnippets = allSnippets
        self.onDidClearAll = onDidClearAll
    }

    /// 更新数据源
    func updateData(modelContext: ModelContext, allSnippets: [Snippet]) {
        self.modelContext = modelContext
        self.allSnippets = allSnippets
    }

    // MARK: - 清空所有数据

    func clearAllData() {
        for snippet in allSnippets {
            modelContext.delete(snippet)
        }

        do {
            try modelContext.save()
            statusMessage = "All snippets were cleared."
        } catch {
            statusMessage = "Failed to clear data: \(error.localizedDescription)"
        }

        onDidClearAll()

        NotificationCenter.default.post(name: NSNotification.Name("HotKeysNeedUpdate"), object: nil)
        NotificationCenter.default.post(name: NSNotification.Name("MenuBarNeedUpdate"), object: nil)
    }

    // MARK: - 导出 JSON

    func exportToJSON() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "QuickClip Snippets.json"
        panel.title = "Export Snippets"
        panel.message = "Choose a location to save the JSON file."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        let payload = SnippetExportFile(
            version: 1,
            exportedAt: Date(),
            snippets: allSnippets.map { snippet in
                SnippetExportItem(
                    title: snippet.title,
                    content: snippet.content,
                    shortcutKey: snippet.shortcutKey,
                    showInMenuBar: snippet.showInMenuBar ?? false,
                    createdAt: snippet.createdAt,
                    updatedAt: snippet.updatedAt
                )
            }
        )

        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(payload)
            try data.write(to: url, options: [.atomic])
            statusMessage = "Exported \(payload.snippets.count) snippets."
        } catch {
            statusMessage = "Failed to export: \(error.localizedDescription)"
        }
    }

    // MARK: - 导入 JSON

    func importFromJSON() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.title = "Import Snippets"
        panel.message = "Select a JSON file exported from QuickClip."

        guard panel.runModal() == .OK, let url = panel.url else { return }

        do {
            let data = try Data(contentsOf: url)
            let items = try decodeImportItems(from: data)

            var existingContents = Set(allSnippets.map(\.content))
            var usedShortcuts = Set(
                allSnippets
                    .compactMap(\.shortcutKey)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )

            var importedCount = 0
            var skippedSameContentCount = 0
            var clearedShortcutCount = 0

            for item in items {
                if existingContents.contains(item.content) {
                    skippedSameContentCount += 1
                    continue
                }

                let trimmedShortcut = item.shortcutKey?.trimmingCharacters(in: .whitespacesAndNewlines)
                let resolvedShortcut: String?
                if let trimmedShortcut, !trimmedShortcut.isEmpty, usedShortcuts.contains(trimmedShortcut) {
                    resolvedShortcut = nil
                    clearedShortcutCount += 1
                } else {
                    resolvedShortcut = trimmedShortcut
                    if let resolvedShortcut {
                        usedShortcuts.insert(resolvedShortcut)
                    }
                }

                let snippet = Snippet(
                    title: item.title,
                    content: item.content,
                    shortcutKey: resolvedShortcut,
                    showInMenuBar: item.showInMenuBar
                )

                snippet.createdAt = item.createdAt
                snippet.updatedAt = item.updatedAt

                modelContext.insert(snippet)
                existingContents.insert(item.content)
                importedCount += 1
            }

            try modelContext.save()

            var messageParts: [String] = []
            messageParts.append("Imported \(importedCount) snippets.")
            if skippedSameContentCount > 0 {
                messageParts.append("Skipped \(skippedSameContentCount) duplicate contents.")
            }
            if clearedShortcutCount > 0 {
                messageParts.append("Cleared \(clearedShortcutCount) conflicting hotkeys.")
            }
            statusMessage = messageParts.joined(separator: " ")

            NotificationCenter.default.post(name: NSNotification.Name("HotKeysNeedUpdate"), object: nil)
            NotificationCenter.default.post(name: NSNotification.Name("MenuBarNeedUpdate"), object: nil)
        } catch {
            statusMessage = "Failed to import: \(error.localizedDescription)"
        }
    }

    // MARK: - 解码导入数据

    private func decodeImportItems(from data: Data) throws -> [SnippetExportItem] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let file = try? decoder.decode(SnippetExportFile.self, from: data) {
            return file.snippets
        }
        return try decoder.decode([SnippetExportItem].self, from: data)
    }
}
