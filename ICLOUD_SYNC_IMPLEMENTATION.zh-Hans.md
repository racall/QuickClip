# QuickClip iCloud 同步实现说明（以代码为准）

> 本文档完全基于当前仓库代码整理；行号对应当前文件版本，后续代码变更可能导致行号漂移。

## 1. 何时触发同步

### 1.1 开启/关闭 iCloud 同步

- UI 入口：设置页 iCloud 开关 `Toggle("", isOn: $viewModel.iCloudSyncEnabled)`  
  `QuickClip/SettingsView.swift:141`
- 开关变更逻辑：`SettingsViewModel.iCloudSyncEnabled` 的 `didSet`  
  `QuickClip/SettingsViewModel.swift:40`
  - 开启时：`enableiCloudSync()`  
    `QuickClip/SettingsViewModel.swift:301` → `iCloudSyncManager.performFullSync()` `QuickClip/iCloudSyncManager.swift:124`
  - 关闭时：`disableiCloudSync()`  
    `QuickClip/SettingsViewModel.swift:340`

### 1.2 手动同步（设置页按钮）

- UI 入口：设置页 “Manual Sync / Sync Now” 按钮  
  `QuickClip/SettingsView.swift:151`
- 调用链：`SettingsViewModel.manualSync()`  
  `QuickClip/SettingsViewModel.swift:351` → `iCloudSyncManager.performFullSync()` `QuickClip/iCloudSyncManager.swift:124`

### 1.3 App 启动时自动同步

- 入口：`ContentView.task`  
  `QuickClip/ContentView.swift:48`
- 调用链：`SettingsViewModel.performStartupSyncIfEnabled()`  
  `QuickClip/SettingsViewModel.swift:398` → `iCloudSyncManager.performFullSync()` `QuickClip/iCloudSyncManager.swift:124`
- 前置条件：`iCloudSyncEnabled == true` 且 `isSyncing == false`  
  `QuickClip/SettingsViewModel.swift:399`

### 1.4 新建片段后立即上传

- 入口：`SnippetListView.addNewSnippet()`  
  `QuickClip/SnippetListView.swift:122`
- 调用链：`syncNewSnippetToiCloud()`  
  `QuickClip/SnippetListView.swift:196` → `iCloudSyncManager.uploadSnippet()` `QuickClip/iCloudSyncManager.swift:168`
- 前置条件：`UserDefaults("iCloudSyncEnabled") == true`  
  `QuickClip/SnippetListView.swift:198`

### 1.5 编辑片段后延迟上传（3 秒）

- 入口：详情页字段变化监听 `onChange`  
  `QuickClip/SnippetDetailView.swift:221`、`QuickClip/SnippetDetailView.swift:224`、`QuickClip/SnippetDetailView.swift:227`、`QuickClip/SnippetDetailView.swift:230`
- 调用链：`markNeedsSyncAndScheduleUpload()`  
  `QuickClip/SnippetDetailView.swift:236`
  - 先写本地：`snippet.needsSync = true` 并保存  
    `QuickClip/SnippetDetailView.swift:237`
  - 3 秒后调用：`iCloudSyncManager.updateSnippet()`  
    `QuickClip/SnippetDetailView.swift:255` → `QuickClip/iCloudSyncManager.swift:196`
- 前置条件：`UserDefaults("iCloudSyncEnabled") == true`  
  `QuickClip/SnippetDetailView.swift:242`
- 失败处理：延迟同步失败时保持 `needsSync = true`，等待下次完整同步重试  
  `QuickClip/SnippetDetailView.swift:258`

### 1.6 删除片段时优先删除云端

- 入口：列表删除 `SnippetListView.deleteSnippet(_:)`  
  `QuickClip/SnippetListView.swift:137`
- 调用链：`iCloudSyncManager.deleteCloudRecord(recordName:)`  
  `QuickClip/SnippetListView.swift:156` → `QuickClip/iCloudSyncManager.swift:189`
- 前置条件：本地有 `cloudRecordID` 且 `UserDefaults("iCloudSyncEnabled") == true`  
  `QuickClip/SnippetListView.swift:150`
- 失败处理：云端删除失败则不删除本地，仅提示  
  `QuickClip/SnippetListView.swift:165`

### 1.7 导入 JSON 后上传导入项

- 入口：`SettingsViewModel.importFromJSON()`  
  `QuickClip/SettingsViewModel.swift:196`
- 调用链：`syncImportedSnippetsToiCloud()`  
  `QuickClip/SettingsViewModel.swift:428`
  - 逐条上传：`iCloudSyncManager.uploadSnippet()`  
    `QuickClip/SettingsViewModel.swift:448` → `QuickClip/iCloudSyncManager.swift:168`

## 2. 同步相关数据字段

### 2.1 Snippet 本地字段（SwiftData）

`QuickClip/Snippet.swift:11`

- `id: UUID`：本地唯一标识（同步时也作为云端 `snippetID`）  
  `QuickClip/Snippet.swift:13`
- `updatedAt: Date`：用于冲突决策（谁更新得更晚）  
  `QuickClip/Snippet.swift:19`
- iCloud 相关：
  - `cloudRecordID: String?`：CloudKit recordName（本地记录绑定的云端记录）  
    `QuickClip/Snippet.swift:22`
  - `lastSyncedAt: Date?`：本地记录最后一次成功同步时间  
    `QuickClip/Snippet.swift:23`
  - `needsSync: Bool`：本地是否需要向云端同步（编辑后置为 true）  
    `QuickClip/Snippet.swift:24`

### 2.2 cloudRecordID 归一化规则

为避免 `cloudRecordID == ""` 这类“看似存在但实际无效”的状态导致遗漏上传，代码将空字符串/全空格视为 `nil`：  
`iCloudSyncManager.normalizedRecordName(_:)` `QuickClip/iCloudSyncManager.swift:95`

## 3. 同步时的策略（完整同步 performFullSync）

完整同步入口：`iCloudSyncManager.performFullSync()`  
`QuickClip/iCloudSyncManager.swift:124`

### 3.1 完整同步步骤

1) 账户状态检查：`checkAccountStatus()`  
`QuickClip/iCloudSyncManager.swift:104`

2) 下载云端全量数据：`downloadAllSnippets()`  
`QuickClip/iCloudSyncManager.swift:233`  
解析记录：`parseCloudKitRecord(_:)` `QuickClip/iCloudSyncManager.swift:279`

3) 合并到本地并处理冲突：`mergeCloudSnippets(_:)`  
`QuickClip/iCloudSyncManager.swift:501`

4) 上传本地需要同步的记录：`uploadLocalSnippets()`  
`QuickClip/iCloudSyncManager.swift:307`

### 3.2 冲突决策总规则（updatedAt）

冲突判定统一以 `updatedAt` 为准：
- 若本地 `updatedAt >=` 云端 `updatedAt`：本地胜出（相同时间戳也视为本地胜出）  
  `QuickClip/iCloudSyncManager.swift:606`、`QuickClip/iCloudSyncManager.swift:655`
- 若云端更新更晚：云端胜出，覆盖本地  
  `QuickClip/iCloudSyncManager.swift:625`、`QuickClip/iCloudSyncManager.swift:673`

### 3.3 合并策略（你确认的 3 条规则落地）

#### 3.3.1 规则 1：按 snippetID 匹配（本地存在同一条记录）

位置：`mergeCloudSnippets` 的“按 snippetID 处理”分支  
`QuickClip/iCloudSyncManager.swift:602`

- snippetID 命中本地后：
  - 本地胜出：若字段不一致，标记 `needsSync = true`，后续上传覆盖云端  
    `QuickClip/iCloudSyncManager.swift:617`
  - 云端胜出：云端字段覆盖本地，并清理 `needsSync`  
    `QuickClip/iCloudSyncManager.swift:625`

#### 3.3.2 规则 2：云端有、本地没有任何 content 匹配

位置：`mergeCloudSnippets` 的“按 content 处理”分支，且本地无法命中 content  
`QuickClip/iCloudSyncManager.swift:694`

- 行为：导入云端记录到本地（新增 Snippet）
- 为保证跨设备稳定匹配，导入时将本地 `Snippet.id` 设为云端 `snippetID`  
  `QuickClip/iCloudSyncManager.swift:702`

#### 3.3.3 规则 3：content 相同但 snippetID 不同

位置：`mergeCloudSnippets` 的“content 命中，但 snippetID 不同”分支  
`QuickClip/iCloudSyncManager.swift:653`

- updatedAt 决策：
  - 本地胜出：绑定/修正 `cloudRecordID`，若字段不一致则标记 `needsSync = true`（后续上传覆盖云端）  
    `QuickClip/iCloudSyncManager.swift:660`、`QuickClip/iCloudSyncManager.swift:665`
  - 云端胜出：云端字段覆盖本地  
    `QuickClip/iCloudSyncManager.swift:673`

### 3.4 快捷键冲突策略（沿用现有策略）

位置：`applyShortcut(_:to:)`  
`QuickClip/iCloudSyncManager.swift:527`

- 如果新写入的快捷键已被其他 Snippet 占用：清空当前 Snippet 的 `shortcutKey`  
  `QuickClip/iCloudSyncManager.swift:540`-`542`

### 3.5 修复“只同步新增、旧数据不上传”的根因

位置：`mergeCloudSnippets` 的“本地 recordName 纠偏”分支  
`QuickClip/iCloudSyncManager.swift:725`

策略：
- 若本地 `cloudRecordID` 是空白（`""`/空格），直接置为 `nil`  
  `QuickClip/iCloudSyncManager.swift:728`
- 若本地 `cloudRecordID` 不在本次下载到的云端 recordName 集合中：
  - 清空 `cloudRecordID`
  - 标记 `needsSync = true`，确保随后的 `uploadLocalSnippets()` 会把该记录作为“本地独有数据”上传  
  `QuickClip/iCloudSyncManager.swift:734`-`737`

## 4. 上传策略（uploadLocalSnippets）

入口：`uploadLocalSnippets()`  
`QuickClip/iCloudSyncManager.swift:307`

### 4.1 上传筛选条件

只上传两类 Snippet：  
`QuickClip/iCloudSyncManager.swift:312`

- `cloudRecordID` 为空（包含空白归一化后为空）  
  `QuickClip/iCloudSyncManager.swift:313`
- 或 `needsSync == true`

### 4.2 批量上传/更新分组

`QuickClip/iCloudSyncManager.swift:322`

- 新增上传：`batchUploadNewSnippets()`  
  `QuickClip/iCloudSyncManager.swift:340`
- 已存在更新：`batchUpdateExistingSnippets()`  
  `QuickClip/iCloudSyncManager.swift:397`

## 5. 同步逻辑图（含函数/文件/行号）

### 5.1 完整同步（开启开关 / 手动 / 启动）

```text
Settings iCloud Toggle
  QuickClip/SettingsView.swift:141
    |
    v
SettingsViewModel.iCloudSyncEnabled didSet
  QuickClip/SettingsViewModel.swift:40
    |
    +--> enableiCloudSync() QuickClip/SettingsViewModel.swift:301
    |       |
    |       v
    |     performFullSync() QuickClip/iCloudSyncManager.swift:124
    |
    +--> manualSync() QuickClip/SettingsViewModel.swift:351
    |       |
    |       v
    |     performFullSync() QuickClip/iCloudSyncManager.swift:124
    |
    +--> ContentView.task QuickClip/ContentView.swift:48
            |
            v
          performStartupSyncIfEnabled() QuickClip/SettingsViewModel.swift:398
            |
            v
          performFullSync() QuickClip/iCloudSyncManager.swift:124
            |
            +--> checkAccountStatus() QuickClip/iCloudSyncManager.swift:104
            +--> downloadAllSnippets() QuickClip/iCloudSyncManager.swift:233
            |       +--> parseCloudKitRecord() QuickClip/iCloudSyncManager.swift:279
            +--> mergeCloudSnippets() QuickClip/iCloudSyncManager.swift:501
            |       +--> 修复旧 cloudRecordID/needsSync QuickClip/iCloudSyncManager.swift:725
            +--> uploadLocalSnippets() QuickClip/iCloudSyncManager.swift:307
                    +--> batchUploadNewSnippets() QuickClip/iCloudSyncManager.swift:340
                    +--> batchUpdateExistingSnippets() QuickClip/iCloudSyncManager.swift:397
```

### 5.2 增量同步：新建 / 编辑 / 删除

```text
新建片段
  addNewSnippet() QuickClip/SnippetListView.swift:122
    |
    v
  syncNewSnippetToiCloud() QuickClip/SnippetListView.swift:196
    |
    v
  uploadSnippet() QuickClip/iCloudSyncManager.swift:168

编辑片段（延迟 3 秒）
  onChange(...) QuickClip/SnippetDetailView.swift:221
    |
    v
  markNeedsSyncAndScheduleUpload() QuickClip/SnippetDetailView.swift:236
    |
    +--> needsSync = true QuickClip/SnippetDetailView.swift:237
    |
    +--> after 3s: updateSnippet() QuickClip/SnippetDetailView.swift:255
                |
                v
              updateSnippet() QuickClip/iCloudSyncManager.swift:196

删除片段（云端优先）
  deleteSnippet(_) QuickClip/SnippetListView.swift:137
    |
    v
  deleteCloudRecord() QuickClip/SnippetListView.swift:156
    |
    v
  deleteCloudRecord() QuickClip/iCloudSyncManager.swift:189
```

### 5.3 导入后上传

```text
importFromJSON() QuickClip/SettingsViewModel.swift:196
  |
  v
syncImportedSnippetsToiCloud() QuickClip/SettingsViewModel.swift:428
  |
  v
uploadSnippet() QuickClip/SettingsViewModel.swift:448
  |
  v
uploadSnippet() QuickClip/iCloudSyncManager.swift:168
```

