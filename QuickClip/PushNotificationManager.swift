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

    /// Device Token（十六进制字符串）
    private(set) var deviceToken: String? {
        didSet {
            if let token = deviceToken {
//                UserDefaults.standard.set(token, forKey: "apnsDeviceToken")
                print("✅ APNs Device Token: \(token)")
            }
        }
    }

    // MARK: - 初始化

    private override init() {
        super.init()

        // 恢复保存的 token
//        if let savedToken = UserDefaults.standard.string(forKey: "apnsDeviceToken") {
//            self.deviceToken = savedToken
//        }
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
            } else {
                print(granted ? "✅ 通知权限已授予" : "⚠️ 用户拒绝了通知权限")
            }
        }
        // 注册 APNs（无论权限是否授予，都注册以获取 token）
        DispatchQueue.main.async {
            NSApplication.shared.registerForRemoteNotifications()
        }
    }

    /// APNs 注册成功
    func didRegisterForRemoteNotifications(withDeviceToken deviceToken: Data) {
        // 转换为十六进制字符串
        let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
        self.deviceToken = token
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

    /// 处理推送通知内容
    private func handleAPSPayload(_ aps: [String: Any], userInfo: [String: Any]) {
        // 1. 提取标准 APS 字段
        var title = "QuickClip"
        var body = ""

        if let alert = aps["alert"] as? String {
            body = alert
            print("📝 通知内容: \(alert)")
        } else if let alertDict = aps["alert"] as? [String: Any] {
            title = alertDict["title"] as? String ?? "QuickClip"
            body = alertDict["body"] as? String ?? ""
            print("📝 通知标题: \(title)")
            print("📝 通知内容: \(body)")
        }

        if let badge = aps["badge"] as? Int {
            print("🔴 角标数: \(badge)")
            // 设置应用角标
            NSApplication.shared.dockTile.badgeLabel = badge > 0 ? "\(badge)" : nil
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
            handleNotificationAction(action, data: userInfo, title: title, body: body)
        }
    }

    /// 处理通知触发的操作
    private func handleNotificationAction(_ action: String, data: [String: Any], title: String, body: String) {
        print("🎬 执行操作: \(action)")

        switch action {
        case "update":
            // 提示用户更新
            if let version = data["version"] as? String {
                let url = data["url"] as? String
                showUpdateAlert(version: version, url: url)
            }

        case "message":
            // 显示自定义消息
            if let message = data["message"] as? String {
                showMessage(title: title, message: message)
            } else {
                // 使用 body 作为消息
                showMessage(title: title, message: body)
            }

        case "url":
            // 打开 URL
            if let urlString = data["url"] as? String,
               let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }

        default:
            print("⚠️ 未知操作: \(action)")
        }
    }

    /// 显示更新提示
    private func showUpdateAlert(version: String, url: String?) {
        let alert = NSAlert()
        alert.messageText = "New Version Available"
        alert.informativeText = "QuickClip \(version) is now available. Would you like to update?"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Later")

        if alert.runModal() == .alertFirstButtonReturn {
            // 打开下载链接
            let urlString = url ?? "https://apps.apple.com/app/quickclip/idXXXXXXXXXX"
            if let downloadURL = URL(string: urlString) {
                NSWorkspace.shared.open(downloadURL)
            }
        }
    }

    /// 显示消息提示
    private func showMessage(title: String, message: String) {
        let alert = NSAlert()
        alert.messageText = title
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

        let userInfo = notification.request.content.userInfo as! [String: Any]
        didReceiveRemoteNotification(userInfo)

        // 在前台也显示通知横幅
        completionHandler([.banner, .sound, .badge])
    }

    /// 用户点击通知
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        print("👆 用户点击了通知")

        let userInfo = response.notification.request.content.userInfo as! [String: Any]
        didReceiveRemoteNotification(userInfo)

        completionHandler()
    }
}
