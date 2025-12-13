# QuickClip iCloud 同步功能实现方案

## 一、需求总结

1. ✅ 在设置中添加iCloud开关（默认关闭）
2. ✅ 开启时：加载iCloud数据到本地 + 上传本地数据到iCloud（冲突处理复用导入逻辑）
3. ✅ 开启状态下：本地增删操作自动同步到iCloud
4. ✅ 关闭后：停止同步，本地和iCloud数据独立
5. ✅ 添加手动同步按钮：强制双向同步

---

## 二、技术方案设计

### 2.1 核心架构

```
┌────────────────────────────────────────────────────────────────┐
│                       用户操作层                                 │
│  SettingsView (iCloud Toggle + Manual Sync Button)            │
└──────────────────┬─────────────────────────────────────────────┘
                   │
┌──────────────────▼─────────────────────────────────────────────┐
│                    业务逻辑层                                    │
│  SettingsViewModel                                             │
│  ├─ iCloudSyncEnabled: Bool (UserDefaults持久化)              │
│  ├─ enableiCloudSync()  → 初始双向同步                        │
│  ├─ disableiCloudSync() → 停止监听                             │
│  └─ manualSync()        → 手动双向同步                         │
└──────────────────┬─────────────────────────────────────────────┘
                   │
┌──────────────────▼─────────────────────────────────────────────┐
│                  iCloud同步引擎层                                │
│  iCloudSyncManager (新建)                                      │
│  ├─ CloudKit操作: uploadSnippet/downloadSnippets/deleteSnippet│
│  ├─ 冲突处理: 复用SettingsViewModel导入逻辑                    │
│  ├─ 变化监听: 监听SwiftData变化 + CloudKit远程通知             │
│  └─ 同步状态管理: 防止循环同步                                 │
└──────────────────┬─────────────────────────────────────────────┘
                   │
┌──────────────────▼─────────────────────────────────────────────┐
│                   数据存储层                                     │
│  ├─ 本地: SwiftData (Snippet Model)                           │
│  └─ 云端: CloudKit (CKRecord "Snippet" recordType)            │
└────────────────────────────────────────────────────────────────┘
```

---

## 三、实现细节

### 3.1 新增文件：iCloudSyncManager.swift

**职责**：
- CloudKit CRUD操作（创建、读取、更新、删除记录）
- 监听本地SwiftData变化（通过ModelContext通知）
- 监听远程CloudKit变化（CKDatabaseSubscription）
- 防止循环同步（标记位：isSyncing）

**关键API**：
```swift
@MainActor
final class iCloudSyncManager: ObservableObject {
    private let container: CKContainer
    private let privateDatabase: CKDatabase
    private var modelContext: ModelContext

    // 防止循环同步
    private var isSyncing = false

    // MARK: - 公开接口
    func performInitialSync() async throws -> SyncResult
    func uploadSnippet(_ snippet: Snippet) async throws
    func deleteSnippet(recordID: CKRecord.ID) async throws
    func downloadAllSnippets() async throws -> [SnippetCloudRecord]
    func enableRealtimeSync()
    func disableRealtimeSync()

    // MARK: - 内部实现
    private func setupCloudKitSubscription() async throws
    private func handleLocalChange(_ notification: Notification)
    private func handleRemoteChange(_ notification: CKNotification)
}

struct SnippetCloudRecord {
    let recordID: CKRecord.ID
    let title: String
    let content: String
    let shortcutKey: String?
    let showInMenuBar: Bool
    let createdAt: Date
    let updatedAt: Date
}
```

**CloudKit Record Schema**：
```
RecordType: "Snippet"
Fields:
  - id: String (Snippet.id.uuidString)
  - title: String
  - content: String
  - shortcutKey: String (可选)
  - showInMenuBar: Int64 (1/0)
  - createdAt: Date
  - updatedAt: Date
```

---

### 3.2 扩展 Snippet.swift

**新增属性**（可选，用于优化同步性能）：
```swift
@Model
final class Snippet {
    // ... 现有属性 ...

    // iCloud同步相关
    var cloudRecordID: String?        // CKRecord.recordID.recordName
    var lastSyncedAt: Date?           // 最后同步时间
}
```

**注意**：这两个属性是**可选的优化项**，不影响核心功能。如果不添加，每次同步都需要遍历所有记录匹配。

---

### 3.3 扩展 SettingsViewModel.swift

**新增属性**：
```swift
@MainActor
final class SettingsViewModel: ObservableObject {
    // ... 现有属性 ...

    // iCloud同步相关
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
    @Published var lastSyncTime: Date?

    private var syncManager: iCloudSyncManager?

    // MARK: - 初始化
    init(...) {
        // ... 现有代码 ...
        self.iCloudSyncEnabled = UserDefaults.standard.bool(forKey: "iCloudSyncEnabled")
    }
}
```

**新增方法**：
```swift
// 1. 开启iCloud同步
private func enableiCloudSync() async {
    guard let modelContext = modelContext else { return }

    isSyncing = true
    statusMessage = "Syncing with iCloud..."

    do {
        // 初始化SyncManager
        syncManager = iCloudSyncManager(modelContext: modelContext)

        // 执行初始同步
        let result = try await syncManager?.performInitialSync()

        // 启动实时监听
        syncManager?.enableRealtimeSync()

        lastSyncTime = Date()
        statusMessage = "iCloud sync enabled. \(result?.summary ?? "")"
    } catch {
        iCloudSyncEnabled = false  // 失败时自动关闭
        statusMessage = "Failed to enable iCloud: \(error.localizedDescription)"
    }

    isSyncing = false
}

// 2. 关闭iCloud同步
private func disableiCloudSync() {
    syncManager?.disableRealtimeSync()
    syncManager = nil
    statusMessage = "iCloud sync disabled"
}

// 3. 手动同步
func manualSync() async {
    guard iCloudSyncEnabled, let syncManager = syncManager else {
        statusMessage = "iCloud sync is not enabled"
        return
    }

    isSyncing = true
    statusMessage = "Syncing..."

    do {
        let result = try await syncManager.performInitialSync()
        lastSyncTime = Date()
        statusMessage = "Manual sync completed. \(result.summary)"
    } catch {
        statusMessage = "Sync failed: \(error.localizedDescription)"
    }

    isSyncing = false
}
```

---

### 3.4 扩展 SettingsView.swift

**UI新增内容**（在现有3个按钮后添加）：

```swift
var body: some View {
    VStack(spacing: 0) {
        // ... 现有标题栏 ...

        // ... 现有3个按钮 ...

        // === 新增：iCloud同步区域 ===
        Divider()
            .padding(.vertical, 12)

        // iCloud开关
        HStack {
            Image(systemName: "icloud")
                .font(.system(size: 20))
                .foregroundColor(.blue)

            Text("iCloud Sync")
                .font(.system(size: 14))

            Spacer()

            Toggle("", isOn: $viewModel.iCloudSyncEnabled)
                .toggleStyle(.switch)
                .labelsHidden()
                .disabled(viewModel.isSyncing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)

        // 手动同步按钮
        if viewModel.iCloudSyncEnabled {
            HStack {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 18))
                    .foregroundColor(.secondary)

                Text("Manual Sync")
                    .font(.system(size: 14))

                Spacer()

                Button(viewModel.isSyncing ? "Syncing..." : "Sync Now") {
                    Task {
                        await viewModel.manualSync()
                    }
                }
                .disabled(viewModel.isSyncing)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)

            // 最后同步时间
            if let lastSync = viewModel.lastSyncTime {
                Text("Last synced: \(lastSync, formatter: dateFormatter)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .padding(.horizontal, 20)
                    .padding(.top, 4)
            }
        }

        // ... 现有状态消息 ...
    }
    .frame(width: 520, height: iCloudSyncEnabled ? 420 : 360)  // 动态高度
}

private var dateFormatter: DateFormatter {
    let formatter = DateFormatter()
    formatter.dateStyle = .short
    formatter.timeStyle = .short
    return formatter
}
```

---

### 3.5 冲突处理逻辑（复用现有机制）

**与导入JSON相同的策略**：

```swift
// 在iCloudSyncManager的downloadAllSnippets后，调用合并逻辑
func mergeCloudSnippets(_ cloudRecords: [SnippetCloudRecord]) -> MergeResult {
    guard let modelContext = modelContext else { return .init() }

    // 获取现有数据
    let descriptor = FetchDescriptor<Snippet>()
    let existingSnippets = (try? modelContext.fetch(descriptor)) ?? []

    // 1. 构建内容集合（检测重复）
    let existingContents = Set(existingSnippets.map(\.content))

    // 2. 构建快捷键集合（检测冲突）
    var usedShortcuts = Set<String>()
    for snippet in existingSnippets {
        if let key = snippet.shortcutKey, !key.isEmpty {
            usedShortcuts.insert(key)
        }
    }

    var importedCount = 0
    var skippedCount = 0
    var clearedShortcutCount = 0

    for record in cloudRecords {
        // 内容重复检查
        if existingContents.contains(record.content) {
            skippedCount += 1
            continue
        }

        // 快捷键冲突处理
        var resolvedShortcut = record.shortcutKey
        if let key = resolvedShortcut, !key.isEmpty {
            if usedShortcuts.contains(key) {
                resolvedShortcut = nil  // 清除冲突的快捷键
                clearedShortcutCount += 1
            } else {
                usedShortcuts.insert(key)
            }
        }

        // 创建新Snippet
        let newSnippet = Snippet(
            title: record.title,
            content: record.content,
            shortcutKey: resolvedShortcut,
            showInMenuBar: record.showInMenuBar
        )
        newSnippet.createdAt = record.createdAt
        newSnippet.updatedAt = record.updatedAt
        newSnippet.cloudRecordID = record.recordID.recordName

        modelContext.insert(newSnippet)
        importedCount += 1
    }

    try? modelContext.save()

    // 发送通知更新
    NotificationCenter.default.post(name: NSNotification.Name("HotKeysNeedUpdate"), object: nil)
    NotificationCenter.default.post(name: NSNotification.Name("MenuBarNeedUpdate"), object: nil)

    return MergeResult(
        imported: importedCount,
        skipped: skippedCount,
        clearedShortcuts: clearedShortcutCount
    )
}
```

---

### 3.6 实时同步机制

**监听本地变化**：
```swift
// 在iCloudSyncManager中
func enableRealtimeSync() {
    // 监听SwiftData变化通知
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleLocalDataChange),
        name: NSManagedObjectContext.didSaveObjectsNotification,  // SwiftData底层用CoreData
        object: nil
    )
}

@objc private func handleLocalDataChange(_ notification: Notification) {
    guard !isSyncing else { return }  // 防止循环同步

    Task {
        // 解析变化的对象
        if let inserted = notification.userInfo?[NSInsertedObjectsKey] as? Set<NSManagedObject> {
            // 上传新增的Snippet
        }
        if let updated = notification.userInfo?[NSUpdatedObjectsKey] as? Set<NSManagedObject> {
            // 更新对应的CKRecord
        }
        if let deleted = notification.userInfo?[NSDeletedObjectsKey] as? Set<NSManagedObject> {
            // 删除对应的CKRecord
        }
    }
}
```

**监听远程变化**（可选进阶功能）：
```swift
// 使用CKDatabaseSubscription
func setupCloudKitSubscription() async throws {
    let subscription = CKDatabaseSubscription(subscriptionID: "snippet-changes")

    let notificationInfo = CKSubscription.NotificationInfo()
    notificationInfo.shouldSendContentAvailable = true
    subscription.notificationInfo = notificationInfo

    try await privateDatabase.save(subscription)
}
```

---

## 四、实现步骤建议

### Phase 1: 基础CloudKit集成（最小可用版本）
1. ✅ 创建 `iCloudSyncManager.swift`
2. ✅ 实现基本的CloudKit CRUD操作
3. ✅ 实现 `performInitialSync()` 方法（双向同步）
4. ✅ 实现冲突处理逻辑（复用导入逻辑）

### Phase 2: UI集成
5. ✅ 扩展 `SettingsViewModel` 添加iCloud开关
6. ✅ 扩展 `SettingsView` 添加UI控件
7. ✅ 实现手动同步功能

### Phase 3: 实时同步
8. ✅ 实现本地数据变化监听
9. ✅ 实现自动上传逻辑
10. ✅ （可选）实现远程变化监听

### Phase 4: 优化
11. ✅ 添加错误处理和用户提示
12. ✅ 添加同步状态指示器
13. ✅ 性能优化（批量上传、增量同步等）

---

## 五、关键技术点

### 5.1 CloudKit配置检查清单
- ✅ iCloud容器已创建：`iCloud.io.0os.QuickClip`
- ✅ Entitlements已配置：`com.apple.developer.icloud-services` = CloudKit
- ⚠️ 需要在CloudKit Dashboard创建Record Type："Snippet"
- ⚠️ 需要测试网络权限（沙箱环境下）

### 5.2 防止循环同步
```swift
// 关键标记位
private var isSyncing = false

func uploadSnippet(_ snippet: Snippet) async throws {
    isSyncing = true
    defer { isSyncing = false }

    // CloudKit上传操作
    // ...
}
```

### 5.3 错误处理
```swift
enum SyncError: LocalizedError {
    case notSignedIn
    case networkUnavailable
    case quotaExceeded
    case conflictResolutionFailed

    var errorDescription: String? {
        switch self {
        case .notSignedIn:
            return "Not signed in to iCloud"
        case .networkUnavailable:
            return "Network unavailable"
        case .quotaExceeded:
            return "iCloud storage quota exceeded"
        case .conflictResolutionFailed:
            return "Failed to resolve data conflicts"
        }
    }
}
```

---

## 六、测试场景

### 6.1 基本功能测试
- [ ] 开启iCloud同步（首次）
- [ ] 本地有数据，云端无数据 → 上传
- [ ] 本地无数据，云端有数据 → 下载
- [ ] 本地和云端都有数据 → 冲突处理

### 6.2 冲突处理测试
- [ ] 内容完全相同 → 跳过
- [ ] 快捷键冲突 → 清除快捷键后导入
- [ ] 快捷键无冲突 → 正常导入

### 6.3 实时同步测试
- [ ] 本地新增Snippet → 自动上传
- [ ] 本地删除Snippet → 云端删除
- [ ] 本地修改Snippet → 云端更新

### 6.4 开关状态测试
- [ ] 关闭iCloud → 停止同步
- [ ] 重新开启 → 执行双向同步

### 6.5 多设备测试（进阶）
- [ ] 设备A新增 → 设备B自动接收
- [ ] 设备A删除 → 设备B自动删除

---

## 七、风险与注意事项

### 7.1 技术风险
⚠️ **SwiftData与CloudKit集成**：SwiftData原生不支持CloudKit，需要手动实现同步逻辑
⚠️ **网络异常处理**：需要队列化失败的操作，支持重试
⚠️ **并发冲突**：多设备同时修改同一记录时的冲突解决

### 7.2 用户体验风险
⚠️ **首次同步慢**：数据量大时可能需要较长时间
⚠️ **iCloud配额**：用户iCloud存储空间不足时的处理
⚠️ **登录状态**：未登录iCloud时的友好提示

### 7.3 代码规范
✅ 所有注释使用中文
✅ UI文案使用英文（专业风格）
✅ 错误消息使用英文

---

## 八、文件清单总结

### 新建文件
- `/QuickClip/iCloudSyncManager.swift` (约300行)

### 修改文件
- `/QuickClip/Snippet.swift` (+2属性，可选)
- `/QuickClip/SettingsViewModel.swift` (+150行)
- `/QuickClip/SettingsView.swift` (+60行)

### 配置文件
- CloudKit Dashboard配置（Web操作，非代码）

---

## 九、方案优势

✅ **复用现有逻辑**：冲突处理完全复用导入JSON的成熟代码
✅ **架构清晰**：独立的SyncManager，职责单一
✅ **可渐进实现**：可以分阶段实现（先手动同步，再实时同步）
✅ **用户可控**：开关可随时切换，手动同步提供兜底方案
✅ **符合规范**：注释中文+文案英文，符合CLAUDE.md要求

---

## 十、预估工作量

| 阶段 | 工作内容 | 复杂度 |
|------|---------|--------|
| Phase 1 | 基础CloudKit集成 | 中 |
| Phase 2 | UI集成 | 低 |
| Phase 3 | 实时同步 | 中高 |
| Phase 4 | 优化与测试 | 中 |

**建议实现顺序**：Phase 1 → Phase 2 → （测试）→ Phase 3 → Phase 4

---

## 十一、待确认问题

❓ 是否需要实现远程变化监听（多设备实时同步）？
❓ 是否需要添加 `cloudRecordID` 和 `lastSyncedAt` 字段到Snippet模型？
❓ 同步失败时是否需要持久化失败队列（支持离线操作）？
❓ 是否需要在UI上显示同步进度（数量/百分比）？

---

请您review这个方案，确认后我将开始实现。如有任何疑问或需要调整的地方，请告诉我！
