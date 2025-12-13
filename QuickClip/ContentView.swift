//
//  主界面
//  快速剪贴
//
//  创建者：Brian He（2025/12/9）
//

import SwiftUI
import SwiftData
import AppKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var allSnippets: [Snippet]

    @State private var selectedSnippet: Snippet?
    @State private var isShowingSettings: Bool = false
    @State private var hasPerformedStartupSync = false

    var body: some View {
        NavigationSplitView {
            SnippetListView(
                selectedSnippet: $selectedSnippet,
                isShowingSettings: $isShowingSettings
            )
                .navigationSplitViewColumnWidth(min: 250, ideal: 300)
        } detail: {
            if let snippet = selectedSnippet {
                SnippetDetailView(snippet: snippet)
            } else {
                VStack(spacing: 20) {
                    Image(systemName: "doc.text")
                        .font(.system(size: 60))
                        .foregroundColor(.secondary)
                    Text("Select or create a snippet")
                        .font(.title2)
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $isShowingSettings) {
            SettingsView {
                selectedSnippet = nil
            }
        }
        .task {
            // App 启动时执行一次 iCloud 同步（如果已开启）
            guard !hasPerformedStartupSync else { return }
            hasPerformedStartupSync = true

            // 创建临时 ViewModel 来执行启动同步
            let viewModel = SettingsViewModel(
                modelContext: modelContext,
                allSnippets: allSnippets,
                onDidClearAll: {}
            )

            await viewModel.performStartupSyncIfEnabled()
        }
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Snippet.self, inMemory: true)
}
