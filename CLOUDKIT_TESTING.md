# CloudKit Production 环境测试指南

## 新版 Xcode (16.0+) 环境说明

在新版 Xcode 中，CloudKit 环境的选择已经简化，不再需要手动切换。**环境根据构建配置自动选择**：

- ✅ **Debug 构建** → CloudKit Development 环境
- ✅ **Release 构建** → CloudKit Production 环境

---

## 测试 Production 环境的正确方法

### 方法 1：使用 Release 配置运行（推荐）

**步骤**：
1. **编辑 Scheme**
   ```
   Xcode → Product → Scheme → Edit Scheme
   (或快捷键: Cmd + <)
   ```

2. **切换构建配置**
   ```
   左侧选择 "Run"
   → Info 标签页
   → Build Configuration: 选择 "Release"
   ```

3. **运行 App**
   ```
   Product → Run (Cmd + R)
   ```

4. **验证环境**
   - 查看控制台输出
   - 检查 CloudKit Dashboard 中 Production Database 的数据变化

**注意**:
- Release 模式下，某些调试功能会被禁用（如 `#if DEBUG` 包裹的代码）
- 测试完成后记得切换回 Debug 配置

---

### 方法 2：Archive 后测试（最接近真实环境）

**步骤**：
1. **清理构建**
   ```
   Product → Clean Build Folder (Shift + Cmd + K)
   ```

2. **Archive**
   ```
   Product → Archive
   等待构建完成
   ```

3. **导出 App**
   ```
   Organizer 窗口自动打开
   → 选择刚才的 Archive
   → 点击 "Distribute App"
   → 选择 "Development"
   → 选择导出位置
   ```

4. **运行导出的 .app**
   ```
   打开导出文件夹
   双击运行 QuickClip.app
   ```

**优点**：
- 完全模拟生产环境
- 包含完整的代码签名
- 与用户实际使用的版本一致

**缺点**：
- 构建和导出耗时较长
- 无法直接调试

---

## 如何验证当前使用的环境

### 方法 1：代码中添加日志

在 `UsageStatsManager.swift` 或 `iCloudSyncManager.swift` 的 `init()` 方法中添加：

```swift
init() {
    self.container = CKContainer(identifier: "iCloud.io.0os.QuickClip")
    self.publicDatabase = container.publicCloudDatabase

    #if DEBUG
    print("🔧 CloudKit Environment: DEVELOPMENT")
    #else
    print("🚀 CloudKit Environment: PRODUCTION")
    #endif
}
```

### 方法 2：在 CloudKit Dashboard 中查看

1. 登录 [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard/)
2. 选择 `iCloud.io.0os.QuickClip` 容器
3. 切换到 **Development** 环境，查看是否有新数据
4. 切换到 **Production** 环境，查看是否有新数据
5. 根据数据出现的位置判断当前使用的环境

### 方法 3：通过数据区分

在测试数据中添加特殊标记：

**Development 测试**：
```swift
// 创建标题包含 [DEV] 的测试片段
let testSnippet = Snippet(title: "[DEV] Test Snippet", content: "Development test")
```

**Production 测试**：
```swift
// 创建标题包含 [PROD] 的测试片段
let testSnippet = Snippet(title: "[PROD] Test Snippet", content: "Production test")
```

然后在 CloudKit Dashboard 中查看数据出现在哪个环境。

---

## 上线前必做测试

### 1. 确认 Production Schema 已部署
```
CloudKit Dashboard
→ 选择容器 iCloud.io.0os.QuickClip
→ Schema 标签页
→ 点击 "Deploy to Production"
→ 确认 Snippet 和 UsingUsers 都已部署
```

### 2. 使用 Release 配置测试完整流程
```
1. 切换到 Release 配置
2. 启动 App（应创建用户统计记录）
3. 开启 iCloud 同步（应执行完整同步）
4. 创建新片段（应上传到 Production）
5. 修改片段（3秒后应上传更新）
6. 删除片段（应删除 Production 中的记录）
7. 在 CloudKit Dashboard Production 环境中验证所有操作
```

### 3. 清理测试数据
**重要**: 上线前清理 Production 环境中的测试数据

```
1. 登录 CloudKit Dashboard
2. 选择 Production 环境
3. 进入 Default Zone → Snippet
4. 删除所有测试记录
5. 进入 Public Database → UsingUsers
6. 删除测试统计记录（如果有）
```

---

## 常见问题

### Q1: 为什么我看不到 CloudKit 环境选项？
**A**: 新版 Xcode 移除了手动选择 CloudKit 环境的选项，改为根据构建配置自动选择。这是正常的。

### Q2: 如何确保上线后使用 Production 环境？
**A**: Archive 和上传到 App Store 的构建始终使用 Release 配置，因此自动使用 Production 环境。无需额外配置。

### Q3: Development 数据会影响 Production 吗？
**A**: 不会。Development 和 Production 是完全独立的环境，数据不会互相影响。

### Q4: 能否在 Debug 模式下测试 Production？
**A**: 理论上可以通过修改 Build Settings，但不推荐。最佳实践是：
- Debug 模式 → Development 环境（开发测试）
- Release 模式 → Production 环境（上线前验证）

### Q5: TestFlight 使用哪个环境？
**A**: TestFlight 构建使用 Production 环境，与正式发布版本一致。

---

## 快速检查清单

上线前，按照以下清单确保 CloudKit Production 环境正确配置：

- [ ] CloudKit Dashboard 中 Production Schema 已部署
- [ ] 切换到 Release 配置
- [ ] 启动 App，确认使用 Production 环境（查看日志）
- [ ] 测试 iCloud 同步功能（开启、创建、修改、删除）
- [ ] 测试用户统计上传
- [ ] 在 CloudKit Dashboard Production 环境中验证数据
- [ ] 清理 Production 环境中的测试数据
- [ ] 切换回 Debug 配置（继续开发）

---

## 参考文档

- [RELEASE_CHECKLIST.md](./RELEASE_CHECKLIST.md) - 完整上线检查清单
- [ICLOUD_SYNC_DESIGN.md](./ICLOUD_SYNC_DESIGN.md) - iCloud 同步方案设计
- [USAGE_STATS.md](./USAGE_STATS.md) - 用户统计功能说明
- [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard/)

---

**更新日期**: 2025-12-13
**适用于**: Xcode 16.0 及更高版本
