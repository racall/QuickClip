//
//  数据导出模型
//  快速剪贴
//
//  创建者：Brian He（2025/12/13）
//

import Foundation

/// 导出文件结构
struct SnippetExportFile: Codable {
    let version: Int
    let exportedAt: Date
    let snippets: [SnippetExportItem]
}

/// 导出项结构
struct SnippetExportItem: Codable {
    let title: String
    let content: String
    let shortcutKey: String?
    let showInMenuBar: Bool
    let createdAt: Date
    let updatedAt: Date
}
