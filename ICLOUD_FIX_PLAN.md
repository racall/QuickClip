# iCloud 同步功能修复方案

## 必须修复（3个问题）

### ❗ 问题 1：线程安全问题 - CloudKit 回调中的 Actor 隔离违规

**位置**: `iCloudSyncManager.swift:209-242` (fetchRecords 方法)

**问题描述**:
```swift
operation.recordMatchedBlock = { recordID, result in
    switch result {
    case .success(let record):
        if let snippetRecord = self.parseCloudKitRecord(record) {  // ❌ 后台线程调用 @MainActor 方法
            fetchedRecords.append(snippetRecord)  // ❌ 非线程安全的数组操作
        }
    }
}
```

**修复方案**:

#### 方案 A：使用 MainActor.run（简单快速）
```swift
operation.recordMatchedBlock = { recordID, result in
    switch result {
    case .success(let record):
        Task { @MainActor in
            if let snippetRecord = self.parseCloudKitRecord(record) {
                fetchedRecords.append(snippetRecord)
            }
        }
    }
}
```

**优点**: 修改量小
**缺点**: 仍然使用旧的操作型 API

#### 方案 B：切换到现代 async CloudKit API（推荐）
```swift
/// 下载所有云端片段（使用现代 API）
private func downloadAllSnippets() async throws -> [SnippetCloudRecord] {
    let query = CKQuery(recordType: "Snippet", predicate: NSPredicate(value: true))

    var allRecords: [SnippetCloudRecord] = []
    var cursor: CKQueryOperation.Cursor?

    repeat {
        // 使用现代 async API
        let (matchResults, nextCursor) = try await privateDatabase.records(
            matching: query,
            continuingMatchFrom: cursor,
            desiredKeys: nil
        )

        cursor = nextCursor

        // 在主线程解析记录
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

    return allRecords.sorted { $0.createdAt > $1.createdAt }
}
```

**优点**:
- 彻底解决线程安全问题
- 代码更简洁
- 使用 Apple 推荐的现代 API

**缺点**: 需要修改更多代码

**推荐**: 方案 B（一次性解决，避免未来问题）

---

### ❗ 问题 2：删除操作"回滚"风险

**位置**: `SnippetListView.swift:127-150` (deleteSnippet 方法)

**问题描述**:
```swift
private func deleteSnippet(_ snippet: Snippet) {
    let cloudRecordID = snippet.cloudRecordID

    // ❌ 先删除本地
    modelContext.delete(snippet)
    try? modelContext.save()

    // 如果云端删除失败，下次同步会重新导入
    if let recordID = cloudRecordID {
        deleteSnippetFromiCloud(recordID: recordID)
    }
}
```

**修复方案**:

#### 方案 A：先删除云端，再删除本地（推荐）
```swift
private func deleteSnippet(_ snippet: Snippet) {
    print("🗑️ Delete snippet: \(snippet.title)")

    let hasHotKey = snippet.shortcutKey != nil
    let cloudRecordID = snippet.cloudRecordID

    // 如果当前选中的是这个片段，清除选中状态
    if selectedSnippet?.id == snippet.id {
        selectedSnippet = nil
    }

    // ✅ 先尝试删除云端（如果有）
    if let recordID = cloudRecordID, UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") {
        Task { @MainActor in
            do {
                let syncManager = iCloudSyncManager(modelContext: modelContext)
                try await syncManager.deleteCloudRecord(recordName: recordID)
                print("✅ 云端记录已删除: \(recordID)")

                // ✅ 云端删除成功后，再删除本地
                deleteSnippetLocally(snippet, hasHotKey: hasHotKey)
            } catch {
                print("❌ 删除云端片段失败: \(error.localizedDescription)")
                // ⚠️ 云端删除失败，询问用户是否继续删除本地
                showCloudDeleteFailureAlert(snippet: snippet, hasHotKey: hasHotKey)
            }
        }
    } else {
        // 没有云端记录或 iCloud 未开启，直接删除本地
        deleteSnippetLocally(snippet, hasHotKey: hasHotKey)
    }
}

/// 删除本地片段
private func deleteSnippetLocally(_ snippet: Snippet, hasHotKey: Bool) {
    modelContext.delete(snippet)
    try? modelContext.save()

    if hasHotKey {
        NotificationCenter.default.post(name: NSNotification.Name("HotKeysNeedUpdate"), object: nil)
    }
}

/// 显示云端删除失败提示
private func showCloudDeleteFailureAlert(snippet: Snippet, hasHotKey: Bool) {
    // TODO: 显示警告对话框，询问用户是否仍要删除本地副本
    // 暂时先删除本地（保持原有行为）
    deleteSnippetLocally(snippet, hasHotKey: hasHotKey)
}
```

**优点**:
- 避免删除后重新出现的问题
- 提供用户友好的错误处理

**缺点**: 需要等待网络操作（但这是正确的做法）

#### 方案 B：实现删除队列（复杂但健壮）
```swift
// 在 Snippet 模型中添加
var pendingDeletion: Bool = false  // 标记为待删除

// 删除流程
1. 标记 snippet.pendingDeletion = true
2. 从 UI 中隐藏（过滤掉 pendingDeletion == true）
3. 后台异步删除云端
4. 成功后删除本地
5. 失败则重试（指数退避）
```

**优点**:
- 离线时也能"删除"（实际是隐藏）
- 有重试机制

**缺点**:
- 实现复杂
- 需要修改数据模型

**推荐**: 方案 A（简单且有效）

---

### ❗ 问题 3：多容器风险

**位置**: `SettingsView.swift:25` (init 方法)

**问题描述**:
```swift
init(onDidClearAll: @escaping () -> Void) {
    self.onDidClearAll = onDidClearAll
    // ❌ 创建新的 ModelContainer
    _viewModel = StateObject(wrappedValue: SettingsViewModel(
        modelContext: ModelContext(ModelContainer.shared),  // 与主容器不同步
        allSnippets: [],
        onDidClearAll: onDidClearAll
    ))
}
```

**修复方案**:

#### 方案 A：使用 Environment 传递 ModelContext（推荐）
```swift
// 1. 修改 SettingsView.swift
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Snippet.createdAt, order: .reverse) private var allSnippets: [Snippet]

    // ✅ 移除临时容器，直接使用 Environment 的 modelContext
    @StateObject private var viewModel: SettingsViewModel

    let onDidClearAll: () -> Void

    init(onDidClearAll: @escaping () -> Void) {
        self.onDidClearAll = onDidClearAll
        // ✅ 延迟初始化（在 onAppear 中完成）
        _viewModel = StateObject(wrappedValue: SettingsViewModel(
            modelContext: nil,  // 临时占位
            allSnippets: [],
            onDidClearAll: onDidClearAll
        ))
    }

    var body: some View {
        VStack {
            // ... UI 代码 ...
        }
        .onAppear {
            // ✅ 使用真实的 Environment modelContext
            if viewModel.modelContext == nil {
                viewModel.updateData(modelContext: modelContext, allSnippets: allSnippets)
            }
        }
    }
}

// 2. 修改 SettingsViewModel.swift
@MainActor
final class SettingsViewModel: ObservableObject {
    private var modelContext: ModelContext?  // ✅ 改为可选

    init(modelContext: ModelContext?, allSnippets: [Snippet], onDidClearAll: @escaping () -> Void) {
        self.modelContext = modelContext
        // ... 其他初始化 ...
    }
}

// 3. 删除 SettingsView.swift 末尾的 ModelContainer.shared 扩展
```

**优点**:
- 只有一个 ModelContainer
- 符合 SwiftUI 最佳实践
- 避免数据不一致

**缺点**: 需要修改初始化逻辑

#### 方案 B：传递共享容器（次选）
```swift
// 在 QuickClipApp.swift 中通过 Environment 传递
.environment(\.modelContainer, sharedModelContainer)

// 在 SettingsView 中使用
@Environment(\.modelContainer) private var sharedContainer
```

**推荐**: 方案 A（更符合 SwiftUI 设计模式）

---

## 应该修复（3个问题）

### ⚠️ 问题 4：进度 UI 未连接

**位置**:
- `iCloudSyncManager.swift:81, 131` (设置 syncProgress)
- `SettingsViewModel.swift:33` (声明 syncProgress)
- `SettingsView.swift:170` (显示 syncProgress)

**问题描述**:
```swift
// iCloudSyncManager 中
syncProgress = "Downloading from iCloud..."  // ❌ 只设置了 manager 的属性

// SettingsViewModel 中
@Published var syncProgress: String = ""  // ❌ 从未更新

// SettingsView 中显示
Text(viewModel.syncProgress)  // ❌ 永远是空字符串
```

**修复方案**:

#### 方案 A：使用 Combine 绑定（推荐）
```swift
// 1. 在 SettingsViewModel.swift 中
import Combine

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var syncProgress: String = ""
    private var syncManager: iCloudSyncManager?
    private var progressCancellable: AnyCancellable?  // ✅ 添加订阅

    private func enableiCloudSync() async {
        // ... 初始化 syncManager ...
        syncManager = iCloudSyncManager(modelContext: modelContext)

        // ✅ 绑定进度
        progressCancellable = syncManager?.$syncProgress
            .receive(on: DispatchQueue.main)
            .assign(to: \.syncProgress, on: self)

        // ... 执行同步 ...
    }

    private func disableiCloudSync() {
        progressCancellable?.cancel()  // ✅ 取消绑定
        progressCancellable = nil
        syncManager = nil
        syncProgress = ""
        statusMessage = "iCloud sync disabled"
    }
}
```

**优点**:
- 自动同步进度
- 符合响应式编程模式

**缺点**: 需要添加 Combine 依赖

#### 方案 B：手动传递进度回调（次选）
```swift
// 在 iCloudSyncManager 中添加回调
var onProgressUpdate: ((String) -> Void)?

syncProgress = "Downloading..."
onProgressUpdate?("Downloading...")

// 在 SettingsViewModel 中设置回调
syncManager.onProgressUpdate = { [weak self] progress in
    self?.syncProgress = progress
}
```

**推荐**: 方案 A（更 SwiftUI 化）

---

### ⚠️ 问题 5：部分失败未处理

**位置**: `iCloudSyncManager.swift:295-320` (uploadLocalSnippets 方法)

**问题描述**:
```swift
let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)

operation.perRecordSaveBlock = { recordID, result in
    switch result {
    case .success(let record):
        savedRecords.append(record)
    case .failure(let error):
        print("❌ 上传记录失败 \(recordID): \(error)")  // ❌ 只打印，不处理
    }
}

// ❌ 部分失败会导致整个操作抛出错误，丢失成功的记录
```

**修复方案**:

```swift
/// 上传本地独有片段到云端（改进版）
private func uploadLocalSnippets() async throws -> Int {
    let descriptor = FetchDescriptor<Snippet>()
    let allSnippets = try modelContext.fetch(descriptor)

    let unSyncedSnippets = allSnippets.filter { $0.cloudRecordID == nil }
    guard !unSyncedSnippets.isEmpty else { return 0 }

    var uploadedCount = 0
    var failedSnippets: [(Snippet, Error)] = []  // ✅ 收集失败的片段

    let batchSize = 400
    for i in stride(from: 0, to: unSyncedSnippets.count, by: batchSize) {
        let end = min(i + batchSize, unSyncedSnippets.count)
        let batch = Array(unSyncedSnippets[i..<end])

        let records = batch.map { createCloudKitRecord(from: $0) }
        let operation = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
        operation.savePolicy = .changedKeys
        operation.qualityOfService = .userInitiated

        // ✅ 收集成功和失败的记录
        var successfulRecords: [CKRecord] = []
        var recordErrors: [CKRecord.ID: Error] = [:]

        operation.perRecordSaveBlock = { recordID, result in
            switch result {
            case .success(let record):
                successfulRecords.append(record)
            case .failure(let error):
                recordErrors[recordID] = error
            }
        }

        do {
            _ = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                operation.modifyRecordsResultBlock = { result in
                    switch result {
                    case .success:
                        continuation.resume()
                    case .failure(let error):
                        // ✅ 区分完全失败和部分失败
                        if let ckError = error as? CKError, ckError.code == .partialFailure {
                            // 部分失败，继续处理成功的记录
                            continuation.resume()
                        } else {
                            continuation.resume(throwing: error)
                        }
                    }
                }

                privateDatabase.add(operation)
            }

            // ✅ 更新成功上传的片段
            for record in successfulRecords {
                if let snippetID = record["snippetID"] as? String,
                   let uuid = UUID(uuidString: snippetID),
                   let snippet = batch.first(where: { $0.id == uuid }) {
                    snippet.cloudRecordID = record.recordID.recordName
                    snippet.lastSyncedAt = Date()
                    uploadedCount += 1
                }
            }

            // ✅ 记录失败的片段
            for (recordID, error) in recordErrors {
                let recordName = recordID.recordName
                if let snippet = batch.first(where: {
                    createCloudKitRecord(from: $0).recordID.recordName == recordName
                }) {
                    failedSnippets.append((snippet, error))
                }
            }

        } catch {
            // 整个批次失败
            print("❌ 批量上传失败: \(error)")
            throw error
        }
    }

    try modelContext.save()

    // ✅ 如果有失败的记录，记录日志或返回详细信息
    if !failedSnippets.isEmpty {
        print("⚠️ \(failedSnippets.count) 个片段上传失败")
        for (snippet, error) in failedSnippets {
            print("   - \(snippet.title): \(error.localizedDescription)")
        }
    }

    return uploadedCount
}
```

**优点**:
- 部分失败不会丢失成功的记录
- 提供详细的失败信息
- 可以实现重试逻辑

---

### ⚠️ 问题 6：分散的同步触发点

**位置**:
- `ContentView.swift:48` (启动同步)
- `SettingsViewModel.swift:257` (手动同步)
- `SnippetListView.swift:112, 127` (增删同步)

**问题描述**:
多个组件独立触发同步，可能导致：
- 并发的 CloudKit 写入冲突
- 重复的同步操作
- 难以追踪同步状态

**修复方案**:

#### 创建 SyncCoordinator 服务
```swift
// 1. 新建 SyncCoordinator.swift
import Foundation
import SwiftData
import Combine

/// iCloud 同步协调器（应用单例）
@MainActor
final class SyncCoordinator: ObservableObject {
    static let shared = SyncCoordinator()

    @Published var isSyncing = false
    @Published var syncProgress: String = ""
    @Published var lastSyncTime: Date?

    private var syncManager: iCloudSyncManager?
    private var pendingSync: Task<Void, Never>?
    private var modelContext: ModelContext?

    private init() {
        // 加载最后同步时间
        if let timestamp = UserDefaults.standard.object(forKey: "lastSyncTime") as? Date {
            self.lastSyncTime = timestamp
        }
    }

    /// 初始化同步管理器
    func setup(modelContext: ModelContext) {
        self.modelContext = modelContext

        // 如果 iCloud 已开启，初始化 syncManager
        if UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") {
            syncManager = iCloudSyncManager(modelContext: modelContext)
        }
    }

    /// 执行完整同步（去重）
    func performFullSync() async {
        // ✅ 如果正在同步，等待完成
        if isSyncing {
            print("⚠️ 同步正在进行中，跳过重复请求")
            return
        }

        guard UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") else {
            return
        }

        guard let modelContext = modelContext else {
            print("❌ ModelContext 未初始化")
            return
        }

        // ✅ 取消之前的待处理同步
        pendingSync?.cancel()

        isSyncing = true

        pendingSync = Task { @MainActor in
            do {
                if syncManager == nil {
                    syncManager = iCloudSyncManager(modelContext: modelContext)
                }

                let result = try await syncManager?.performFullSync()

                lastSyncTime = Date()
                UserDefaults.standard.set(lastSyncTime, forKey: "lastSyncTime")

                print("✅ 同步完成: \(result?.summary ?? "")")
            } catch {
                print("❌ 同步失败: \(error.localizedDescription)")
            }

            isSyncing = false
        }

        await pendingSync?.value
    }

    /// 上传单个片段（去重）
    func uploadSnippet(_ snippet: Snippet) async {
        guard UserDefaults.standard.bool(forKey: "iCloudSyncEnabled"),
              let modelContext = modelContext else {
            return
        }

        do {
            if syncManager == nil {
                syncManager = iCloudSyncManager(modelContext: modelContext)
            }

            try await syncManager?.uploadSnippet(snippet)
            print("✅ 片段已上传: \(snippet.title)")
        } catch {
            print("❌ 上传失败: \(error.localizedDescription)")
        }
    }

    /// 删除云端记录
    func deleteCloudRecord(recordName: String) async throws {
        guard UserDefaults.standard.bool(forKey: "iCloudSyncEnabled"),
              let modelContext = modelContext else {
            return
        }

        if syncManager == nil {
            syncManager = iCloudSyncManager(modelContext: modelContext)
        }

        try await syncManager?.deleteCloudRecord(recordName: recordName)
    }

    /// 开启 iCloud 同步
    func enableSync() async {
        guard let modelContext = modelContext else { return }

        UserDefaults.standard.set(true, forKey: "iCloudSyncEnabled")
        syncManager = iCloudSyncManager(modelContext: modelContext)

        await performFullSync()
    }

    /// 关闭 iCloud 同步
    func disableSync() {
        UserDefaults.standard.set(false, forKey: "iCloudSyncEnabled")
        syncManager = nil
        pendingSync?.cancel()
        pendingSync = nil
    }
}

// 2. 修改各组件使用 SyncCoordinator

// ContentView.swift
.task {
    guard !hasPerformedStartupSync else { return }
    hasPerformedStartupSync = true
    await SyncCoordinator.shared.performFullSync()
}

// SnippetListView.swift
private func addNewSnippet() {
    let newSnippet = Snippet()
    modelContext.insert(newSnippet)
    try? modelContext.save()

    Task {
        await SyncCoordinator.shared.uploadSnippet(newSnippet)
    }
}

// SettingsViewModel.swift
func manualSync() async {
    await SyncCoordinator.shared.performFullSync()
}
```

**优点**:
- 集中管理所有同步操作
- 自动去重和序列化
- 全局可访问
- 易于测试和调试

**缺点**: 需要重构现有代码

---

## 总结

### 修复优先级

| 优先级 | 问题 | 难度 | 预计时间 |
|--------|------|------|---------|
| 🔴 必须 | #1 线程安全 | 中 | 30分钟 |
| 🔴 必须 | #2 删除回滚风险 | 低 | 20分钟 |
| 🔴 必须 | #3 多容器风险 | 中 | 40分钟 |
| 🟡 应该 | #4 进度UI未连接 | 低 | 15分钟 |
| 🟡 应该 | #5 部分失败处理 | 中 | 30分钟 |
| 🟡 应该 | #6 同步触发点集中 | 高 | 60分钟 |

**总计**: 约 3 小时

### 建议实施顺序

1. **第一轮**（必须修复，约1.5小时）
   - 问题3：多容器风险（影响数据一致性）
   - 问题1：线程安全（影响稳定性）
   - 问题2：删除回滚风险（影响用户体验）

2. **第二轮**（应该修复，约1.5小时）
   - 问题4：进度UI（快速见效）
   - 问题5：部分失败（提升可靠性）
   - 问题6：同步协调器（长期架构改进）

---

请告知您想先修复哪几个问题，我将立即开始实施。
