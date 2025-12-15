//
//  片段列表视图
//  快速剪贴
//
//  创建者：Brian He（2025/12/9）
//

import SwiftUI
import SwiftData

struct SnippetListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Snippet.createdAt, order: .reverse) private var allSnippets: [Snippet]

    @State private var searchText: String = ""
    @State private var pendingScrollToSnippetID: UUID?
    @State private var cloudDeleteError: String?  // 云端删除错误消息
    @State private var showCloudDeleteError = false  // 显示错误对话框
    @State private var deletingSnippetIDs: Set<UUID> = []  // 正在删除的片段 ID 集合
    @Binding var selectedSnippet: Snippet?
    @Binding var isShowingSettings: Bool

    var filteredSnippets: [Snippet] {
        if searchText.isEmpty {
            return allSnippets
        } else {
            return allSnippets.filter { snippet in
                snippet.title.localizedCaseInsensitiveContains(searchText) ||
                snippet.content.localizedCaseInsensitiveContains(searchText)
            }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            VStack(spacing: 0) {
                // 搜索框
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Search snippets", text: $searchText)
                        .textFieldStyle(.plain)
                    if !searchText.isEmpty {
                        Button {
                            searchText = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(8)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(6)
                .padding()

                // 片段列表
                List(selection: $selectedSnippet) {
                    ForEach(filteredSnippets) { snippet in
                        SnippetRowView(
                            snippet: snippet,
                            isDeleting: deletingSnippetIDs.contains(snippet.id),
                            onDelete: { deleteSnippet(snippet) }
                        )
                        .id(snippet.id)
                        .tag(snippet)
                    }
                }
                .listStyle(.sidebar)
                .onChange(of: selectedSnippet?.id) { _, newSelectedID in
                    guard let targetID = pendingScrollToSnippetID, targetID == newSelectedID else { return }
                    pendingScrollToSnippetID = nil
                    DispatchQueue.main.async {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            proxy.scrollTo(targetID, anchor: .center)
                        }
                    }
                }

                // 底部工具栏
                Divider()
                HStack {
                Button {
                    addNewSnippet()
                } label: {
                    Label("New Snippet", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)

                    Spacer()

                Text("\(filteredSnippets.count) snippets")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.trailing, 8)

                    Button {
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 12)
                    .help("Settings")
                    .pointerStyle(.link)
            }
            .background(Color.gray.opacity(0.05))
            }
        }
        .alert("Failed to Delete from iCloud", isPresented: $showCloudDeleteError) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Could not delete snippet from iCloud: \(cloudDeleteError ?? "Unknown error"). The local copy has been preserved. Please try again later or check your network connection.")
        }
    }

    private func addNewSnippet() {
        let newSnippet = Snippet()
        modelContext.insert(newSnippet)
        pendingScrollToSnippetID = newSnippet.id
        selectedSnippet = newSnippet

        // 保存到本地
        try? modelContext.save()

        // iCloud 同步：上传新片段
        syncNewSnippetToiCloud(newSnippet)

        // 数据已保存，菜单会在打开时自动刷新
    }

    private func deleteSnippet(_ snippet: Snippet) {
        print("🗑️ Delete snippet: \(snippet.title)")

        let hasHotKey = snippet.shortcutKey != nil
        let cloudRecordID = snippet.cloudRecordID
        let snippetID = snippet.id

        // 如果当前选中的是这个片段，清除选中状态
        if selectedSnippet?.id == snippet.id {
            selectedSnippet = nil
        }

        // ✅ 先尝试删除云端（如果有记录且 iCloud 已开启）
        if let recordID = cloudRecordID, UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") {
            // ✅ 标记为正在删除
            deletingSnippetIDs.insert(snippetID)

            Task { @MainActor in
                do {
                    let syncManager = iCloudSyncManager(modelContext: modelContext)
                    try await syncManager.deleteCloudRecord(recordName: recordID)
                    print("✅ 云端记录已删除: \(recordID)")

                    // ✅ 云端删除成功，再删除本地
                    deleteSnippetLocally(snippet, hasHotKey: hasHotKey)

                    // ✅ 移除删除标记
                    deletingSnippetIDs.remove(snippetID)
                } catch {
                    print("❌ 删除云端片段失败: \(error.localizedDescription)")
                    // ✅ 移除删除标记
                    deletingSnippetIDs.remove(snippetID)

                    // ✅ 云端删除失败，显示错误提示，不删除本地
                    cloudDeleteError = error.localizedDescription
                    showCloudDeleteError = true
                }
            }
        } else {
            // 没有云端记录或 iCloud 未开启，直接删除本地
            deleteSnippetLocally(snippet, hasHotKey: hasHotKey)
        }
    }

    /// 删除本地片段
    private func deleteSnippetLocally(_ snippet: Snippet, hasHotKey: Bool) {
        modelContext.delete(snippet)
        try? modelContext.save()

        if hasHotKey {
            print("📣 Snippet has a hotkey. Posting hotkey update notification.")
            NotificationCenter.default.post(name: NSNotification.Name("HotKeysNeedUpdate"), object: nil)
        }
        // 菜单会在打开时自动刷新，无需手动通知
    }

    // MARK: - iCloud 同步

    /// 上传新片段到 iCloud
    private func syncNewSnippetToiCloud(_ snippet: Snippet) {
        // 检查 iCloud 是否开启
        guard UserDefaults.standard.bool(forKey: "iCloudSyncEnabled") else {
            return
        }

        Task { @MainActor in
            do {
                let syncManager = iCloudSyncManager(modelContext: modelContext)
                try await syncManager.uploadSnippet(snippet)
                print("✅ 新片段已上传到 iCloud: \(snippet.title)")
            } catch {
                print("❌ 上传片段失败: \(error.localizedDescription)")
            }
        }
    }
}

struct SnippetRowView: View {
    let snippet: Snippet
    let isDeleting: Bool  // ✅ 是否正在删除
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 8) {
            Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
                .font(.headline)
                .foregroundColor(snippet.title.isEmpty ? .secondary : .primary)
                .lineLimit(1)
                .opacity(isDeleting ? 0.5 : 1.0)  // ✅ 删除时半透明

            Spacer()

            if let shortcut = snippet.shortcutKey, !shortcut.isEmpty {
                Text(shortcut)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2))
                    .cornerRadius(4)
                    .opacity(isDeleting ? 0.5 : 1.0)  // ✅ 删除时半透明
            }

            // ✅ 正在删除时显示 loading 指示器
            if isDeleting {
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 20, height: 20)
            }
            // 悬停时显示删除按钮（非删除状态）
            else if isHovering {
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.system(size: 14))
                }
                .pointerStyle(.link)
                .buttonStyle(.plain)
                .help("Delete snippet")
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 44)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .disabled(isDeleting)  // ✅ 删除时禁用交互
        .confirmationDialog(
            "Confirm deletion",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Delete snippet “\(snippet.title)”? \(snippet.shortcutKey != nil ? "\nThis will also remove its hotkey setting." : "")")
        }
    }
}
