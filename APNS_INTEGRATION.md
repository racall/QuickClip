# APNs 推送通知接入方案

## 1. 概述

QuickClip 接入 APNs (Apple Push Notification service)，用于接收来自服务器的推送通知。

---

## 2. 客户端实现

### 2.1 Xcode 配置

#### Step 1: 添加 Push Notifications Capability
```
Xcode → 项目设置 → Signing & Capabilities
→ 点击 "+ Capability"
→ 添加 "Push Notifications"
```

#### Step 2: 修改 Entitlements
**文件**: `QuickClip.entitlements`

添加以下内容：
```xml
<!-- Push Notifications -->
<key>aps-environment</key>
<string>development</string>
```

**注意**:
- 开发环境使用 `development`
- 上线到 App Store 后自动变为 `production`

---

### 2.2 代码实现

#### 文件 1: `PushNotificationManager.swift` (新建)

**功能**: 管理 APNs 注册、token 上传、通知处理

```swift
//
//  推送通知管理器
//  快速剪贴
//
//  创建者：Brian He（2025/12/13）
//

import Foundation
import UserNotifications
import AppKit

/// 推送通知管理器
@MainActor
final class PushNotificationManager: NSObject {

    // MARK: - 单例

    static let shared = PushNotificationManager()

    // MARK: - 属性

    /// 服务器 API 地址（需要替换为你的服务器地址）
    private let serverURL = "https://your-api.com/apns/register"

    /// Device Token（十六进制字符串）
    private(set) var deviceToken: String? {
        didSet {
            if let token = deviceToken {
                UserDefaults.standard.set(token, forKey: "apnsDeviceToken")
                print("✅ Device Token 已保存: \(token)")
            }
        }
    }

    /// 是否已上传 token 到服务器
    private var hasUploadedToken: Bool {
        get { UserDefaults.standard.bool(forKey: "hasUploadedAPNsToken") }
        set { UserDefaults.standard.set(newValue, forKey: "hasUploadedAPNsToken") }
    }

    // MARK: - 初始化

    private override init() {
        super.init()

        // 恢复保存的 token
        if let savedToken = UserDefaults.standard.string(forKey: "apnsDeviceToken") {
            self.deviceToken = savedToken
        }
    }

    // MARK: - 公开接口

    /// 注册远程通知
    func registerForRemoteNotifications() {
        print("📱 开始注册 APNs...")

        let center = UNUserNotificationCenter.current()
        center.delegate = self

        // 请求通知权限
        center.requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            if let error = error {
                print("❌ 通知权限请求失败: \(error.localizedDescription)")
                return
            }

            if granted {
                print("✅ 通知权限已授予")
            } else {
                print("⚠️ 用户拒绝了通知权限")
            }

            // 注册 APNs（无论权限是否授予，都注册以获取 token）
            DispatchQueue.main.async {
                NSApplication.shared.registerForRemoteNotifications()
            }
        }
    }

    /// APNs 注册成功
    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        // 转换为十六进制字符串
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        self.deviceToken = token

        print("✅ APNs Device Token: \(token)")

        // 上传到服务器
        uploadTokenToServer(token)
    }

    /// APNs 注册失败
    func didFailToRegisterForRemoteNotifications(withError error: Error) {
        print("❌ APNs 注册失败: \(error.localizedDescription)")
    }

    /// 接收远程通知
    func didReceiveRemoteNotification(_ userInfo: [String: Any]) {
        print("📬 收到远程通知: \(userInfo)")

        // 解析通知内容
        if let aps = userInfo["aps"] as? [String: Any] {
            handleAPSPayload(aps, userInfo: userInfo)
        }
    }

    // MARK: - 私有方法

    /// 上传 Device Token 到服务器
    private func uploadTokenToServer(_ token: String) {
        // 避免重复上传
        if hasUploadedToken {
            print("ℹ️ Token 已上传过，跳过")
            return
        }

        guard let url = URL(string: serverURL) else {
            print("❌ 服务器 URL 无效")
            return
        }

        // 构建请求
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // 构建请求体
        let payload: [String: Any] = [
            "device_token": token,
            "platform": "macos",
            "app_version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown",
            "os_version": ProcessInfo.processInfo.operatingSystemVersionString,
            "timestamp": Date().timeIntervalSince1970
        ]

        do {
            request.httpBody = try JSONSerialization.data(withJSONObject: payload)
        } catch {
            print("❌ JSON 序列化失败: \(error)")
            return
        }

        // 发送请求
        Task {
            do {
                let (data, response) = try await URLSession.shared.data(for: request)

                if let httpResponse = response as? HTTPURLResponse {
                    if httpResponse.statusCode == 200 {
                        print("✅ Device Token 已上传到服务器")
                        hasUploadedToken = true

                        // 解析响应（可选）
                        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                            print("📥 服务器响应: \(json)")
                        }
                    } else {
                        print("⚠️ 服务器返回错误: \(httpResponse.statusCode)")
                    }
                }
            } catch {
                print("❌ 上传 Token 失败: \(error.localizedDescription)")
            }
        }
    }

    /// 处理推送通知内容
    private func handleAPSPayload(_ aps: [String: Any], userInfo: [String: Any]) {
        // 1. 提取标准 APS 字段
        if let alert = aps["alert"] as? String {
            print("📝 通知内容: \(alert)")
        } else if let alertDict = aps["alert"] as? [String: Any] {
            let title = alertDict["title"] as? String ?? ""
            let body = alertDict["body"] as? String ?? ""
            print("📝 通知标题: \(title)")
            print("📝 通知内容: \(body)")
        }

        if let badge = aps["badge"] as? Int {
            print("🔴 角标数: \(badge)")
        }

        if let sound = aps["sound"] as? String {
            print("🔊 声音: \(sound)")
        }

        // 2. 提取自定义数据
        for (key, value) in userInfo {
            if key != "aps" {
                print("🔖 自定义数据 [\(key)]: \(value)")
            }
        }

        // 3. 根据自定义字段执行相应操作
        if let action = userInfo["action"] as? String {
            handleNotificationAction(action, data: userInfo)
        }
    }

    /// 处理通知触发的操作
    private func handleNotificationAction(_ action: String, data: [String: Any]) {
        print("🎬 执行操作: \(action)")

        switch action {
        case "sync":
            // 触发同步
            NotificationCenter.default.post(
                name: NSNotification.Name("TriggerSync"),
                object: nil,
                userInfo: data
            )

        case "update":
            // 提示用户更新
            if let version = data["version"] as? String {
                showUpdateAlert(version: version)
            }

        case "message":
            // 显示消息
            if let message = data["message"] as? String {
                showMessage(message)
            }

        default:
            print("⚠️ 未知操作: \(action)")
        }
    }

    /// 显示更新提示
    private func showUpdateAlert(version: String) {
        let alert = NSAlert()
        alert.messageText = "New Version Available"
        alert.informativeText = "QuickClip \(version) is available. Would you like to update?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            // 打开 App Store 或下载链接
            if let url = URL(string: "https://your-website.com/download") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    /// 显示消息提示
    private func showMessage(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "QuickClip"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}

// MARK: - UNUserNotificationCenterDelegate

extension PushNotificationManager: UNUserNotificationCenterDelegate {

    /// App 在前台时收到通知
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        print("📬 前台收到通知")

        let userInfo = notification.request.content.userInfo
        didReceiveRemoteNotification(userInfo)

        // 在前台也显示通知
        completionHandler([.banner, .sound, .badge])
    }

    /// 用户点击通知
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        print("👆 用户点击了通知")

        let userInfo = response.notification.request.content.userInfo
        didReceiveRemoteNotification(userInfo)

        completionHandler()
    }
}
```

---

#### 文件 2: 修改 `QuickClipApp.swift`

在 `AppDelegate` 中集成推送通知：

```swift
import UserNotifications  // 添加导入

class AppDelegate: NSObject, NSApplicationDelegate {
    // ... 现有代码

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置窗口关闭行为为隐藏而不是退出
        NSApplication.shared.windows.first?.delegate = self

        // 上传用户统计数据
        Task {
            await uploadUsageStats()
        }

        // ✅ 注册 APNs
        PushNotificationManager.shared.registerForRemoteNotifications()
    }

    // ✅ APNs 注册成功
    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        PushNotificationManager.shared.didRegisterForRemoteNotifications(withDeviceToken: deviceToken)
    }

    // ✅ APNs 注册失败
    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushNotificationManager.shared.didFailToRegisterForRemoteNotifications(withError: error)
    }

    // ✅ 接收远程通知
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String : Any]) {
        PushNotificationManager.shared.didReceiveRemoteNotification(userInfo)
    }

    // ... 现有代码
}
```

---

## 3. 服务器端实现

### 3.1 接收 Device Token

#### API 端点: `POST /apns/register`

**请求格式**:
```json
{
  "device_token": "a1b2c3d4e5f6...",
  "platform": "macos",
  "app_version": "1.0.0",
  "os_version": "Version 14.0 (Build 23A344)",
  "timestamp": 1702468800.0
}
```

**响应格式**:
```json
{
  "status": "success",
  "message": "Device token registered successfully"
}
```

#### 数据库存储

建议存储的字段：
```sql
CREATE TABLE apns_tokens (
    id SERIAL PRIMARY KEY,
    device_token VARCHAR(100) UNIQUE NOT NULL,
    platform VARCHAR(20) NOT NULL,
    app_version VARCHAR(20),
    os_version VARCHAR(100),
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);
```

---

### 3.2 发送推送通知

#### 推送格式

**基本格式**:
```json
{
  "aps": {
    "alert": {
      "title": "QuickClip",
      "body": "Your message here"
    },
    "badge": 1,
    "sound": "default"
  },
  "action": "sync",
  "custom_data": "your custom data"
}
```

**静默推送格式**:
```json
{
  "aps": {
    "content-available": 1
  },
  "action": "sync",
  "data": {
    "key": "value"
  }
}
```

#### 使用 Node.js 发送推送

安装依赖：
```bash
npm install apn
```

示例代码：
```javascript
const apn = require('apn');

// 配置 APNs
const options = {
  token: {
    key: './AuthKey_XXXXXXXXXX.p8',  // 从 Apple Developer 下载
    keyId: 'XXXXXXXXXX',              // Key ID
    teamId: 'XXXXXXXXXX'              // Team ID
  },
  production: false  // 开发环境为 false，生产环境为 true
};

const apnProvider = new apn.Provider(options);

// 发送推送
function sendPush(deviceToken, message) {
  const notification = new apn.Notification();

  notification.alert = {
    title: 'QuickClip',
    body: message
  };
  notification.topic = 'io.0os.QuickClip';  // Bundle ID
  notification.badge = 1;
  notification.sound = 'default';

  // 自定义数据
  notification.payload = {
    action: 'sync',
    timestamp: Date.now()
  };

  apnProvider.send(notification, deviceToken).then(result => {
    console.log('Push sent:', result);
  }).catch(err => {
    console.error('Push error:', err);
  });
}

// 使用示例
sendPush('a1b2c3d4e5f6...', 'Your data has been synced!');
```

#### 使用 Python 发送推送

安装依赖：
```bash
pip install pyapns2
```

示例代码：
```python
from apns2.client import APNsClient
from apns2.payload import Payload

# 配置
token_hex = 'a1b2c3d4e5f6...'
bundle_id = 'io.0os.QuickClip'

# 创建客户端
client = APNsClient(
    './AuthKey_XXXXXXXXXX.p8',
    key_id='XXXXXXXXXX',
    team_id='XXXXXXXXXX',
    use_sandbox=True  # 开发环境
)

# 创建 Payload
payload = Payload(
    alert={
        'title': 'QuickClip',
        'body': 'Your message here'
    },
    badge=1,
    sound='default',
    custom={
        'action': 'sync',
        'timestamp': 1702468800
    }
)

# 发送推送
client.send_notification(token_hex, payload, bundle_id)
```

---

## 4. APNs 证书配置

### 4.1 创建 APNs Auth Key（推荐）

**步骤**:
1. 登录 [Apple Developer](https://developer.apple.com/)
2. Certificates, Identifiers & Profiles → Keys
3. 点击 "+" 创建新 Key
4. 勾选 "Apple Push Notifications service (APNs)"
5. 下载 `.p8` 文件（只能下载一次，妥善保管）
6. 记录 Key ID 和 Team ID

**优点**:
- 永不过期
- 可用于所有 App
- 配置简单

### 4.2 使用证书（传统方式）

**步骤**:
1. 创建 CSR (Certificate Signing Request)
2. 在 Apple Developer 创建 APNs SSL 证书
3. 下载证书并导出为 .p12 文件

**缺点**:
- 每年需要更新
- 每个 App 需要单独配置

---

## 5. 测试

### 5.1 测试工具

#### Pusher（推荐）
- 下载: [https://github.com/noodlewerk/NWPusher](https://github.com/noodlewerk/NWPusher)
- 功能: 图形化界面，方便测试
- 支持: Certificate 和 Token 认证

#### 命令行测试
使用 curl：
```bash
curl -v \
  -H "apns-topic: io.0os.QuickClip" \
  -H "apns-push-type: alert" \
  --http2 \
  --cert ./apns_cert.pem \
  -d '{"aps":{"alert":"Test message"}}' \
  https://api.sandbox.push.apple.com/3/device/DEVICE_TOKEN
```

### 5.2 测试步骤

1. **真机测试**（模拟器不支持 APNs）
   - 在真机上运行 Debug 版本
   - 查看控制台是否输出 Device Token
   - 确认 Token 已上传到服务器

2. **发送测试推送**
   - 使用 Pusher 或服务器 API 发送推送
   - 查看 App 是否收到通知
   - 检查控制台日志

3. **前台/后台测试**
   - App 在前台：应显示通知横幅
   - App 在后台：应在通知中心显示
   - App 未运行：启动后应接收通知

---

## 6. 推送通知格式示例

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
    "sound": "default"
  },
  "action": "update",
  "version": "1.1.0",
  "url": "https://your-website.com/download"
}
```

### 6.3 静默推送（后台同步）
```json
{
  "aps": {
    "content-available": 1
  },
  "action": "sync",
  "data": {
    "sync_type": "background"
  }
}
```

### 6.4 自定义消息
```json
{
  "aps": {
    "alert": {
      "title": "QuickClip",
      "body": "Server maintenance scheduled"
    },
    "badge": 1,
    "sound": "default"
  },
  "action": "message",
  "message": "QuickClip will be under maintenance from 2:00 AM to 4:00 AM UTC.",
  "priority": "high"
}
```

---

## 7. 常见问题

### Q1: 为什么收不到推送？
**检查清单**:
- [ ] 是否在真机上测试（模拟器不支持）
- [ ] 是否成功注册 APNs（检查 Device Token）
- [ ] 环境是否匹配（开发/生产）
- [ ] Bundle ID 是否正确
- [ ] 证书/Key 是否有效

### Q2: Device Token 什么时候会变化？
- 重新安装 App
- 系统重置
- 从备份恢复

### Q3: 推送延迟多久？
- 通常 1-30 秒
- 取决于网络状况和 Apple 服务器负载

### Q4: 如何测试生产环境？
- Archive 并上传到 TestFlight
- 从 TestFlight 安装测试

---

## 8. 安全建议

### 8.1 Device Token 保护
- 使用 HTTPS 传输
- 服务器端加密存储
- 定期清理失效 Token

### 8.2 Auth Key 保护
- 妥善保管 .p8 文件
- 不要提交到代码仓库
- 限制服务器访问权限

### 8.3 推送内容
- 避免在推送中包含敏感信息
- 使用加密（如有必要）
- 控制推送频率，避免骚扰用户

---

## 9. 隐私政策更新

建议在隐私政策中添加：

```markdown
## 推送通知

QuickClip 使用 Apple Push Notification service (APNs) 向您发送通知：

### 收集的信息
- Device Token（用于识别您的设备）
- 设备平台（macOS）
- App 版本号
- 系统版本

### 使用目的
- 发送同步提醒
- 通知版本更新
- 发送重要消息

### 数据保护
- Device Token 通过 HTTPS 加密传输
- 存储在我们的服务器中，采用加密措施
- 不会与第三方共享

### 用户控制
- 您可以在系统设置中关闭通知权限
- 卸载 App 后，Token 将自动失效
```

---

## 10. 上线检查清单

- [ ] Push Notifications Capability 已添加
- [ ] Entitlements 文件正确配置
- [ ] Device Token 上传 API 已实现
- [ ] 服务器已配置 APNs 证书/Key
- [ ] 推送发送功能已测试
- [ ] 前台/后台通知接收已测试
- [ ] 真机测试通过
- [ ] 隐私政策已更新
- [ ] 用户通知权限请求已实现

---

**文档版本**: v1.0
**最后更新**: 2025-12-13
**维护者**: QuickClip Team
