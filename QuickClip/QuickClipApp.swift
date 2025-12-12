//
//  应用入口
//  快速剪贴
//
//  创建者：Brian He（2025/12/9）
//

import SwiftUI
import SwiftData

@main
struct QuickClipApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Snippet.self,
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

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

class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarManager: MenuBarManager?
    private var hotKeyManager: HotKeyManager?
    weak var mainWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // 设置窗口关闭行为为隐藏而不是退出
        NSApplication.shared.windows.first?.delegate = self
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
        NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
        app.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)

        // 延迟再次激活，确保菜单栏事件结束后仍能获取焦点
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            NSRunningApplication.current.activate(options: [.activateAllWindows, .activateIgnoringOtherApps])
            app.activate(ignoringOtherApps: true)
            window?.makeKeyAndOrderFront(nil)
        }
    }
}

extension AppDelegate: NSWindowDelegate {
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        NSApplication.shared.setActivationPolicy(.accessory)
        return false
    }
}
