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

    // MARK: - 工具方法

    /// 归一化 CloudKit recordName（把空字符串/全空格视为 nil）
    private func normalizedRecordName(_ recordName: String?) -> String? {
        guard let recordName else { return nil }
        let trimmed = recordName.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
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
            print("✅ 下载云端片段数量: \(cloudRecords.count)")
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
        snippet.needsSync = false

        try modelContext.save()

        print("✅ 片段已上传: \(snippet.title)")
    }

    /// 删除云端记录（删除片段时使用）
    func deleteCloudRecord(recordName: String) async throws {
        let recordID = CKRecord.ID(recordName: recordName)
        try await privateDatabase.deleteRecord(withID: recordID)
        print("✅ 云端记录已删除: \(recordName)")
    }

    /// 更新单个片段到 iCloud（修改片段时使用）
    func updateSnippet(_ snippet: Snippet) async throws {
        // 检查账户状态
        try await checkAccountStatus()

        // 如果是新片段（没有 cloudRecordID），直接上传
        guard let recordName = normalizedRecordName(snippet.cloudRecordID) else {
            try await uploadSnippet(snippet)
            return
        }

        // 先从云端获取已有记录
        let recordID = CKRecord.ID(recordName: recordName)
        let record = try await privateDatabase.record(for: recordID)

        // 修改记录字段
        record["snippetID"] = snippet.id.uuidString
        record["title"] = snippet.title
        record["content"] = snippet.content
        record["shortcutKey"] = snippet.shortcutKey
        record["showInMenuBar"] = (snippet.showInMenuBar ?? false) ? 1 : 0
        record["createdAt"] = snippet.createdAt
        record["updatedAt"] = snippet.updatedAt

        // 保存到 iCloud
        _ = try await privateDatabase.save(record)

        // 更新本地同步状态
        snippet.needsSync = false
        snippet.lastSyncedAt = Date()
        try modelContext.save()

        print("✅ 片段已更新: \(snippet.title)")
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

    /// 上传本地独有片段和已修改片段到云端
    private func uploadLocalSnippets() async throws -> Int {
        let descriptor = FetchDescriptor<Snippet>()
        let allSnippets = try modelContext.fetch(descriptor)

        // 筛选出需要同步的片段：1. 新片段（cloudRecordID 为空）2. 已修改片段（needsSync == true）
        let snippetsToSync = allSnippets.filter {
            normalizedRecordName($0.cloudRecordID) == nil || $0.needsSync == true
        }

        guard !snippetsToSync.isEmpty else {
            return 0
        }

        var uploadedCount = 0

        // 分为新增和更新两组
        let newSnippets = snippetsToSync.filter { normalizedRecordName($0.cloudRecordID) == nil }
        let updatedSnippets = snippetsToSync.filter { normalizedRecordName($0.cloudRecordID) != nil && $0.needsSync == true }

        // 批量上传新片段
        if !newSnippets.isEmpty {
            uploadedCount += try await batchUploadNewSnippets(newSnippets, allSnippets: allSnippets)
        }

        // 批量更新已有片段
        if !updatedSnippets.isEmpty {
            uploadedCount += try await batchUpdateExistingSnippets(updatedSnippets)
        }

        return uploadedCount
    }

    /// 批量上传新片段
    private func batchUploadNewSnippets(_ snippets: [Snippet], allSnippets: [Snippet]) async throws -> Int {
        var uploadedCount = 0
        let batchSize = 400

        for i in stride(from: 0, to: snippets.count, by: batchSize) {
            let end = min(i + batchSize, snippets.count)
            let batch = Array(snippets[i..<end])

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

            // 更新本地 Snippet 的 cloudRecordID 和同步状态
            for record in savedRecords {
                if let snippetID = record["snippetID"] as? String,
                   let uuid = UUID(uuidString: snippetID),
                   let snippet = allSnippets.first(where: { $0.id == uuid }) {
                    snippet.cloudRecordID = record.recordID.recordName
                    snippet.lastSyncedAt = Date()
                    snippet.needsSync = false
                }
            }

            uploadedCount += savedRecords.count
        }

        try modelContext.save()
        return uploadedCount
    }

    /// 批量更新已有片段
    private func batchUpdateExistingSnippets(_ snippets: [Snippet]) async throws -> Int {
        var updatedCount = 0
        let batchSize = 400

        for i in stride(from: 0, to: snippets.count, by: batchSize) {
            let end = min(i + batchSize, snippets.count)
            let batch = Array(snippets[i..<end])

            // 1. 先批量获取云端记录
            let recordIDs = batch.compactMap { snippet -> CKRecord.ID? in
                guard let recordName = normalizedRecordName(snippet.cloudRecordID) else { return nil }
                return CKRecord.ID(recordName: recordName)
            }

            guard !recordIDs.isEmpty else { continue }

            // 使用现代 API 批量获取记录
            let fetchResults = try await privateDatabase.records(for: recordIDs, desiredKeys: nil)

            // 2. 修改获取到的记录
            var recordsToSave: [CKRecord] = []
            for (recordID, result) in fetchResults {
                switch result {
                case .success(let record):
                    // 找到对应的 snippet
                    if let snippet = batch.first(where: { $0.cloudRecordID == recordID.recordName }) {
                        record["snippetID"] = snippet.id.uuidString
                        record["title"] = snippet.title
                        record["content"] = snippet.content
                        record["shortcutKey"] = snippet.shortcutKey
                        record["showInMenuBar"] = (snippet.showInMenuBar ?? false) ? 1 : 0
                        record["createdAt"] = snippet.createdAt
                        record["updatedAt"] = snippet.updatedAt
                        recordsToSave.append(record)
                    }
                case .failure(let error):
                    print("❌ 获取记录失败 \(recordID): \(error)")
                }
            }

            guard !recordsToSave.isEmpty else { continue }

            // 3. 批量保存
            let operation = CKModifyRecordsOperation(recordsToSave: recordsToSave, recordIDsToDelete: nil)
            operation.savePolicy = .changedKeys
            operation.qualityOfService = .userInitiated

            let savedRecords = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<[CKRecord], Error>) in
                var savedRecords: [CKRecord] = []

                operation.perRecordSaveBlock = { recordID, result in
                    switch result {
                    case .success(let record):
                        savedRecords.append(record)
                    case .failure(let error):
                        print("❌ 更新记录失败 \(recordID): \(error)")
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

            // 更新本地 Snippet 的同步状态
            for record in savedRecords {
                if let snippetID = record["snippetID"] as? String,
                   let uuid = UUID(uuidString: snippetID),
                   let snippet = batch.first(where: { $0.id == uuid }) {
                    snippet.needsSync = false
                    snippet.lastSyncedAt = Date()
                }
            }

            updatedCount += savedRecords.count
        }

        try modelContext.save()
        return updatedCount
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

    /// 合并云端数据到本地（按 updatedAt 决定覆盖方向）
    private func mergeCloudSnippets(_ cloudRecords: [SnippetCloudRecord]) async throws -> (imported: Int, skipped: Int, clearedShortcuts: Int) {
        let descriptor = FetchDescriptor<Snippet>()
        let existingSnippets = try modelContext.fetch(descriptor)

        // 本地索引
        var localBySnippetID: [String: Snippet] = [:]
        var localByContent: [String: Snippet] = [:]
        for snippet in existingSnippets {
            localBySnippetID[snippet.id.uuidString] = snippet
            if let existing = localByContent[snippet.content] {
                if snippet.updatedAt > existing.updatedAt {
                    localByContent[snippet.content] = snippet
                }
            } else {
                localByContent[snippet.content] = snippet
            }
        }

        // 快捷键占用表（沿用原策略：冲突时清空“新写入”的快捷键）
        var shortcutOwnerByKey: [String: String] = [:]
        for snippet in existingSnippets {
            if let key = snippet.shortcutKey?.trimmingCharacters(in: .whitespacesAndNewlines), !key.isEmpty {
                shortcutOwnerByKey[key] = snippet.id.uuidString
            }
        }

        func applyShortcut(_ shortcutKey: String?, to snippet: Snippet) -> Bool {
            // 返回是否发生了“冲突清空”
            let oldKey = snippet.shortcutKey?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let oldKey, !oldKey.isEmpty, shortcutOwnerByKey[oldKey] == snippet.id.uuidString {
                shortcutOwnerByKey.removeValue(forKey: oldKey)
            }

            let trimmed = shortcutKey?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let trimmed, !trimmed.isEmpty else {
                snippet.shortcutKey = nil
                return false
            }

            if let owner = shortcutOwnerByKey[trimmed], owner != snippet.id.uuidString {
                snippet.shortcutKey = nil
                return true
            }

            snippet.shortcutKey = trimmed
            shortcutOwnerByKey[trimmed] = snippet.id.uuidString
            return false
        }

        func syncPayloadMatches(_ snippet: Snippet, _ record: SnippetCloudRecord) -> Bool {
            (snippet.title == record.title) &&
            (snippet.content == record.content) &&
            ((snippet.shortcutKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines) == (record.shortcutKey ?? "").trimmingCharacters(in: .whitespacesAndNewlines)) &&
            ((snippet.showInMenuBar ?? false) == record.showInMenuBar) &&
            (snippet.createdAt == record.createdAt) &&
            (snippet.updatedAt == record.updatedAt)
        }

        func registerContentIndex(for snippet: Snippet, oldContent: String?) {
            if let oldContent, let mapped = localByContent[oldContent], mapped.id == snippet.id {
                localByContent.removeValue(forKey: oldContent)
            }
            if let existing = localByContent[snippet.content] {
                if snippet.updatedAt > existing.updatedAt {
                    localByContent[snippet.content] = snippet
                }
            } else {
                localByContent[snippet.content] = snippet
            }
        }

        // 云端索引
        var cloudBySnippetID: [String: SnippetCloudRecord] = [:]
        var cloudCanonicalByContent: [String: SnippetCloudRecord] = [:]
        var allCloudRecordNames = Set<String>()

        for record in cloudRecords {
            allCloudRecordNames.insert(record.recordID.recordName)

            if let existing = cloudBySnippetID[record.snippetID] {
                if record.updatedAt > existing.updatedAt {
                    cloudBySnippetID[record.snippetID] = record
                }
            } else {
                cloudBySnippetID[record.snippetID] = record
            }

            if let existing = cloudCanonicalByContent[record.content] {
                if record.updatedAt > existing.updatedAt {
                    cloudCanonicalByContent[record.content] = record
                }
            } else {
                cloudCanonicalByContent[record.content] = record
            }
        }

        var skippedCount = 0
        var clearedShortcutCount = 0
        var downloadedCount = 0
        var didChangeLocal = false

        // 1) 优先按 snippetID 处理（规则 1）
        for (snippetID, record) in cloudBySnippetID {
            guard let local = localBySnippetID[snippetID] else { continue }

            let localWins = local.updatedAt >= record.updatedAt  // updatedAt 相同优先本地
            if localWins {
                // 如果已完全一致，仅修正 cloudRecordID（必要时）即可
                let desiredRecordName = record.recordID.recordName
                let currentRecordName = normalizedRecordName(local.cloudRecordID)

                if currentRecordName != desiredRecordName {
                    local.cloudRecordID = desiredRecordName
                    didChangeLocal = true
                }

                if !syncPayloadMatches(local, record) {
                    local.needsSync = true
                    didChangeLocal = true
                }

                continue
            }

            // 云端更新更“新”，覆盖本地
            let oldContent = local.content
            local.title = record.title
            local.content = record.content
            local.showInMenuBar = record.showInMenuBar
            local.createdAt = record.createdAt
            local.updatedAt = record.updatedAt
            local.cloudRecordID = record.recordID.recordName
            local.needsSync = false
            local.lastSyncedAt = Date()
            downloadedCount += 1

            if applyShortcut(record.shortcutKey, to: local) {
                clearedShortcutCount += 1
            }

            registerContentIndex(for: local, oldContent: oldContent)
            didChangeLocal = true
        }

        // 2) 按 content 处理（规则 2/3，且同 content 只取云端最新一条）
        let canonicalCloudRecords = cloudCanonicalByContent.values.sorted { $0.updatedAt > $1.updatedAt }
        for record in canonicalCloudRecords {
            if localBySnippetID[record.snippetID] != nil {
                // 该 snippetID 已存在于本地，且已在上一步处理；这里不再重复导入
                continue
            }

            if let local = localByContent[record.content] {
                // content 命中，但 snippetID 不同（规则 3）
                let localWins = local.updatedAt >= record.updatedAt  // updatedAt 相同优先本地
                if localWins {
                    let desiredRecordName = record.recordID.recordName
                    let currentRecordName = normalizedRecordName(local.cloudRecordID)

                    if currentRecordName != desiredRecordName {
                        local.cloudRecordID = desiredRecordName
                        didChangeLocal = true
                    }

                    if !syncPayloadMatches(local, record) {
                        local.needsSync = true
                        didChangeLocal = true
                    }

                    continue
                }

                // 云端更“新”，覆盖本地（保持本地 id 不变）
                let oldContent = local.content
                local.title = record.title
                local.content = record.content
                local.showInMenuBar = record.showInMenuBar
                local.createdAt = record.createdAt
                local.updatedAt = record.updatedAt
                local.cloudRecordID = record.recordID.recordName
                local.needsSync = false
                local.lastSyncedAt = Date()
                downloadedCount += 1

                if applyShortcut(record.shortcutKey, to: local) {
                    clearedShortcutCount += 1
                }

                registerContentIndex(for: local, oldContent: oldContent)
                didChangeLocal = true
                continue
            }

            // 本地无 snippetID 命中、也无 content 命中（规则 2）：导入云端记录
            let newSnippet = Snippet(
                title: record.title,
                content: record.content,
                shortcutKey: nil,
                showInMenuBar: record.showInMenuBar
            )

            // 使用云端 snippetID 作为本地 id，确保跨设备可稳定匹配
            if let uuid = UUID(uuidString: record.snippetID) {
                newSnippet.id = uuid
            }

            newSnippet.createdAt = record.createdAt
            newSnippet.updatedAt = record.updatedAt
            newSnippet.cloudRecordID = record.recordID.recordName
            newSnippet.lastSyncedAt = Date()
            newSnippet.needsSync = false

            if applyShortcut(record.shortcutKey, to: newSnippet) {
                clearedShortcutCount += 1
            }

            modelContext.insert(newSnippet)
            localBySnippetID[newSnippet.id.uuidString] = newSnippet
            localByContent[newSnippet.content] = newSnippet

            downloadedCount += 1
            didChangeLocal = true
        }

        // 3) 修复“本地认为已同步，但云端无对应 record”的情况（旧数据不上传的根因之一）
        for snippet in existingSnippets {
            // 空白 recordName 直接视为 nil
            if normalizedRecordName(snippet.cloudRecordID) == nil, snippet.cloudRecordID != nil {
                snippet.cloudRecordID = nil
                didChangeLocal = true
            }

            guard let recordName = normalizedRecordName(snippet.cloudRecordID) else { continue }
            if !allCloudRecordNames.contains(recordName) {
                snippet.cloudRecordID = nil
                snippet.needsSync = true
                didChangeLocal = true
            }
        }

        // 统计 skipped：云端重复 content 的旧记录数量
        skippedCount = max(0, cloudRecords.count - cloudCanonicalByContent.count)

        if didChangeLocal {
            try modelContext.save()
            NotificationCenter.default.post(name: NSNotification.Name("HotKeysNeedUpdate"), object: nil)
            NotificationCenter.default.post(name: NSNotification.Name("MenuBarNeedUpdate"), object: nil)
        }

        return (downloadedCount, skippedCount, clearedShortcutCount)
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
