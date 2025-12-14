# QuickClip iCloud 同步方案设计文档

## 1. 技术栈

### 1.1 核心框架
- **CloudKit**: Apple 原生云存储服务
  - 使用 `CKContainer` 和 `CKDatabase` 管理云端数据
  - 容器标识符: `iCloud.io.0os.QuickClip`
  - 使用私有数据库 (`privateCloudDatabase`)

- **SwiftData**: 本地数据持久化
  - 数据模型: `Snippet`
  - 禁用了 SwiftData 自动 CloudKit 集成 (QuickClipApp.swift:21-26)

- **Combine**: 响应式编程框架
  - 用于绑定同步进度到 UI (SettingsViewModel.swift:37, 249-251)

### 1.2 现代 CloudKit API
- `privateDatabase.records(matching:desiredKeys:)` - 查询记录
- `privateDatabase.records(continuingMatchFrom:desiredKeys:)` - 分页查询
- `privateDatabase.records(for:desiredKeys:)` - 批量获取记录
- `privateDatabase.record(for:)` - 获取单个记录
- `privateDatabase.save(_:)` - 保存记录
- `privateDatabase.deleteRecord(withID:)` - 删除记录

---

## 2. 核心文件结构

### 2.1 数据模型
**文件**: `Snippet.swift`
- **关键字段**:
  - `cloudRecordID: String?` (22行) - CloudKit 记录 ID
  - `lastSyncedAt: Date?` (23行) - 最后同步时间
  - `needsSync: Bool` (24行) - 是否需要同步标记

### 2.2 同步引擎
**文件**: `iCloudSyncManager.swift` (442行)

**核心结构**:
- **SnippetCloudRecord** (14-23行) - 云端记录数据结构
- **SyncResult** (26-42行) - 同步结果统计
- **SyncError** (45-66行) - 同步错误枚举

**关键方法**:
| 方法名 | 行数 | 功能 |
|--------|------|------|
| `checkAccountStatus()` | 95-112 | 检查 iCloud 账户状态 |
| `performFullSync()` | 115-156 | 执行完整双向同步 |
| `uploadSnippet(_:)` | 159-177 | 上传单个新片段 |
| `updateSnippet(_:)` | 187-219 | 更新单个已有片段 |
| `deleteCloudRecord(recordName:)` | 180-184 | 删除云端记录 |
| `downloadAllSnippets()` | 223-263 | 下载所有云端片段 |
| `uploadLocalSnippets()` | 297-327 | 上传本地片段和已修改片段 |
| `batchUploadNewSnippets(_:allSnippets:)` | 330-384 | 批量上传新片段 |
| `batchUpdateExistingSnippets(_:)` | 387-457 | 批量更新已有片段 |
| `mergeCloudSnippets(_:)` | 477-485 | 合并云端数据到本地 |

### 2.3 同步控制层
**文件**: `SettingsViewModel.swift` (394行)

**关键属性**:
| 属性名 | 行数 | 功能 |
|--------|------|------|
| `iCloudSyncEnabled: Bool` | 21-30 | iCloud 开关状态 |
| `isSyncing: Bool` | 32 | 是否正在同步 |
| `syncProgress: String` | 33 | 同步进度文本 |
| `lastSyncTime: Date?` | 34 | 最后同步时间 |
| `syncManager: iCloudSyncManager?` | 36 | 同步管理器实例 |
| `progressCancellable: AnyCancellable?` | 37 | Combine 订阅句柄 |

**关键方法**:
| 方法名 | 行数 | 功能 |
|--------|------|------|
| `enableiCloudSync()` | 234-270 | 开启 iCloud 同步 |
| `disableiCloudSync()` | 273-281 | 关闭 iCloud 同步 |
| `manualSync()` | 284-328 | 手动同步 |
| `performStartupSyncIfEnabled()` | 331-358 | 启动时自动同步 |
| `syncImportedSnippetsToiCloud(_:)` | 361-393 | 导入后同步到云端 |

### 2.4 UI 层
**文件**: `SettingsView.swift` (131-232行)
- iCloud 开关 (141行)
- 手动同步按钮 (159-167行)
- 同步进度显示 (171-180行)
- 最后同步时间 (183-192行)

**文件**: `SnippetDetailView.swift` (221-267行)
- 延迟同步逻辑 (`markNeedsSyncAndScheduleUpload()`)
- 监听字段变化 (221-232行)

**文件**: `SnippetListView.swift`
- 新增片段上传 (`syncNewSnippetToiCloud()`, 195-210行)
- 删除片段云端优先 (`deleteSnippet()`, 136-178行)

### 2.5 启动入口
**文件**: `ContentView.swift` (56-69行)
- App 启动时触发自动同步

---

## 3. 同步逻辑流程图

### 3.1 完整同步流程 (启动同步 / 手动同步)

```
┌─────────────────────────────────────────────────┐
│   用户开启 iCloud / 点击手动同步 / App 启动     │
└─────────────────┬───────────────────────────────┘
                  │
                  ▼
      ┌───────────────────────┐
      │ 1. 检查 iCloud 账户   │
      │   checkAccountStatus()│
      └───────────┬───────────┘
                  │
                  ▼
      ┌───────────────────────┐
      │ 2. 下载云端所有片段   │
      │   downloadAllSnippets()│
      │   (使用 CKQuery 分页) │
      └───────────┬───────────┘
                  │
                  ▼
      ┌───────────────────────┐
      │ 3. 合并到本地数据库   │
      │   mergeCloudSnippets()│
      │   - 跳过重复内容      │
      │   - 处理快捷键冲突    │
      └───────────┬───────────┘
                  │
                  ▼
      ┌───────────────────────────────┐
      │ 4. 上传本地片段              │
      │   uploadLocalSnippets()      │
      │                              │
      │   4.1 筛选需要同步的片段:    │
      │       - cloudRecordID == nil │
      │       - needsSync == true    │
      │                              │
      │   4.2 批量上传新片段:        │
      │       batchUploadNewSnippets()│
      │       (创建新 CKRecord)       │
      │                              │
      │   4.3 批量更新已有片段:      │
      │       batchUpdateExistingSnippets()│
      │       (先获取记录再修改)     │
      └───────────┬───────────────────┘
                  │
                  ▼
      ┌───────────────────────┐
      │ 5. 更新同步状态       │
      │   - needsSync = false │
      │   - lastSyncedAt = now│
      └───────────┬───────────┘
                  │
                  ▼
          ┌───────────────┐
          │  同步完成     │
          └───────────────┘
```

### 3.2 延迟同步流程 (修改片段后 3 秒)

```
┌─────────────────────────────────────┐
│  用户修改片段字段                   │
│  (title/content/shortcutKey/        │
│   showInMenuBar)                    │
└─────────────┬───────────────────────┘
              │
              ▼
  ┌────────────────────────────┐
  │ onChange 监听触发          │
  │ markNeedsSyncAndScheduleUpload() │
  └────────────┬───────────────┘
              │
              ▼
  ┌────────────────────────────┐
  │ 1. 标记 needsSync = true   │
  │ 2. 保存到本地 SwiftData    │
  └────────────┬───────────────┘
              │
              ▼
  ┌────────────────────────────┐
  │ 检查 iCloud 是否开启?      │
  └────┬───────────────┬────────┘
       │ NO            │ YES
       │               │
       ▼               ▼
   ┌──────┐   ┌────────────────────┐
   │ 结束 │   │ 取消之前的延迟任务 │
   └──────┘   │ syncWorkItem?.cancel()│
              └────────┬───────────┘
                       │
                       ▼
              ┌────────────────────┐
              │ 创建新的延迟任务   │
              │ 3 秒后执行         │
              └────────┬───────────┘
                       │
                       │ (3 秒内无新修改)
                       │
                       ▼
              ┌────────────────────┐
              │ 执行同步:          │
              │ updateSnippet()    │
              │ 1. 获取云端记录    │
              │ 2. 修改字段        │
              │ 3. 保存到 CloudKit │
              └────────┬───────────┘
                       │
                       ▼
              ┌────────────────────┐
              │ needsSync = false  │
              │ lastSyncedAt = now │
              └────────────────────┘
```

### 3.3 新增片段流程

```
┌─────────────────────┐
│  用户点击新增按钮   │
└──────────┬──────────┘
           │
           ▼
┌──────────────────────┐
│ 1. 创建 Snippet 对象 │
│    insert() 到 SwiftData│
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ 2. 保存到本地数据库  │
│    modelContext.save()│
└──────────┬───────────┘
           │
           ▼
┌──────────────────────┐
│ 检查 iCloud 是否开启?│
└────┬─────────────┬───┘
     │ NO          │ YES
     │             │
     ▼             ▼
 ┌──────┐  ┌──────────────────┐
 │ 结束 │  │ syncNewSnippetToiCloud()│
 └──────┘  └──────────┬───────┘
                      │
                      ▼
           ┌──────────────────────┐
           │ uploadSnippet()      │
           │ 1. 创建 CKRecord     │
           │ 2. 上传到 CloudKit   │
           │ 3. 保存 cloudRecordID│
           │ 4. needsSync = false │
           └──────────────────────┘
```

### 3.4 删除片段流程

```
┌─────────────────────┐
│  用户确认删除片段   │
└──────────┬──────────┘
           │
           ▼
┌──────────────────────────────┐
│ 检查是否有 cloudRecordID?   │
│ 且 iCloud 是否开启?          │
└────┬──────────────────┬──────┘
     │ NO               │ YES
     │                  │
     ▼                  ▼
┌────────────┐  ┌───────────────────────┐
│ 直接删除    │  │ 1. 标记 isDeleting    │
│ 本地数据    │  │ 2. 显示 loading       │
└────────────┘  └───────────┬───────────┘
                            │
                            ▼
                   ┌────────────────────┐
                   │ deleteCloudRecord()│
                   │ 删除云端记录       │
                   └────────┬───────────┘
                            │
                   ┌────────┴────────┐
                   │                 │
                   ▼                 ▼
            ┌──────────┐      ┌──────────────┐
            │  成功    │      │    失败      │
            └────┬─────┘      └──────┬───────┘
                 │                   │
                 ▼                   ▼
     ┌──────────────────┐   ┌────────────────┐
     │ 删除本地数据     │   │ 显示错误提示   │
     │ 移除 loading     │   │ 保留本地数据   │
     └──────────────────┘   │ 移除 loading   │
                            └────────────────┘
```

---

## 4. 同步规则

### 4.1 触发同步的时机

| 操作 | 同步方式 | 触发位置 |
|------|---------|---------|
| **App 启动** | 完整同步 | ContentView.swift:62-67 |
| **开启 iCloud 开关** | 完整同步 | SettingsViewModel.swift:234-270 |
| **点击手动同步** | 完整同步 | SettingsViewModel.swift:284-328 |
| **新增片段** | 立即上传 | SnippetListView.swift:131, 195-210 |
| **修改片段** | 延迟 3 秒上传 | SnippetDetailView.swift:221-267 |
| **删除片段** | 云端优先删除 | SnippetListView.swift:136-178 |
| **导入 JSON** | 批量上传 | SettingsViewModel.swift:198-200 |

### 4.2 冲突解决策略

#### 4.2.1 内容冲突
**规则**: 以 `content` 字段为唯一性标识

**处理方式**:
- 下载云端数据时，检查本地是否已存在相同 `content` 的片段
- 如果存在，跳过该云端记录 (`mergeCloudSnippets()` 375-378行)
- 统计信息中 `skipped` 计数器 +1

**代码位置**: iCloudSyncManager.swift:375-378

#### 4.2.2 快捷键冲突
**规则**: 一个快捷键只能分配给一个片段

**处理方式**:
1. 维护 `usedShortcuts` 集合记录已使用的快捷键
2. 导入云端片段时，如果快捷键已被占用：
   - 将该片段的 `shortcutKey` 设为 `nil`
   - 统计信息中 `clearedShortcuts` 计数器 +1
3. 导入 JSON 时应用相同逻辑

**代码位置**:
- iCloudSyncManager.swift:380-392
- SettingsViewModel.swift:167-177

#### 4.2.3 记录 ID 冲突
**规则**: 以 `snippetID` (Snippet.id.uuidString) 为云端唯一标识

**处理方式**:
- 下载云端数据时，检查本地是否已存在相同 `snippetID` 的片段
- 如果存在，跳过该云端记录 (`mergeCloudSnippets()` 368-372行)

**代码位置**: iCloudSyncManager.swift:368-372

### 4.3 数据同步方向

#### 4.3.1 完整同步 (双向)
```
云端 → 本地: 下载所有云端记录，合并到本地
本地 → 云端: 上传所有未同步的本地记录
```

**流程**:
1. 下载云端所有片段
2. 合并到本地 (跳过重复内容和 snippetID)
3. 上传本地新片段 (`cloudRecordID == nil`)
4. 上传本地已修改片段 (`needsSync == true`)

**代码位置**: iCloudSyncManager.swift:115-156

#### 4.3.2 单向上传
```
本地 → 云端: 立即上传或延迟 3 秒上传
```

**场景**:
- 新增片段: 立即上传
- 修改片段: 延迟 3 秒上传 (debounce)
- 导入 JSON: 批量上传

### 4.4 needsSync 标记规则

#### 4.4.1 设置为 true 的时机
| 场景 | 位置 |
|------|------|
| 用户修改片段任何字段 | SnippetDetailView.swift:237 |

#### 4.4.2 设置为 false 的时机
| 场景 | 位置 |
|------|------|
| 新片段上传成功 | iCloudSyncManager.swift:172 |
| 单个片段更新成功 | iCloudSyncManager.swift:214 |
| 批量上传新片段成功 | iCloudSyncManager.swift:375 |
| 批量更新片段成功 | iCloudSyncManager.swift:447 |

**核心原则**:
- ✅ 只要上传/更新成功，立即清除 `needsSync` 标记
- ✅ 如果上传/更新失败，保持 `needsSync = true`，等待下次完整同步重试
- ✅ 完整同步结束后，所有成功上传的片段 `needsSync` 都为 `false`

### 4.5 批量操作限制

**CloudKit 限制**: 每批次最多 400 条记录

**实现方式**:
- 使用 `stride(from:to:by:)` 分批处理
- `batchSize = 400` (iCloudSyncManager.swift:332, 390)

**代码位置**:
- iCloudSyncManager.swift:332-366 (批量上传新片段)
- iCloudSyncManager.swift:390-454 (批量更新片段)

### 4.6 错误处理

#### 4.6.1 账户状态错误
**错误类型**: `SyncError.notSignedIn`, `SyncError.permissionDenied`

**处理方式**:
- 自动关闭 iCloud 开关
- 显示错误信息给用户

**代码位置**: SettingsViewModel.swift:262-266

#### 4.6.2 网络错误
**错误类型**: `SyncError.networkUnavailable`

**处理方式**:
- 保持 `needsSync` 标记
- 下次有网络时重试

**代码位置**: iCloudSyncManager.swift:427-439

#### 4.6.3 云端删除失败
**处理方式**:
- 显示错误对话框
- 保留本地数据，不删除
- 用户可以稍后重试

**代码位置**: SnippetListView.swift:164-172

---

## 5. 数据字段映射

### 5.1 Snippet (SwiftData) ↔ CKRecord (CloudKit)

| SwiftData 字段 | CloudKit 字段 | 类型 | 说明 |
|---------------|--------------|------|------|
| `id` | `snippetID` | String | UUID.uuidString |
| `title` | `title` | String | 片段标题 |
| `content` | `content` | String | 片段内容 |
| `shortcutKey` | `shortcutKey` | String? | 快捷键组合 |
| `showInMenuBar` | `showInMenuBar` | Int64 | Bool → Int (1/0) |
| `createdAt` | `createdAt` | Date | 创建时间 |
| `updatedAt` | `updatedAt` | Date | 更新时间 |
| `cloudRecordID` | - | String? | 存储 recordName |
| `lastSyncedAt` | - | Date? | 最后同步时间 |
| `needsSync` | - | Bool | 是否需要同步 |

**转换代码位置**:
- SwiftData → CKRecord: iCloudSyncManager.swift:492-502
- CKRecord → SnippetCloudRecord: iCloudSyncManager.swift:266-294

### 5.2 CloudKit 记录类型

**Record Type**: `Snippet`

**Zone**: `_defaultZone` (默认区域)

**字段定义**:
```
snippetID: String (Indexed, Queryable)
title: String
content: String
shortcutKey: String (Optional)
showInMenuBar: Int64
createdAt: Date
updatedAt: Date
```

---

## 6. 性能优化

### 6.1 Debounce 机制
**目的**: 避免频繁的网络请求

**实现**:
- 用户修改片段后，延迟 3 秒才上传
- 3 秒内继续修改，取消之前的上传任务，重新计时
- 使用 `DispatchWorkItem` 实现

**代码位置**: SnippetDetailView.swift:246-266

### 6.2 批量操作
**目的**: 减少网络请求次数

**实现**:
- 批量上传新片段 (最多 400 条/批)
- 批量更新片段 (最多 400 条/批)
- 批量获取云端记录

**代码位置**:
- iCloudSyncManager.swift:332-384 (批量上传)
- iCloudSyncManager.swift:387-457 (批量更新)

### 6.3 增量同步
**目的**: 只同步有变化的数据

**实现**:
- 使用 `needsSync` 标记跟踪修改
- 完整同步时只上传 `needsSync == true` 的片段
- 避免重复上传未修改的数据

**代码位置**: iCloudSyncManager.swift:301-304

### 6.4 进度反馈
**目的**: 提升用户体验

**实现**:
- 使用 Combine 框架实时更新同步进度
- 显示 "Downloading...", "Merging...", "Uploading..." 状态
- 显示最后同步时间

**代码位置**:
- 进度绑定: SettingsViewModel.swift:249-251
- 进度显示: SettingsView.swift:171-192

---

## 7. 安全性考虑

### 7.1 私有数据库
- 使用 CloudKit 私有数据库 (`privateCloudDatabase`)
- 数据只在用户自己的 iCloud 账户中存储
- 不会共享给其他用户

### 7.2 账户验证
- 每次同步前检查 iCloud 账户状态
- 未登录或权限不足时拒绝同步
- 代码位置: iCloudSyncManager.swift:95-112

### 7.3 数据隔离
- 每个用户的数据完全独立
- 使用 `snippetID` (UUID) 作为唯一标识
- 避免数据冲突和泄露

---

## 8. 测试场景

### 8.1 基本功能测试
1. ✅ 开启 iCloud 同步，检查是否执行完整同步
2. ✅ 关闭 iCloud 同步，检查是否停止同步
3. ✅ 新增片段，检查是否立即上传
4. ✅ 修改片段，检查是否 3 秒后上传
5. ✅ 删除片段，检查是否先删除云端再删除本地
6. ✅ 手动同步，检查是否同步所有修改

### 8.2 冲突处理测试
1. ✅ 云端和本地有相同内容的片段，检查是否跳过
2. ✅ 云端片段的快捷键本地已被占用，检查是否清除快捷键
3. ✅ 修改同一个片段多次，检查是否只上传最后一次修改

### 8.3 错误处理测试
1. ✅ 未登录 iCloud 账户，检查是否提示错误
2. ✅ 网络断开时修改片段，检查是否保持 needsSync 标记
3. ✅ 网络恢复后手动同步，检查是否成功上传
4. ✅ 删除云端失败，检查是否显示错误并保留本地数据

### 8.4 性能测试
1. ✅ 3 秒内连续修改片段 5 次，检查是否只上传 1 次
2. ✅ 批量导入 100 个片段，检查是否正确上传
3. ✅ App 启动同步 500 个片段，检查是否成功且无卡顿

---

## 9. 未来改进方向

### 9.1 增量下载
**现状**: 每次完整同步都下载所有云端记录

**改进**:
- 记录最后一次下载时间
- 只下载 `updatedAt > lastDownloadTime` 的记录
- 减少网络流量和同步时间

### 9.2 冲突解决策略优化
**现状**: 内容重复时直接跳过，快捷键冲突时清除

**改进**:
- 提供冲突解决 UI，让用户选择保留哪个版本
- 支持合并冲突 (如保留两个版本)
- 快捷键冲突时提示用户重新分配

### 9.3 后台同步
**现状**: 只在 App 运行时同步

**改进**:
- 使用 `CKSyncEngine` 实现后台同步
- 支持静默推送通知 (Silent Push)
- 云端数据变化时自动拉取更新

### 9.4 同步日志
**现状**: 只在控制台输出日志

**改进**:
- 记录同步历史到本地数据库
- 显示同步日志界面
- 支持导出同步日志用于调试

---

## 10. 关键代码索引

### 10.1 模型层
- `Snippet.swift:24` - needsSync 字段定义
- `Snippet.swift:22-23` - cloudRecordID 和 lastSyncedAt 字段

### 10.2 同步引擎
- `iCloudSyncManager.swift:115-156` - 完整同步主流程
- `iCloudSyncManager.swift:187-219` - 单个片段更新
- `iCloudSyncManager.swift:297-327` - 上传本地片段
- `iCloudSyncManager.swift:387-457` - 批量更新已有片段

### 10.3 UI 交互
- `SnippetDetailView.swift:235-267` - 延迟同步逻辑
- `SettingsView.swift:141` - iCloud 开关
- `SettingsView.swift:159-167` - 手动同步按钮
- `SnippetListView.swift:136-178` - 删除片段逻辑

### 10.4 启动入口
- `ContentView.swift:62-67` - App 启动自动同步
- `SettingsViewModel.swift:234-270` - 开启 iCloud 同步
- `SettingsViewModel.swift:331-358` - 启动时同步方法

---

## 附录：CloudKit Schema 定义

```
Record Type: Snippet
Zone: _defaultZone (Default Zone)

Fields:
├── snippetID (String, Indexed, Queryable)
├── title (String)
├── content (String)
├── shortcutKey (String, Optional)
├── showInMenuBar (Int64)
├── createdAt (Date)
└── updatedAt (Date)

Indexes:
└── recordName (System Index)

Security:
├── Read: Creator Only
├── Write: Creator Only
└── Database: Private
```

---

**文档版本**: v1.0
**最后更新**: 2025-12-13
**维护者**: QuickClip Team
