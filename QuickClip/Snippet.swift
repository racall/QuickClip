//
//  片段模型
//  快速剪贴
//
//  创建者：Brian He（2025/12/9）
//

import Foundation
import SwiftData

@Model
final class Snippet {
    var id: UUID
    var title: String
    var content: String
    var shortcutKey: String?
    var showInMenuBar: Bool?
    var createdAt: Date
    var updatedAt: Date

    // iCloud 同步相关
    var cloudRecordID: String?        // CloudKit 记录 ID
    var lastSyncedAt: Date?           // 最后同步时间
    var needsSync: Bool = false       // 是否需要同步到 iCloud

    init(title: String = "New Snippet", content: String = "", shortcutKey: String? = nil, showInMenuBar: Bool = false) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.shortcutKey = shortcutKey
        self.showInMenuBar = showInMenuBar
        self.createdAt = Date()
        self.updatedAt = Date()
        self.needsSync = false
    }

    func updateContent(title: String? = nil, content: String? = nil, shortcutKey: String? = nil, showInMenuBar: Bool? = nil) {
        if let title = title {
            self.title = title
        }
        if let content = content {
            self.content = content
        }
        if shortcutKey != nil {
            self.shortcutKey = shortcutKey
        }
        if let showInMenuBar = showInMenuBar {
            self.showInMenuBar = showInMenuBar
        }
        self.updatedAt = Date()
    }
}
