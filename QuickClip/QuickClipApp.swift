//
//  应用入口
//  快速剪贴
//
//  创建者：Brian He（2025/12/9）
//

import SwiftUI
import SwiftData
import CloudKit
import UserNotifications

@main
struct QuickClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Snippet.self,
        ])

        // 明确指定本地存储路径，禁用 SwiftData 自动 CloudKit 集成
        // 我们使用手动实现的 iCloudSyncManager 进行 CloudKit 同步
        let storeURL = URL.applicationSupportDirectory.appending(path: "QuickClip.store")
        let modelConfiguration = ModelConfiguration(
            schema: schema,
            url: storeURL,
            cloudKitDatabase: .none  // 禁用自动 CloudKit 集成
        )

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    appDelegate.setupManagers(modelContainer: sharedModelContainer)
                    if let window = NSApplication.shared.windows.first {
                        window.delegate = appDelegate
                        appDelegate.mainWindow = window
                    }
                }
        }
        .modelContainer(sharedModelContainer)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate,UNUserNotificationCenterDelegate {
    private var menuBarManager: MenuBarManager?
    private var hotKeyManager: HotKeyManager?
    weak var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置窗口关闭行为为隐藏而不是退出
        NSApplication.shared.windows.first?.delegate = self
        UNUserNotificationCenter.current().delegate = self
        // 注册 APNs
        PushNotificationManager.shared.registerForRemoteNotifications()

    }

    /// 上传用户统计数据到 CloudKit Public Database
    private func uploadUsageStats() async {
        let statsManager = UsageStatsManager()
        do {
            try await statsManager.uploadOrUpdateStats()
        } catch {
            print("⚠️ 统计上传失败: \(error.localizedDescription)")
        }
    }

    func setupManagers(modelContainer: ModelContainer) {
        let modelContext = ModelContext(modelContainer)

        menuBarManager = MenuBarManager(modelContext: modelContext) { [weak self] in
            self?.showMainWindow()
        }

        hotKeyManager = HotKeyManager(modelContext: modelContext)
        hotKeyManager?.setMenuBarManager(menuBarManager!)

        // 延迟注册快捷键，确保应用完全启动
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            print("🚀 App started. Registering hotkeys...")
            self?.hotKeyManager?.registerAllHotKeys()
        }

        // 监听快捷键更新通知（快捷键设置/清除）
        // 注意：菜单会在 menuWillOpen 时自动刷新，无需手动通知
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("HotKeysNeedUpdate"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            print("🔑 Hotkey update notification received")
            // 稍微延迟以确保数据已保存
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self?.hotKeyManager?.registerAllHotKeys()
            }
        }
    }

    func showMainWindow() {
        NSApplication.shared.setActivationPolicy(.regular)

        let app = NSApplication.shared
        let window = mainWindow ?? app.windows.first

        // 第一次激活
        NSRunningApplication.current.activate(options: [.activateAllWindows])
        app.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)

        // 延迟再次激活，确保菜单栏事件结束后仍能获取焦点
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSRunningApplication.current.activate(options: [.activateAllWindows])
            app.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        }
    }

    // MARK: - APNs Delegate Methods
    
    // ⭐ 关键：前台也展示通知
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async
        -> UNNotificationPresentationOptions {
        return [.banner, .sound, .list]
    }
    
    /// APNs 注册成功
    func application(_ application: NSApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        print("✅ APNs 注册成功，设备令牌已接收")
        PushNotificationManager.shared.didRegisterForRemoteNotifications(withDeviceToken: deviceToken)
        // 上传用户统计数据
        Task {
            await uploadUsageStats()
        }
    }

    /// APNs 注册失败
    func application(_ application: NSApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("❌ APNs 注册失败 \(error.localizedDescription)")
        PushNotificationManager.shared.didFailToRegisterForRemoteNotifications(withError: error)
        // 上传用户统计数据
        Task {
            await uploadUsageStats()
        }
    }

    /// 接收远程通知
    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {
        PushNotificationManager.shared.didReceiveRemoteNotification(userInfo)
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        NSApplication.shared.setActivationPolicy(.accessory)
        return false
    }
}
