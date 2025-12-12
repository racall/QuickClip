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
    @Binding var selectedSnippet: Snippet?

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
                    .padding(.trailing, 12)
            }
            .background(Color.gray.opacity(0.05))
            }
        }
    }

    private func addNewSnippet() {
        let newSnippet = Snippet()
        modelContext.insert(newSnippet)
        pendingScrollToSnippetID = newSnippet.id
        selectedSnippet = newSnippet
        // 数据已保存，菜单会在打开时自动刷新
    }

    private func deleteSnippet(_ snippet: Snippet) {
        print("🗑️ Delete snippet: \(snippet.title)")

        // 检查是否有快捷键
        let hasHotKey = snippet.shortcutKey != nil

        // 如果当前选中的是这个片段，清除选中状态
        if selectedSnippet?.id == snippet.id {
            selectedSnippet = nil
        }

        // 删除片段
        modelContext.delete(snippet)

        // 保存更改
        try? modelContext.save()

        // 如果删除的片段有快捷键，需要重新注册以清除该快捷键
        if hasHotKey {
            print("📣 Snippet has a hotkey. Posting hotkey update notification.")
            NotificationCenter.default.post(name: NSNotification.Name("HotKeysNeedUpdate"), object: nil)
        }
        // 菜单会在打开时自动刷新，无需手动通知
    }
}

struct SnippetRowView: View {
    let snippet: Snippet
    let onDelete: () -> Void

    @State private var isHovering = false
    @State private var showDeleteConfirmation = false

    var body: some View {
        HStack(spacing: 8) {
            Text(snippet.title.isEmpty ? "Untitled" : snippet.title)
                .font(.headline)
                .foregroundColor(snippet.title.isEmpty ? .secondary : .primary)
                .lineLimit(1)

            Spacer()

            if let shortcut = snippet.shortcutKey, !shortcut.isEmpty {
                Text(shortcut)
                    .font(.caption)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.2))
                    .cornerRadius(4)
            }

            // 悬停时显示删除按钮
            if isHovering {
                Button {
                    showDeleteConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundColor(.red)
                        .font(.system(size: 14))
                }
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
