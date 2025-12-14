# 用户统计功能说明

## 功能概述

QuickClip 收集匿名的使用统计数据，用于了解用户分布和改进产品。所有数据都是匿名的，不包含任何个人身份信息。

---

## 收集的数据

### CloudKit Record Type: `UsingUsers`
**数据库**: Public Database

| 字段 | 类型 | 说明 | 是否更新 |
|------|------|------|---------|
| `uid` | String | userRecordID 的 MD5 哈希值（匿名标识） | ❌ 永不更新 |
| `os` | String | 系统版本（如 "Version 14.0 (Build 23A344)"） | ✅ 每次启动更新 |
| `sv` | String | App 版本号（如 "1.0.0"） | ✅ 每次启动更新 |
| `firstSendDate` | Date | 首次打开 App 的时间 | ❌ 永不更新 |
| `sendDate` | Date | 最后一次打开 App 的时间 | ✅ 每次启动更新 |

---

## 技术实现

### 文件位置
- **统计管理器**: `QuickClip/UsageStatsManager.swift`
- **集成位置**: `QuickClip/QuickClipApp.swift:59-87`

### 工作流程

#### 首次启动
```
1. 从 CloudKit 获取 userRecordID.recordName
   ↓
2. 计算 MD5 作为匿名 uid
   ↓
3. 获取系统版本和 App 版本
   ↓
4. 创建新的 UsingUsers 记录
   - uid = md5(userRecordID.recordName)
   - os = 当前系统版本
   - sv = 当前 App 版本
   - firstSendDate = 当前时间
   - sendDate = 当前时间
   ↓
5. 保存到 CloudKit Public Database
   ↓
6. 保存 recordName 到 UserDefaults
```

#### 后续启动
```
1. 从 UserDefaults 读取 recordName
   ↓
2. 从 CloudKit 获取已有记录
   ↓
3. 更新字段:
   - os = 当前系统版本
   - sv = 当前 App 版本
   - sendDate = 当前时间
   (uid 和 firstSendDate 保持不变)
   ↓
4. 保存到 CloudKit
```

### 关键代码

#### 计算匿名 UID
```swift
// UsageStatsManager.swift:122-126
private func md5(_ string: String) -> String {
    let digest = Insecure.MD5.hash(data: Data(string.utf8))
    return digest.map { String(format: "%02hhx", $0) }.joined()
}
```

#### 获取系统版本
```swift
// UsageStatsManager.swift:109-112
private func getOSVersion() -> String {
    let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
    return osVersion
}
```

#### 获取 App 版本
```swift
// UsageStatsManager.swift:115-118
private func getAppVersion() -> String {
    let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "Unknown"
    return appVersion
}
```

---

## 隐私保护

### 匿名性
✅ **使用 MD5 哈希**: userRecordID 经过 MD5 哈希后存储，无法反推原始 ID
✅ **不收集个人信息**: 只收集系统版本、App 版本、使用时间
✅ **不收集用户内容**: 不收集用户的片段内容、快捷键设置等任何数据

### 数据存储
✅ **Public Database**: 数据存储在 CloudKit Public Database，不占用用户 iCloud 空间
✅ **匿名标识**: 使用 MD5 哈希作为唯一标识，无法关联到真实用户

### 用户控制
✅ **静默失败**: 如果用户未登录 iCloud 或网络不可用，统计功能会静默失败，不影响 App 正常使用
✅ **无需权限**: 统计功能不需要任何额外权限

---

## 错误处理

### 用户未登录 iCloud
```swift
// QuickClipApp.swift:77-78
case .notAuthenticated:
    print("⚠️ 用户未登录 iCloud，跳过统计上传")
```
**处理方式**: 静默失败，不影响 App 使用

### 网络不可用
```swift
// QuickClipApp.swift:79-80
case .networkUnavailable, .networkFailure:
    print("⚠️ 网络不可用，跳过统计上传")
```
**处理方式**: 静默失败，下次启动时重试

### 记录不存在（被删除）
```swift
// UsageStatsManager.swift:41-46
catch let error as CKError where error.code == .unknownItem {
    print("⚠️ 统计记录不存在，重新创建")
    UserDefaults.standard.removeObject(forKey: recordNameKey)
    try await createNewRecord()
}
```
**处理方式**: 清除本地缓存，重新创建记录

---

## 数据用途

### 统计分析
- **活跃用户数**: 通过 sendDate 统计日活、周活、月活
- **系统版本分布**: 了解用户使用的 macOS 版本，优化兼容性
- **App 版本分布**: 了解用户升级情况，决定是否废弃旧版本
- **用户留存**: 通过 firstSendDate 和 sendDate 分析用户留存率

### 示例查询

#### 统计总用户数
```swift
let query = CKQuery(recordType: "UsingUsers", predicate: NSPredicate(value: true))
// 返回所有记录数量
```

#### 统计日活用户（过去 24 小时）
```swift
let yesterday = Date().addingTimeInterval(-24 * 3600)
let predicate = NSPredicate(format: "sendDate > %@", yesterday as NSDate)
let query = CKQuery(recordType: "UsingUsers", predicate: predicate)
```

#### 统计系统版本分布
```swift
// 按 os 字段分组统计
// 需要在 CloudKit Dashboard 中配置索引
```

---

## 测试场景

### 测试步骤

1. **首次启动测试**
   ```
   - 删除 App
   - 删除 UserDefaults (~/Library/Preferences/io.0os.QuickClip.plist)
   - 删除 CloudKit 中的测试记录（可选）
   - 重新安装并启动 App
   - 检查控制台是否输出 "✅ 用户统计数据已创建"
   - 登录 CloudKit Dashboard 确认记录已创建
   ```

2. **后续启动测试**
   ```
   - 重启 App
   - 检查控制台是否输出 "✅ 用户统计数据已更新"
   - 登录 CloudKit Dashboard 确认 sendDate 已更新
   ```

3. **版本升级测试**
   ```
   - 修改 Info.plist 中的 CFBundleShortVersionString
   - 重新编译并启动 App
   - 确认 CloudKit 中的 sv 字段已更新
   ```

4. **系统升级测试**
   ```
   - 模拟系统升级（或使用不同的 macOS 版本虚拟机）
   - 启动 App
   - 确认 CloudKit 中的 os 字段已更新
   ```

5. **未登录 iCloud 测试**
   ```
   - 系统设置中退出 iCloud
   - 启动 App
   - 检查控制台是否输出 "⚠️ 用户未登录 iCloud，跳过统计上传"
   - 确认 App 正常使用，没有崩溃或错误提示
   ```

6. **网络断开测试**
   ```
   - 断开网络连接
   - 启动 App
   - 检查控制台是否输出 "⚠️ 网络不可用，跳过统计上传"
   - 确认 App 正常使用
   - 恢复网络后再次启动，确认统计数据上传成功
   ```

---

## CloudKit Dashboard 配置

### 1. 创建 Record Type

**Record Type Name**: `UsingUsers`

**Fields**:
| Field Name | Type | Indexed | Notes |
|------------|------|---------|-------|
| `uid` | String | ✅ Yes | 用于查询和去重 |
| `os` | String | ⚪ Optional | 用于统计系统版本分布 |
| `sv` | String | ⚪ Optional | 用于统计 App 版本分布 |
| `firstSendDate` | Date/Time | ⚪ Optional | 用于分析用户注册时间 |
| `sendDate` | Date/Time | ✅ Yes | 用于统计活跃用户 |

### 2. 权限设置

**Database**: Public Database
**Security**: World Readable (所有人可读，用于统计查询)

---

## 日志输出

### 正常流程
```
📊 统计数据已创建: uid=a1b2c3d4e5f6..., os=Version 14.0, sv=1.0.0
✅ 用户统计数据已创建
```

```
📊 统计数据已更新: os=Version 14.0, sv=1.0.0
✅ 用户统计数据已更新
```

### 错误处理
```
⚠️ 用户未登录 iCloud，跳过统计上传
```

```
⚠️ 网络不可用，跳过统计上传
```

```
⚠️ 统计记录不存在，重新创建
```

---

## 隐私政策建议

建议在网站隐私政策中添加以下内容：

```
### 匿名使用统计

QuickClip 会收集匿名的使用统计数据，用于改进产品和服务。收集的数据包括：

- 匿名用户标识（userRecordID 的 MD5 哈希值）
- 操作系统版本
- App 版本号
- App 打开时间

我们不会收集：
- 您的个人身份信息
- 您的片段内容
- 您的快捷键设置
- 任何其他个人数据

所有统计数据都是匿名的，无法关联到具体用户。数据存储在 Apple CloudKit Public Database 中，
仅用于统计分析，不会与第三方共享。

如果您未登录 iCloud 或网络不可用，统计功能会自动跳过，不会影响 App 的正常使用。
```

---

**文档版本**: v1.0
**最后更新**: 2025-12-13
**维护者**: QuickClip Team
