//
//  主界面
//  快速剪贴
//
//  创建者：Brian He（2025/12/9）
//

import SwiftUI
import SwiftData

struct ContentView: View {
    @State private var selectedSnippet: Snippet?

    var body: some View {
        NavigationSplitView {
            SnippetListView(selectedSnippet: $selectedSnippet)
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
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Snippet.self, inMemory: true)
}
