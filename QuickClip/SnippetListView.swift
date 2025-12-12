//
//  SnippetListView.swift
//  QuickClip
//
//  Created by Brian He on 2025/12/9.
//

import SwiftUI
import SwiftData

struct SnippetListView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Snippet.createdAt, order: .reverse) private var allSnippets: [Snippet]

    @State private var searchText: String = ""
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
        VStack(spacing: 0) {
            // 搜索框
            HStack {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                TextField("搜索片段", text: $searchText)
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
                    .tag(snippet)
                }
            }
            .listStyle(.sidebar)

            // 底部工具栏
            Divider()
            HStack {
                Button {
                    addNewSnippet()
                } label: {
                    Label("新建片段", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)

                Spacer()

                Text("\(filteredSnippets.count) 个片段")
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .padding(.trailing, 12)
            }
            .background(Color.gray.opacity(0.05))
        }
    }

    private func addNewSnippet() {
        let newSnippet = Snippet()
        modelContext.insert(newSnippet)
        selectedSnippet = newSnippet
        // 数据已保存，菜单会在打开时自动刷新
    }

    private func deleteSnippet(_ snippet: Snippet) {
        print("🗑️ 删除片段: \(snippet.title)")

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
            print("📣 片段有快捷键，发送快捷键更新通知")
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
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(snippet.title.isEmpty ? "未命名片段" : snippet.title)
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
                }

                Text(snippet.content.isEmpty ? "暂无内容" : snippet.content)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                    .frame(minHeight: 28, alignment: .topLeading)
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
                .help("删除片段")
            }
        }
        .padding(.vertical, 6)
        .frame(minHeight: 60)
        .contentShape(Rectangle())
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .confirmationDialog(
            "确认删除",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                onDelete()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("确定要删除片段「\(snippet.title)」吗？\(snippet.shortcutKey != nil ? "\n此操作将同时移除快捷键设置。" : "")")
        }
    }
}
