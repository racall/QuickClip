# APNs + CloudKit 集成方案

## 1. 方案概述

### 架构设计
```
┌─────────────────────────────────────────────────────────┐
│                     QuickClip App                       │
│                                                         │
│  1. 注册 APNs → 获取 Device Token                       │
│  2. 上传 Token 到 CloudKit Public Database              │
│     (存储在 UsingUsers 记录中)                          │
│  3. 接收和处理推送通知                                  │
└─────────────────────────────────────────────────────────┘
                          ↓ Device Token
                          ↓
┌─────────────────────────────────────────────────────────┐
│              CloudKit Public Database                   │
│                                                         │
│  Record Type: UsingUsers                                │
│  - uid                                                  │
│  - os                                                   │
│  - sv                                                   │
│  - firstSendDate                                        │
│  - sendDate                                             │
│  - token  ← ✅ 新增字段                                 │
└─────────────────────────────────────────────────────────┘
                          ↑ 查询 Tokens
                          ↓ 发送推送
┌─────────────────────────────────────────────────────────┐
│                   你的推送服务器                        │
│                                                         │
│  1. 从 CloudKit 查询所有 Device Token                   │
│  2. 使用 APNs 证书/Key 发送推送                         │
└─────────────────────────────────────────────────────────┘
```

---

## 2. CloudKit Schema 更新

### 2.1 UsingUsers Record Type

在 [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard/) 中更新：

**现有字段**:
- `uid` (String, Indexed)
- `os` (String)
- `sv` (String)
- `firstSendDate` (Date)
- `sendDate` (Date, Indexed)

**新增字段**:
- ✅ `token` (String, Optional) - APNs Device Token

**步骤**:
1. 登录 CloudKit Dashboard
2. 选择 `iCloud.io.0os.QuickClip` 容器
3. 进入 Public Database → Record Types → UsingUsers
4. 添加字段：
   - Field Name: `token`
   - Type: `String`
   - Indexed: 可选（如果需要按 token 查询则勾选）
5. 保存并部署到 Production 环境

---

## 3. 客户端实现

### 3.1 文件结构

```
QuickClip/
├── PushNotificationManager.swift      (新建)
├── UsageStatsManager.swift            (修改)
└── QuickClipApp.swift                 (修改)
```

---

### 3.2 代码实现

#### 文件 1: `PushNotificationManager.swift` (新建)

**功能**:
- 注册 APNs
- 获取 Device Token
- 接收和处理推送通知
- 提供 Token 给 UsageStatsManager

**关键代码**:
```swift
@MainActor
final class PushNotificationManager: NSObject {
    static let shared = PushNotificationManager()

    // Device Token（十六进制字符串）
    private(set) var deviceToken: String? {
        didSet {
            if let token = deviceToken {
                UserDefaults.standard.set(token, forKey: "apnsDeviceToken")
                print("✅ Device Token: \(token)")

                // 通知 UsageStatsManager 更新 token
                NotificationCenter.default.post(
                    name: NSNotification.Name("APNsTokenUpdated"),
                    object: token
                )
            }
        }
    }

    // 注册 APNs
    func registerForRemoteNotifications() {
        let center = UNUserNotificationCenter.current()
        center.delegate = self

        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            DispatchQueue.main.async {
                NSApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    // 获取 Token
    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        self.deviceToken = token
    }

    // 接收推送
    func didReceiveRemoteNotification(_ userInfo: [String: Any]) {
        print("📬 收到推送: \(userInfo)")

        // 解析并处理推送内容
        if let aps = userInfo["aps"] as? [String: Any] {
            handleAPSPayload(aps, userInfo: userInfo)
        }
    }

    // 处理推送内容
    private func handleAPSPayload(_ aps: [String: Any], userInfo: [String: Any]) {
        // 提取标题和内容
        if let alert = aps["alert"] as? [String: Any] {
            let title = alert["title"] as? String ?? "QuickClip"
            let body = alert["body"] as? String ?? ""
            print("📝 \(title): \(body)")
        }

        // 处理自定义 action
        if let action = userInfo["action"] as? String {
            handleAction(action, data: userInfo)
        }
    }

    // 执行操作
    private func handleAction(_ action: String, data: [String: Any]) {
        switch action {
        case "sync":
            // 触发同步
            NotificationCenter.default.post(
                name: NSNotification.Name("TriggerSync"),
                object: nil
            )
        case "update":
            // 显示更新提示
            if let version = data["version"] as? String {
                showUpdateAlert(version: version)
            }
        case "message":
            // 显示消息
            if let message = data["message"] as? String {
                showMessage(message)
            }
        default:
            break
        }
    }
}

// 实现 UNUserNotificationCenterDelegate
extension PushNotificationManager: UNUserNotificationCenterDelegate {
    // 前台接收通知
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        didReceiveRemoteNotification(notification.request.content.userInfo)
        completionHandler([.banner, .sound])
    }

    // 用户点击通知
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        didReceiveRemoteNotification(response.notification.request.content.userInfo)
        completionHandler()
    }
}
```

---

#### 文件 2: 修改 `UsageStatsManager.swift`

**修改内容**:
1. 在创建/更新统计记录时，同时保存 Device Token
2. 监听 Token 更新通知

**修改位置**:

**1) 添加属性和初始化监听**:
```swift
// 在 init() 中添加
init() {
    // ... 现有代码

    // 监听 APNs Token 更新
    NotificationCenter.default.addObserver(
        self,
        selector: #selector(handleTokenUpdate),
        name: NSNotification.Name("APNsTokenUpdated"),
        object: nil
    )
}

// 处理 Token 更新
@objc private func handleTokenUpdate(_ notification: Notification) {
    guard let token = notification.object as? String else { return }

    print("📱 APNs Token 已更新，准备上传到 CloudKit")

    // 如果已有统计记录，更新 token
    Task {
        await updateTokenIfNeeded(token)
    }
}

// 更新已有记录的 token
private func updateTokenIfNeeded(_ token: String) async {
    guard let recordName = UserDefaults.standard.string(forKey: "userStatsRecordName") else {
        return
    }

    do {
        let recordID = CKRecord.ID(recordName: recordName)
        let record = try await publicDatabase.record(for: recordID)

        // 检查 token 是否需要更新
        let existingToken = record["token"] as? String
        if existingToken != token {
            record["token"] = token
            _ = try await publicDatabase.save(record)
            print("✅ Device Token 已更新到 CloudKit")
        }
    } catch {
        print("⚠️ 更新 Token 失败: \(error.localizedDescription)")
    }
}
```

**2) 修改 createNewRecord() 方法**:
```swift
private func createNewRecord() async throws {
    // ... 现有代码（计算 uid、获取版本信息等）

    // 获取 Device Token
    let deviceToken = PushNotificationManager.shared.deviceToken

    // 创建 CloudKit 记录
    let record = CKRecord(recordType: "UsingUsers")
    record["uid"] = uid
    record["os"] = osVersion
    record["sv"] = appVersion
    record["firstSendDate"] = now
    record["sendDate"] = now
    record["token"] = deviceToken  // ✅ 添加 token 字段

    // ... 保存记录
}
```

**3) 修改 updateExistingRecord() 方法**:
```swift
private func updateExistingRecord(recordName: String) async throws {
    // 获取已有记录
    let recordID = CKRecord.ID(recordName: recordName)
    let record = try await publicDatabase.record(for: recordID)

    // 更新字段
    record["os"] = getOSVersion()
    record["sv"] = getAppVersion()
    record["sendDate"] = Date()

    // ✅ 更新 token（如果有）
    if let deviceToken = PushNotificationManager.shared.deviceToken {
        record["token"] = deviceToken
    }

    // 保存
    _ = try await publicDatabase.save(record)
}
```

---

#### 文件 3: 修改 `QuickClipApp.swift`

**修改内容**:
集成 APNs 注册和通知处理

**在 AppDelegate 中添加**:
```swift
import UserNotifications  // ✅ 添加导入

class AppDelegate: NSObject, NSApplicationDelegate {
    // ... 现有代码

    func applicationDidFinishLaunching(_ notification: Notification) {
        // ... 现有代码

        // ✅ 注册 APNs（在上传用户统计之前）
        PushNotificationManager.shared.registerForRemoteNotifications()

        // 上传用户统计数据（会同时上传 Device Token）
        Task {
            await uploadUsageStats()
        }
    }

    // ✅ APNs 注册成功
    func application(
        _ application: NSApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushNotificationManager.shared.didRegisterForRemoteNotifications(
            withDeviceToken: deviceToken
        )
    }

    // ✅ APNs 注册失败
    func application(
        _ application: NSApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        PushNotificationManager.shared.didFailToRegisterForRemoteNotifications(
            withError: error
        )
    }

    // ✅ 接收远程通知
    func application(
        _ application: NSApplication,
        didReceiveRemoteNotification userInfo: [String : Any]
    ) {
        PushNotificationManager.shared.didReceiveRemoteNotification(userInfo)
    }
}
```

---

### 3.3 Xcode 配置

#### Step 1: 添加 Push Notifications Capability
```
Xcode → 项目设置 → Signing & Capabilities
→ 点击 "+ Capability"
→ 添加 "Push Notifications"
```

#### Step 2: 修改 Entitlements
**文件**: `QuickClip.entitlements`

添加：
```xml
<!-- Push Notifications -->
<key>aps-environment</key>
<string>development</string>
```

**注意**: Archive 后会自动变为 `production`

---

## 4. 服务器端实现

### 4.1 从 CloudKit 查询 Device Token

服务器需要访问 CloudKit Public Database 来获取所有 Device Token。

#### 方案 1: 使用 CloudKit Web Services API

**步骤**:
1. 在 Apple Developer 创建 Server-to-Server Key
2. 使用 CloudKit Web Services API 查询记录

**示例（Node.js）**:
```javascript
const https = require('https');
const crypto = require('crypto');

// CloudKit 配置
const CONTAINER_ID = 'iCloud.io.0os.QuickClip';
const KEY_ID = 'YOUR_KEY_ID';
const PRIVATE_KEY = '-----BEGIN PRIVATE KEY-----\n...';

// 生成 JWT Token
function generateToken() {
    const header = {
        alg: 'ES256',
        kid: KEY_ID
    };

    const claims = {
        iss: 'YOUR_TEAM_ID',
        iat: Math.floor(Date.now() / 1000),
        exp: Math.floor(Date.now() / 1000) + 3600
    };

    // 使用 jsonwebtoken 库
    const jwt = require('jsonwebtoken');
    return jwt.sign(claims, PRIVATE_KEY, {
        algorithm: 'ES256',
        header: header
    });
}

// 查询所有 Device Token
async function fetchAllTokens() {
    const token = generateToken();

    const options = {
        hostname: 'api.apple-cloudkit.com',
        path: `/database/1/${CONTAINER_ID}/production/public/records/query`,
        method: 'POST',
        headers: {
            'Authorization': `Bearer ${token}`,
            'Content-Type': 'application/json'
        }
    };

    const query = {
        query: {
            recordType: 'UsingUsers',
            filterBy: [
                {
                    fieldName: 'token',
                    comparator: 'NOT_EQUALS',
                    fieldValue: { value: null }
                }
            ]
        }
    };

    // 发送请求...
    // 返回所有有 token 的记录
}
```

#### 方案 2: 使用 CloudKit JS 库（简单）

**安装**:
```bash
npm install cloudkit
```

**示例代码**:
```javascript
const CloudKit = require('cloudkit');

// 配置 CloudKit
CloudKit.configure({
    containers: [{
        containerIdentifier: 'iCloud.io.0os.QuickClip',
        apiTokenAuth: {
            apiToken: 'YOUR_API_TOKEN',
            persist: true
        },
        environment: 'production'
    }]
});

const container = CloudKit.getDefaultContainer();
const publicDB = container.publicCloudDatabase;

// 查询所有有 token 的用户
async function fetchAllTokens() {
    const query = {
        recordType: 'UsingUsers',
        filterBy: [{
            fieldName: 'token',
            comparator: CloudKit.QueryFilterComparator.NOT_EQUALS,
            fieldValue: { value: null }
        }]
    };

    try {
        const response = await publicDB.performQuery(query);
        const tokens = response.records.map(record => ({
            token: record.fields.token.value,
            uid: record.fields.uid.value,
            platform: 'macos'
        }));

        console.log(`获取到 ${tokens.length} 个 Device Token`);
        return tokens;
    } catch (error) {
        console.error('查询失败:', error);
        return [];
    }
}
```

---

### 4.2 发送推送通知

#### 使用 Node.js (apn 库)

**安装**:
```bash
npm install apn
```

**示例代码**:
```javascript
const apn = require('apn');

// 配置 APNs
const apnProvider = new apn.Provider({
    token: {
        key: './AuthKey_XXXXXXXXXX.p8',  // 你的 APNs Auth Key
        keyId: 'YOUR_KEY_ID',
        teamId: 'YOUR_TEAM_ID'
    },
    production: true  // 生产环境
});

// 发送推送
async function sendPushToAll(message) {
    // 1. 从 CloudKit 获取所有 Token
    const tokens = await fetchAllTokens();

    // 2. 创建通知
    const notification = new apn.Notification();
    notification.alert = {
        title: 'QuickClip',
        body: message
    };
    notification.topic = 'io.0os.QuickClip';
    notification.badge = 1;
    notification.sound = 'default';

    // 自定义数据
    notification.payload = {
        action: 'sync',
        timestamp: Date.now()
    };

    // 3. 批量发送
    const results = await apnProvider.send(
        notification,
        tokens.map(t => t.token)
    );

    console.log(`推送成功: ${results.sent.length}`);
    console.log(`推送失败: ${results.failed.length}`);

    // 4. 清理失效 Token
    for (const failure of results.failed) {
        if (failure.status === '410') {
            console.log(`Token 已失效: ${failure.device}`);
            // 从 CloudKit 中删除或标记为无效
        }
    }
}

// 使用示例
sendPushToAll('Your snippets have been synced!');
```

---

### 4.3 完整推送服务示例

```javascript
const CloudKit = require('cloudkit');
const apn = require('apn');

// CloudKit 配置
CloudKit.configure({
    containers: [{
        containerIdentifier: 'iCloud.io.0os.QuickClip',
        apiTokenAuth: {
            apiToken: 'YOUR_API_TOKEN',
            persist: true
        },
        environment: 'production'
    }]
});

// APNs 配置
const apnProvider = new apn.Provider({
    token: {
        key: './AuthKey_XXXXXXXXXX.p8',
        keyId: 'YOUR_KEY_ID',
        teamId: 'YOUR_TEAM_ID'
    },
    production: true
});

// 推送服务类
class PushService {
    // 获取所有 Token
    async fetchTokens() {
        const container = CloudKit.getDefaultContainer();
        const publicDB = container.publicCloudDatabase;

        const query = {
            recordType: 'UsingUsers',
            filterBy: [{
                fieldName: 'token',
                comparator: CloudKit.QueryFilterComparator.NOT_EQUALS,
                fieldValue: { value: null }
            }]
        };

        const response = await publicDB.performQuery(query);
        return response.records.map(record => ({
            token: record.fields.token.value,
            uid: record.fields.uid.value,
            recordName: record.recordName
        }));
    }

    // 发送推送
    async sendPush(title, body, action = null, data = {}) {
        const tokens = await this.fetchTokens();

        const notification = new apn.Notification();
        notification.alert = { title, body };
        notification.topic = 'io.0os.QuickClip';
        notification.sound = 'default';

        if (action) {
            notification.payload = { action, ...data };
        }

        const results = await apnProvider.send(
            notification,
            tokens.map(t => t.token)
        );

        console.log(`✅ 发送成功: ${results.sent.length}`);
        console.log(`❌ 发送失败: ${results.failed.length}`);

        // 处理失效 Token
        await this.handleFailedTokens(results.failed, tokens);

        return results;
    }

    // 处理失效 Token
    async handleFailedTokens(failures, allTokens) {
        for (const failure of failures) {
            if (failure.status === '410') {
                // Token 已失效，从 CloudKit 删除
                const tokenInfo = allTokens.find(t => t.token === failure.device);
                if (tokenInfo) {
                    await this.removeToken(tokenInfo.recordName);
                }
            }
        }
    }

    // 从 CloudKit 删除失效 Token
    async removeToken(recordName) {
        const container = CloudKit.getDefaultContainer();
        const publicDB = container.publicCloudDatabase;

        try {
            const recordID = CloudKit.Record.recordID(recordName);
            const record = await publicDB.fetchRecords([recordID]);

            // 将 token 字段设为 null
            record.fields.token = { value: null };
            await publicDB.saveRecords([record]);

            console.log(`🗑️ 已清除失效 Token: ${recordName}`);
        } catch (error) {
            console.error(`清除 Token 失败: ${error}`);
        }
    }
}

// 使用示例
const pushService = new PushService();

// 发送同步提醒
pushService.sendPush(
    'QuickClip',
    'Your snippets have been synced!',
    'sync'
);

// 发送版本更新通知
pushService.sendPush(
    'Update Available',
    'QuickClip 1.1.0 is now available',
    'update',
    { version: '1.1.0' }
);
```

---

## 5. 数据流程图

### 5.1 首次启动流程

```
App 启动
  ↓
注册 APNs
  ↓
获取 Device Token
  ↓
保存到 UserDefaults
  ↓
上传用户统计（UsageStatsManager）
  ↓
创建 CloudKit 记录（UsingUsers）
  包含: uid, os, sv, firstSendDate, sendDate, token
  ↓
完成
```

### 5.2 后续启动流程

```
App 启动
  ↓
注册 APNs
  ↓
获取 Device Token（可能变化）
  ↓
更新用户统计
  ↓
更新 CloudKit 记录
  更新: os, sv, sendDate, token
  ↓
完成
```

### 5.3 发送推送流程

```
服务器
  ↓
从 CloudKit 查询所有 UsingUsers 记录
  ↓
提取所有非空的 token 字段
  ↓
构建推送 Payload
  ↓
使用 APNs 证书/Key 发送推送
  ↓
处理失败结果
  ↓
清理失效 Token（status = 410）
```

### 5.4 接收推送流程

```
APNs 推送
  ↓
App 收到通知
  ↓
didReceiveRemoteNotification
  ↓
解析 aps 和自定义字段
  ↓
根据 action 执行操作:
  - sync → 触发同步
  - update → 显示更新提示
  - message → 显示消息
  ↓
完成
```

---

## 6. 推送格式规范

### 6.1 同步提醒
```json
{
  "aps": {
    "alert": {
      "title": "QuickClip",
      "body": "Your snippets have been synced"
    },
    "sound": "default"
  },
  "action": "sync"
}
```

### 6.2 版本更新
```json
{
  "aps": {
    "alert": {
      "title": "Update Available",
      "body": "QuickClip 1.1.0 is now available"
    },
    "badge": 1,
    "sound": "default"
  },
  "action": "update",
  "version": "1.1.0",
  "url": "https://your-website.com/download"
}
```

### 6.3 静默推送（后台）
```json
{
  "aps": {
    "content-available": 1
  },
  "action": "sync"
}
```

### 6.4 自定义消息
```json
{
  "aps": {
    "alert": {
      "title": "QuickClip",
      "body": "Server maintenance notice"
    },
    "sound": "default"
  },
  "action": "message",
  "message": "Maintenance from 2:00 AM to 4:00 AM UTC"
}
```

---

## 7. 测试计划

### 7.1 客户端测试

#### Test 1: APNs 注册
- [ ] 启动 App
- [ ] 查看控制台是否输出 Device Token
- [ ] 检查 UserDefaults 是否保存了 Token

#### Test 2: Token 上传到 CloudKit
- [ ] 启动 App（首次）
- [ ] 登录 CloudKit Dashboard
- [ ] 查看 UsingUsers 记录是否包含 token 字段
- [ ] 验证 token 值是否正确

#### Test 3: Token 更新
- [ ] 重启 App
- [ ] 检查 CloudKit 记录的 token 字段是否更新

#### Test 4: 接收推送
- [ ] 使用测试工具发送推送
- [ ] 查看 App 是否收到通知
- [ ] 检查控制台日志
- [ ] 验证 action 是否正确执行

### 7.2 服务器测试

#### Test 1: 查询 Token
- [ ] 运行查询脚本
- [ ] 验证返回的 Token 列表
- [ ] 检查 Token 格式是否正确

#### Test 2: 发送推送
- [ ] 发送测试推送
- [ ] 检查发送结果
- [ ] 验证客户端是否收到

#### Test 3: 失效 Token 处理
- [ ] 模拟失效 Token（删除 App）
- [ ] 发送推送
- [ ] 验证失效 Token 是否被清理

---

## 8. 监控和维护

### 8.1 监控指标

**CloudKit**:
- 总用户数（UsingUsers 记录数）
- 有效 Token 数（token 字段非空）
- Token 更新频率

**APNs**:
- 推送发送成功率
- 推送失败率
- 失效 Token 数量

### 8.2 维护任务

**定期清理**:
- 清理超过 90 天未活跃的 Token
- 删除失效的 Token

**脚本示例**:
```javascript
async function cleanupInactiveTokens() {
    const ninetyDaysAgo = new Date();
    ninetyDaysAgo.setDate(ninetyDaysAgo.getDate() - 90);

    const query = {
        recordType: 'UsingUsers',
        filterBy: [{
            fieldName: 'sendDate',
            comparator: CloudKit.QueryFilterComparator.LESS_THAN,
            fieldValue: { value: ninetyDaysAgo.getTime() }
        }]
    };

    // 查询并清除 token
    const response = await publicDB.performQuery(query);
    for (const record of response.records) {
        record.fields.token = { value: null };
    }
    await publicDB.saveRecords(response.records);

    console.log(`清理了 ${response.records.length} 个不活跃 Token`);
}
```

---

## 9. 安全和隐私

### 9.1 Token 安全
- ✅ Token 存储在 CloudKit Public Database（只能通过服务器访问）
- ✅ Token 不包含个人信息
- ✅ Token 与匿名 UID 关联

### 9.2 推送内容
- ⚠️ 避免在推送中包含敏感信息
- ✅ 使用通用提示语
- ✅ 详细信息在 App 内显示

### 9.3 用户控制
- ✅ 用户可以在系统设置中关闭通知权限
- ✅ 用户关闭 iCloud 同步后，token 仍会保留（用于发送更新通知）
- ✅ 卸载 App 后，Token 自动失效

---

## 10. 上线检查清单

### 客户端
- [ ] Push Notifications Capability 已添加
- [ ] Entitlements 正确配置
- [ ] PushNotificationManager 已创建
- [ ] UsageStatsManager 已修改（支持 token）
- [ ] QuickClipApp 已集成
- [ ] 真机测试通过
- [ ] Device Token 成功上传到 CloudKit

### CloudKit
- [ ] UsingUsers 添加了 token 字段
- [ ] Development 环境测试通过
- [ ] Production 环境 Schema 已部署

### 服务器
- [ ] CloudKit Web Services 配置完成
- [ ] APNs 证书/Key 准备就绪
- [ ] 查询 Token 脚本测试通过
- [ ] 发送推送脚本测试通过
- [ ] 失效 Token 清理机制已实现

### 文档
- [ ] 隐私政策已更新（说明推送通知）
- [ ] 服务器端文档完善
- [ ] 监控脚本准备就绪

---

## 11. 常见问题

### Q1: Token 什么时候会变化？
- 重新安装 App
- 系统重置
- 从备份恢复

### Q2: 如何测试生产环境推送？
- 使用 TestFlight 安装
- 或 Archive 后使用 Development 导出测试

### Q3: 推送延迟多久？
- 通常 1-30 秒
- 取决于网络和 APNs 负载

### Q4: 如何处理失效 Token？
- APNs 返回 status=410 时
- 从 CloudKit 清除该 Token

### Q5: CloudKit 查询有数量限制吗？
- 单次查询最多 200 条
- 使用 Cursor 分页查询

---

**文档版本**: v1.0
**最后更新**: 2025-12-13
**维护者**: QuickClip Team
