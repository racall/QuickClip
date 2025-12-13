//
//  iCloud 同步管理器
//  快速剪贴
//
//  创建者：Brian He（2025/12/13）
//

import Foundation
import CloudKit
import SwiftData
import Combine

/// CloudKit 记录数据结构
struct SnippetCloudRecord {
    let recordID: CKRecord.ID
    let snippetID: String           // Snippet.id.uuidString
    let title: String
    let content: String
    let shortcutKey: String?
    let showInMenuBar: Bool
    let createdAt: Date
    let updatedAt: Date
}

/// 同步结果统计
struct SyncResult {
    var uploaded: Int = 0           // 上传数量
    var downloaded: Int = 0         // 下载数量
    var skipped: Int = 0            // 跳过数量（内容重复）
    var clearedShortcuts: Int = 0   // 清除快捷键数量
    var deleted: Int = 0            // 删除数量

    var summary: String {
        var parts: [String] = []
        if uploaded > 0 { parts.append("Uploaded \(uploaded)") }
        if downloaded > 0 { parts.append("Downloaded \(downloaded)") }
        if skipped > 0 { parts.append("Skipped \(skipped)") }
        if clearedShortcuts > 0 { parts.append("Cleared \(clearedShortcuts) shortcuts") }
        if deleted > 0 { parts.append("Deleted \(deleted)") }
        return parts.isEmpty ? "No changes" : parts.joined(separator: ", ")
    }
}

/// iCloud 同步错误
enum SyncError: LocalizedError {
    case notSignedIn
    case networkUnavailable
    case quotaExceeded
    case permissionDenied
    case unknown(Error)

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in to iCloud"
        case .networkUnavailable:
            return "Network unavailable"
        case .quotaExceeded:
            return "iCloud storage quota exceeded"
        case .permissionDenied:
            return "iCloud permission denied"
        case .unknown(let error):
            return "Sync error: \(error.localizedDescription)"
        }
    }
}

/// iCloud 同步管理器
@MainActor
final class iCloudSyncManager: ObservableObject {

    // MARK: - 属性

    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private var modelContext: ModelContext

    /// 防止循环同步标记
    private var isSyncing = false

    /// 当前同步进度
    @Published var syncProgress: String = ""

    // MARK: - 初始化

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
        self.container = CKContainer(identifier: "iCloud.io.0os.QuickClip")
        self.privateDatabase = container.privateCloudDatabase
    }

    // MARK: - 公开接口

    /// 检查 iCloud 账户状态
    func checkAccountStatus() async throws {
        let status = try await container.accountStatus()

        switch status {
        case .couldNotDetermine:
            throw SyncError.unknown(NSError(domain: "iCloudSync", code: -1, userInfo: [NSLocalizedDescriptionKey: "Could not determine iCloud status"]))
        case .noAccount:
            throw SyncError.notSignedIn
        case .restricted:
            throw SyncError.permissionDenied
        case .available:
            break
        case .temporarilyUnavailable:
            throw SyncError.networkUnavailable
        @unknown default:
            throw SyncError.unknown(NSError(domain: "iCloudSync", code: -1, userInfo: [NSLocalizedDescriptionKey: "Unknown iCloud status"]))
        }
    }

    /// 执行完整同步（双向）
    func performFullSync() async throws -> SyncResult {
        guard !isSyncing else {
            print("⚠️ 同步正在进行中，跳过")
            return SyncResult()
        }

        isSyncing = true
        defer { isSyncing = false }

        var result = SyncResult()

        do {
            // 1. 检查账户状态
            try await checkAccountStatus()

            // 2. 下载云端数据
            syncProgress = "Downloading from iCloud..."
            let cloudRecords = try await downloadAllSnippets()

            // 3. 合并到本地（处理冲突）
            syncProgress = "Merging data..."
            let mergeResult = try await mergeCloudSnippets(cloudRecords)
            result.downloaded = mergeResult.imported
            result.skipped = mergeResult.skipped
            result.clearedShortcuts = mergeResult.clearedShortcuts

            // 4. 上传本地独有数据到云端
            syncProgress = "Uploading to iCloud..."
            let uploadCount = try await uploadLocalSnippets()
            result.uploaded = uploadCount

            syncProgress = ""
            return result

        } catch {
            syncProgress = ""
            if let ckError = error as? CKError {
                throw handleCloudKitError(ckError)
            }
            throw SyncError.unknown(error)
        }
    }

    /// 上传单个片段到 iCloud（新增片段时使用）
    func uploadSnippet(_ snippet: Snippet) async throws {
        // 检查账户状态
        try await checkAccountStatus()

        // 创建 CloudKit 记录
        let record = createCloudKitRecord(from: snippet)

        // 上传到 iCloud
        let savedRecord = try await privateDatabase.save(record)

        // 更新本地片段的 cloudRecordID
        snippet.cloudRecordID = savedRecord.recordID.recordName
        snippet.lastSyncedAt = Date()

        try modelContext.save()

        print("✅ 片段已上传: \(snippet.title)")
    }

    /// 删除云端记录（删除片段时使用）
    func deleteCloudRecord(recordName: String) async throws {
        let recordID = CKRecord.ID(recordName: recordName)
        try await privateDatabase.deleteRecord(withID: recordID)
        print("✅ 云端记录已删除: \(recordName)")
    }

    // MARK: - CloudKit 操作

    /// 下载所有云端片段（使用现代 async/await API）
    private func downloadAllSnippets() async throws -> [SnippetCloudRecord] {
        let query = CKQuery(recordType: "Snippet", predicate: NSPredicate(value: true))
        // 注意：不在 CloudKit 查询中排序，避免 "Field is not marked sortable" 错误
        // 下载后在本地排序即可

        var allRecords: [SnippetCloudRecord] = []
        var cursor: CKQueryOperation.Cursor?

        repeat {
            // ✅ 使用现代 async API
            let (matchResults, nextCursor): ([(CKRecord.ID, Result<CKRecord, Error>)], CKQueryOperation.Cursor?)

            if let cursor = cursor {
                // 继续从游标获取
                (matchResults, nextCursor) = try await privateDatabase.records(
                    continuingMatchFrom: cursor,
                    desiredKeys: nil
                )
            } else {
                // 首次查询
                (matchResults, nextCursor) = try await privateDatabase.records(
                    matching: query,
                    desiredKeys: nil
                )
            }

            cursor = nextCursor

            // ✅ 在主线程解析记录（避免 actor 隔离问题）
            for (_, result) in matchResults {
                switch result {
                case .success(let record):
                    if let snippetRecord = parseCloudKitRecord(record) {
                        allRecords.append(snippetRecord)
                    }
                case .failure(let error):
                    print("❌ 获取记录失败: \(error)")
                }
            }
        } while cursor != nil

        // 在本地按创建时间排序（从新到旧）
        return allRecords.sorted { $0.createdAt > $1.createdAt }
    }

    /// 解析 CloudKit 记录
    private func parseCloudKitRecord(_ record: CKRecord) -> SnippetCloudRecord? {
        guard
            let snippetID = record["snippetID"] as? String,
            let title = record["title"] as? String,
            let content = record["content"] as? String,
            let showInMenuBarInt = record["showInMenuBar"] as? Int64,
            let createdAt = record["createdAt"] as? Date,
            let updatedAt = record["updatedAt"] as? Date
        else {
            print("⚠️ 记录字段缺失: \(record.recordID)")
            return nil
        }

        let shortcutKey = record["shortcutKey"] as? String

        return SnippetCloudRecord(
            recordID: record.recordID,
            snippetID: snippetID,
            title: title,
            content: content,
            shortcutKey: shortcutKey,
            showInMenuBar: showInMenuBarInt == 1,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }

    /// 上传本地独有片段到云端
    private func uploadLocalSnippets() async throws -> Int {
        let descriptor = FetchDescriptor<Snippet>()
        let allSnippets = try modelContext.fetch(descriptor)

        // 筛选出未同步的片段（cloudRecordID 为空）
        let unSyncedSnippets = allSnippets.filter { $0.cloudRecordID == nil }

        guard !unSyncedSnippets.isEmpty else {
            return 0
        }

        var uploadedCount = 0

        // 批量上传（每批最多 400 个，CloudKit 限制）
        let batchSize = 400
        for i in stride(from: 0, to: unSyncedSnippets.count, by: batchSize) {
            let end = min(i + batchSize, unSyncedSnippets.count)
            let batch = Array(unSyncedSnippets[i..<end])

            let records = batch.map { createCloudKitRecord(from: $0) }

            let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            operation.qualityOfService = .userInitiated

            let savedRecords = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[CKRecord], Error>) in
                var savedRecords: [CKRecord] = []

                operation.perRecordSaveBlock = { recordID, result in
                    switch result {
                    case .success(let record):
                        savedRecords.append(record)
                    case .failure(let error):
                        print("❌ 上传记录失败 \(recordID): \(error)")
                    }
                }

                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume(returning: savedRecords)
                    case .failure(let error):
                        continuation.resume(throwing: error)
                    }
                }

                privateDatabase.add(operation)
            }

            // 更新本地 Snippet 的 cloudRecordID
            for record in savedRecords {
                if let snippetID = record["snippetID"] as? String,
                   let uuid = UUID(uuidString: snippetID),
                   let snippet = allSnippets.first(where: { $0.id == uuid }) {
                    snippet.cloudRecordID = record.recordID.recordName
                    snippet.lastSyncedAt = Date()
                }
            }

            uploadedCount += savedRecords.count
        }

        try modelContext.save()

        return uploadedCount
    }

    /// 创建 CloudKit 记录
    private func createCloudKitRecord(from snippet: Snippet) -> CKRecord {
        let record = CKRecord(recordType: "Snippet")

        record["snippetID"] = snippet.id.uuidString
        record["title"] = snippet.title
        record["content"] = snippet.content
        record["shortcutKey"] = snippet.shortcutKey
        record["showInMenuBar"] = (snippet.showInMenuBar ?? false) ? 1 : 0
        record["createdAt"] = snippet.createdAt
        record["updatedAt"] = snippet.updatedAt

        return record
    }

    /// 合并云端数据到本地（复用导入逻辑）
    private func mergeCloudSnippets(_ cloudRecords: [SnippetCloudRecord]) async throws -> (imported: Int, skipped: Int, clearedShortcuts: Int) {
        let descriptor = FetchDescriptor<Snippet>()
        let existingSnippets = try modelContext.fetch(descriptor)

        // 1. 构建内容集合（检测重复）
        let existingContents = Set(existingSnippets.map(\.content))

        // 2. 构建已有的 snippetID 集合（避免重复导入）
        let existingSnippetIDs = Set(existingSnippets.map { $0.id.uuidString })

        // 3. 构建快捷键集合（检测冲突）
        var usedShortcuts = Set<String>()
        for snippet in existingSnippets {
            if let key = snippet.shortcutKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
                usedShortcuts.insert(key)
            }
        }

        var importedCount = 0
        var skippedCount = 0
        var clearedShortcutCount = 0

        for record in cloudRecords {
            // 检查是否已存在（通过 snippetID）
            if existingSnippetIDs.contains(record.snippetID) {
                skippedCount += 1
                continue
            }

            // 内容重复检查
            if existingContents.contains(record.content) {
                skippedCount += 1
                continue
            }

            // 快捷键冲突处理
            let trimmedShortcut = record.shortcutKey?.trimmingCharacters(in: .whitespacesAndNewlines)
            let resolvedShortcut: String?

            if let trimmedShortcut, !trimmedShortcut.isEmpty, usedShortcuts.contains(trimmedShortcut) {
                resolvedShortcut = nil
                clearedShortcutCount += 1
            } else {
                resolvedShortcut = trimmedShortcut
                if let resolvedShortcut, !resolvedShortcut.isEmpty {
                    usedShortcuts.insert(resolvedShortcut)
                }
            }

            // 创建新 Snippet
            let newSnippet = Snippet(
                title: record.title,
                content: record.content,
                shortcutKey: resolvedShortcut,
                showInMenuBar: record.showInMenuBar
            )

            // 保留原始时间戳
            newSnippet.createdAt = record.createdAt
            newSnippet.updatedAt = record.updatedAt

            // 保存云端记录 ID
            newSnippet.cloudRecordID = record.recordID.recordName
            newSnippet.lastSyncedAt = Date()

            modelContext.insert(newSnippet)
            importedCount += 1
        }

        if importedCount > 0 {
            try modelContext.save()

            // 发送通知更新
            NotificationCenter.default.post(name: NSNotification.Name("HotKeysNeedUpdate"), object: nil)
            NotificationCenter.default.post(name: NSNotification.Name("MenuBarNeedUpdate"), object: nil)
        }

        return (importedCount, skippedCount, clearedShortcutCount)
    }

    // MARK: - 错误处理

    private func handleCloudKitError(_ error: CKError) -> SyncError {
        switch error.code {
        case .notAuthenticated:
            return .notSignedIn
        case .networkUnavailable, .networkFailure:
            return .networkUnavailable
        case .quotaExceeded:
            return .quotaExceeded
        case .permissionFailure:
            return .permissionDenied
        default:
            return .unknown(error)
        }
    }
}
