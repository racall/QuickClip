//
//  菜单栏管理
//  快速剪贴
//
//  创建者：Brian He（2025/12/9）
//

import AppKit
import SwiftUI
import SwiftData

class MenuBarManager: NSObject, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private var modelContext: ModelContext
    private var showMainWindow: () -> Void
    private var feedbackTimer: Timer?
    private var menuUpdateObserver: NSObjectProtocol?

    init(modelContext: ModelContext, showMainWindow: @escaping () -> Void) {
        self.modelContext = modelContext
        self.showMainWindow = showMainWindow
        super.init()
        setupMenuBar()
        
        menuUpdateObserver = NotificationCenter.default.addObserver(
            forName: NSNotification.Name("MenuBarNeedUpdate"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.updateMenu()
        }
    }

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "QuickClip")
            button.image?.isTemplate = true
        }

        menu = NSMenu()
        menu?.delegate = self
        statusItem?.menu = menu

        updateMenu()
    }

    // 菜单代理方法（NSMenuDelegate）：菜单即将打开时刷新数据
    func menuWillOpen(_ menu: NSMenu) {
        print("🔄 Menu will open. Refreshing data")
        updateMenu()
    }

    func updateMenu() {
        guard let menu = menu else { return }

        menu.removeAllItems()

        // 获取前10个启用菜单栏显示的片段
        let fetchDescriptor = FetchDescriptor<Snippet>(
            predicate: #Predicate { $0.showInMenuBar == true },
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )

        do {
            let snippets = try modelContext.fetch(fetchDescriptor)
            let topSnippets = Array(snippets.prefix(10))

            if topSnippets.isEmpty {
                let noSnippetsItem = NSMenuItem(title: "No menu bar snippets", action: nil, keyEquivalent: "")
                noSnippetsItem.isEnabled = false
                menu.addItem(noSnippetsItem)
            } else {
                for snippet in topSnippets {
                    let title = snippet.title.isEmpty ? "Untitled" : snippet.title
                    let displayTitle = "\(title)"

                    let menuItem = NSMenuItem(
                        title: displayTitle,
                        action: #selector(snippetMenuItemClicked(_:)),
                        keyEquivalent: ""
                    )
                    menuItem.target = self
                    menuItem.representedObject = snippet.id
                    menuItem.toolTip = String(snippet.content.prefix(100))

                    if let shortcut = snippet.shortcutKey, !shortcut.isEmpty {
                        menuItem.title += " [\(shortcut)]"
                    }

                    menu.addItem(menuItem)
                }
            }

            menu.addItem(NSMenuItem.separator())

            // 打开主界面
            let openItem = NSMenuItem(
                title: "Open QuickClip",
                action: #selector(openMainWindow),
                keyEquivalent: "o"
            )
            openItem.target = self
            menu.addItem(openItem)

            // 退出应用
            let quitItem = NSMenuItem(
                title: "Quit",
                action: #selector(quitApp),
                keyEquivalent: "q"
            )
            quitItem.target = self
            menu.addItem(quitItem)

        } catch {
            print("Failed to fetch snippets: \(error)")
        }
    }

    @objc private func snippetMenuItemClicked(_ sender: NSMenuItem) {
        guard let snippetId = sender.representedObject as? UUID else { return }

        let fetchDescriptor = FetchDescriptor<Snippet>(
            predicate: #Predicate { $0.id == snippetId }
        )

        do {
            if let snippet = try modelContext.fetch(fetchDescriptor).first {
                ClipboardHelper.copyToClipboard(snippet.content)
                showCopyFeedback()
            }
        } catch {
            print("Failed to fetch snippet: \(error)")
        }
    }

    @objc private func openMainWindow() {
        showMainWindow()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func showCopyFeedback() {
        feedbackTimer?.invalidate()

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "checkmark.circle.fill", accessibilityDescription: "Copied")

            feedbackTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { _ in
                button.image = NSImage(systemSymbolName: "doc.on.clipboard", accessibilityDescription: "QuickClip")
                button.image?.isTemplate = true
            }
        }
    }
    
    deinit {
        if let menuUpdateObserver = menuUpdateObserver {
            NotificationCenter.default.removeObserver(menuUpdateObserver)
        }
    }
}
