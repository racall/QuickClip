//
//  Snippet.swift
//  QuickClip
//
//  Created by Brian He on 2025/12/9.
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

    init(title: String = "新片段", content: String = "", shortcutKey: String? = nil, showInMenuBar: Bool = false) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.shortcutKey = shortcutKey
        self.showInMenuBar = showInMenuBar
        self.createdAt = Date()
        self.updatedAt = Date()
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
