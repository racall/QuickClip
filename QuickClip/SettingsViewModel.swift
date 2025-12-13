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

    // iCloud 同步相关
    @Published var iCloudSyncEnabled: Bool {
        didSet {
            UserDefaults.standard.set(iCloudSyncEnabled, forKey: "iCloudSyncEnabled")
            if iCloudSyncEnabled {
                Task { await enableiCloudSync() }
            } else {
                disableiCloudSync()
            }
        }
    }

    @Published var isSyncing = false
    @Published var syncProgress: String = ""
    @Published var lastSyncTime: Date?

    private var syncManager: iCloudSyncManager?

    private var modelContext: ModelContext?  // ✅ 改为可选，支持延迟初始化
    private var allSnippets: [Snippet]
    private let onDidClearAll: () -> Void

    init(modelContext: ModelContext?, allSnippets: [Snippet], onDidClearAll: @escaping () -> Void) {
        self.modelContext = modelContext
        self.allSnippets = allSnippets
        self.onDidClearAll = onDidClearAll

        // 从 UserDefaults 加载 iCloud 开关状态
        self.iCloudSyncEnabled = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")

        // 加载最后同步时间
        if let timestamp = UserDefaults.standard.object(forKey: "lastSyncTime") as? Date {
            self.lastSyncTime = timestamp
        }
    }

    /// 更新数据源
    func updateData(modelContext: ModelContext, allSnippets: [Snippet]) {
        self.modelContext = modelContext
        self.allSnippets = allSnippets
    }

    // MARK: - 清空所有数据

    func clearAllData() {
        guard let modelContext = modelContext else {
            statusMessage = "ModelContext not initialized"
            return
        }

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
        guard let modelContext = modelContext else {
            statusMessage = "ModelContext not initialized"
            return
        }

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
            var importedSnippets: [Snippet] = []  // 收集新导入的片段

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
                importedSnippets.append(snippet)  // 记录导入的片段
                importedCount += 1
            }

            try modelContext.save()

            // iCloud 同步：上传导入的片段
            if !importedSnippets.isEmpty {
                syncImportedSnippetsToiCloud(importedSnippets)
            }

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

    // MARK: - iCloud 同步

    /// 开启 iCloud 同步
    private func enableiCloudSync() async {
        guard let modelContext = modelContext else {
            iCloudSyncEnabled = false
            statusMessage = "ModelContext not initialized"
            return
        }

        isSyncing = true
        statusMessage = "Enabling iCloud sync..."

        do {
            // 初始化 SyncManager
            syncManager = iCloudSyncManager(modelContext: modelContext)

            // 执行初始同步
            let result = try await syncManager?.performFullSync()

            // 保存最后同步时间
            lastSyncTime = Date()
            UserDefaults.standard.set(lastSyncTime, forKey: "lastSyncTime")

            statusMessage = "iCloud sync enabled. \(result?.summary ?? "")"
        } catch let error as SyncError {
            iCloudSyncEnabled = false  // 失败时自动关闭
            statusMessage = "Failed to enable iCloud: \(error.errorDescription ?? "Unknown error")"
        } catch {
            iCloudSyncEnabled = false
            statusMessage = "Failed to enable iCloud: \(error.localizedDescription)"
        }

        isSyncing = false
    }

    /// 关闭 iCloud 同步
    private func disableiCloudSync() {
        syncManager = nil
        statusMessage = "iCloud sync disabled"
    }

    /// 手动同步
    func manualSync() async {
        guard iCloudSyncEnabled else {
            statusMessage = "iCloud sync is not enabled"
            return
        }

        guard !isSyncing else {
            statusMessage = "Sync already in progress"
            return
        }

        guard let modelContext = modelContext else {
            statusMessage = "ModelContext not initialized"
            return
        }

        isSyncing = true
        statusMessage = "Syncing..."

        do {
            // 重新初始化 SyncManager（确保使用最新的 modelContext）
            if syncManager == nil {
                syncManager = iCloudSyncManager(modelContext: modelContext)
            }

            let result = try await syncManager?.performFullSync()

            // 保存最后同步时间
            lastSyncTime = Date()
            UserDefaults.standard.set(lastSyncTime, forKey: "lastSyncTime")

            statusMessage = "Sync completed. \(result?.summary ?? "")"
        } catch let error as SyncError {
            statusMessage = "Sync failed: \(error.errorDescription ?? "Unknown error")"
        } catch {
            statusMessage = "Sync failed: \(error.localizedDescription)"
        }

        isSyncing = false
    }

    /// App 启动时自动同步（如果已开启 iCloud）
    func performStartupSyncIfEnabled() async {
        guard iCloudSyncEnabled, !isSyncing else { return }
        guard let modelContext = modelContext else { return }

        print("🔄 App 启动时自动同步...")

        do {
            // 初始化 SyncManager
            if syncManager == nil {
                syncManager = iCloudSyncManager(modelContext: modelContext)
            }

            let result = try await syncManager?.performFullSync()

            // 保存最后同步时间
            lastSyncTime = Date()
            UserDefaults.standard.set(lastSyncTime, forKey: "lastSyncTime")

            print("✅ 启动同步完成: \(result?.summary ?? "")")
        } catch {
            print("❌ 启动同步失败: \(error.localizedDescription)")
        }
    }

    /// 上传导入的片段到 iCloud
    private func syncImportedSnippetsToiCloud(_ snippets: [Snippet]) {
        // 检查 iCloud 是否开启
        guard iCloudSyncEnabled else {
            return
        }

        guard let modelContext = modelContext else {
            return
        }

        Task { @MainActor in
            do {
                // 初始化 SyncManager
                if syncManager == nil {
                    syncManager = iCloudSyncManager(modelContext: modelContext)
                }

                var uploadedCount = 0
                for snippet in snippets {
                    do {
                        try await syncManager?.uploadSnippet(snippet)
                        uploadedCount += 1
                    } catch {
                        print("❌ 上传片段失败 (\(snippet.title)): \(error.localizedDescription)")
                    }
                }

                if uploadedCount > 0 {
                    print("✅ 已上传 \(uploadedCount) 个导入的片段到 iCloud")
                }
            }
        }
    }
}
