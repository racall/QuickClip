//
//  设置界面视图
//  快速剪贴
//
//  创建者：Brian He（2025/12/13）
//

import SwiftUI
import SwiftData

/// 设置界面视图
struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \Snippet.createdAt, order: .reverse) private var allSnippets: [Snippet]

    @StateObject private var viewModel: SettingsViewModel

    let onDidClearAll: () -> Void

    init(onDidClearAll: @escaping () -> Void) {
        self.onDidClearAll = onDidClearAll
        // 创建临时 viewModel，实际初始化在 onAppear 中完成
        _viewModel = StateObject(wrappedValue: SettingsViewModel(
            modelContext: ModelContext(ModelContainer.shared),
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
        .frame(width: 520, height: 320)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            // 使用真实的 modelContext 和 allSnippets 更新 viewModel
            viewModel.updateData(modelContext: modelContext, allSnippets: allSnippets)
        }
        .onChange(of: allSnippets) { _, _ in
            viewModel.updateData(modelContext: modelContext, allSnippets: allSnippets)
        }
    }
}

// MARK: - ModelContainer 扩展

extension ModelContainer {
    /// 共享的 ModelContainer 实例
    static var shared: ModelContainer = {
        do {
            return try ModelContainer(for: Snippet.self)
        } catch {
            fatalError("Failed to create ModelContainer: \(error)")
        }
    }()
}
