//
//  设置界面视图
//  快速剪贴
//
//  创建者：Brian He（2025/12/13）
//

import SwiftUI
import SwiftData
import UserNotifications

/// 设置界面视图
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Snippet.createdAt, order: .reverse) private var allSnippets: [Snippet]

    @StateObject private var viewModel: SettingsViewModel

    let onDidClearAll: () -> Void

    init(onDidClearAll: @escaping () -> Void) {
        self.onDidClearAll = onDidClearAll
        // ✅ 创建临时 viewModel，在 onAppear 中注入真实的 modelContext
        _viewModel = StateObject(wrappedValue: SettingsViewModel(
            modelContext: nil,  // 延迟初始化
            allSnippets: [],
            onDidClearAll: onDidClearAll
        ))
    }

    var body: some View {
        VStack(spacing: 0) {
            // 标题栏
            HStack(spacing: 12) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                        .frame(width: 20, height: 20)
                        .background(
                            Circle()
                                .fill(Color(nsColor: .controlBackgroundColor))
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
                .pointerStyle(.link)
                
                Text("Settings")
                    .font(.title2.weight(.semibold))
                Spacer()
                
            }
            .padding(20)

            Divider()

            // 主内容区
            VStack(spacing: 0) {
                // 通知权限
                HStack(alignment: .center) {
                    HStack(spacing: 4) {
                        Image(systemName: "bell.badge")
                        Text("Notification Permission")
                            .foregroundColor(.primary)
                    }
                    Spacer()

                    // 根据权限状态显示不同的UI
                    if viewModel.notificationAuthorizationStatus == .authorized {
                        Text("Enabled")
                            .foregroundColor(.green)
                    } else {
                        Button {
                            viewModel.openNotificationSettings()
                        } label: {
                            Text("Open Settings")
                        }
                    }
                }
                .padding(12)

                Divider()

                // 清空数据
                HStack(alignment: .center) {
                    HStack(spacing:4){
                        Image(systemName: "trash")
                        Text("Clear all data")
                            .foregroundColor(.primary)
                    }
                    Spacer()
                    Button(role: .destructive) {
                        viewModel.showClearConfirmation = true
                    } label: {
                        Text("Clear")
                            .foregroundColor(.red)
                    }
                    .help("Deletes all snippets and removes all hotkey registrations.")
                    .confirmationDialog(
                        "Clear all data?",
                        isPresented: $viewModel.showClearConfirmation,
                        titleVisibility: .visible
                    ) {
                        Button("Clear All", role: .destructive) {
                            viewModel.clearAllData()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This action cannot be undone.")
                    }
                }
                .padding(12)
                Divider()

                // 导出 JSON
                HStack(alignment: .center) {
                    HStack(spacing:4){
                        Image(systemName: "square.and.arrow.up")
                        Text("Export to JSON")
                            .foregroundColor(.primary)
                    }
                    Spacer()
                    Button {
                        viewModel.exportToJSON()
                    } label: {
                        Text("Export to JSON")
                    }
                }
                .padding(12)

                Divider()

                // 导入 JSON
                HStack(alignment: .center) {
                    HStack(spacing:4){
                        Image(systemName: "square.and.arrow.down")
                        Text("Import from JSON")
                            .foregroundColor(.primary)
                    }
                    Spacer()
                    Button {
                        viewModel.importFromJSON()
                    } label: {
                        Text("Import from JSON")
                    }
                    
                }
                .padding(12)

                Divider()

                // iCloud 同步区域
                VStack(spacing: 0) {
                    // iCloud 开关
                    HStack(alignment: .center) {
                        HStack(spacing: 4) {
                            Image(systemName: "icloud")
                            Text("iCloud Sync")
                                .foregroundColor(.primary)
                        }
                        Spacer()
                        Toggle("", isOn: $viewModel.iCloudSyncEnabled)
                            .toggleStyle(.switch)
                            .labelsHidden()
                            .disabled(viewModel.isSyncing)
                    }
                    .padding(12)

                    // 手动同步按钮
                    if viewModel.iCloudSyncEnabled {
                        Divider()

                        HStack(alignment: .center) {
                            HStack(spacing: 4) {
                                Image(systemName: "arrow.triangle.2.circlepath")
                                Text("Manual Sync")
                                    .foregroundColor(.primary)
                            }
                            Spacer()
                            Button {
                                Task {
                                    await viewModel.manualSync()
                                }
                            } label: {
                                Text(viewModel.isSyncing ? "Syncing..." : "Sync Now")
                            }
                            .disabled(viewModel.isSyncing)
                        }
                        .padding(12)

                        // 同步进度
                        if !viewModel.syncProgress.isEmpty {
                            HStack {
                                Text(viewModel.syncProgress)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                        }

                        // 最后同步时间
                        if let lastSync = viewModel.lastSyncTime {
                            HStack {
                                Text("Last synced: \(lastSync, formatter: Self.dateFormatter)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            .padding(.horizontal, 12)
                            .padding(.bottom, 8)
                        }
                    }
                }

                Divider()

                // 状态消息
                if !viewModel.statusMessage.isEmpty {
                    HStack {
                        Text(viewModel.statusMessage)
                            .font(.callout)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                        Spacer()
                    }
                }

                Spacer(minLength: 0)
            }
        }
        .frame(width: 520, height: viewModel.iCloudSyncEnabled ? 480 : 400)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            // 使用真实的 modelContext 和 allSnippets 更新 viewModel
            viewModel.updateData(modelContext: modelContext, allSnippets: allSnippets)

            // 检查通知权限状态
            Task {
                await viewModel.checkNotificationAuthorization()
            }
        }
        .onChange(of: allSnippets) { _, _ in
            viewModel.updateData(modelContext: modelContext, allSnippets: allSnippets)
        }
    }

    // 日期格式化器
    private static var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
}
