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
    var createdAt: Date
    var updatedAt: Date

    init(title: String = "新片段", content: String = "", shortcutKey: String? = nil) {
        self.id = UUID()
        self.title = title
        self.content = content
        self.shortcutKey = shortcutKey
        self.createdAt = Date()
        self.updatedAt = Date()
    }

    func updateContent(title: String? = nil, content: String? = nil, shortcutKey: String? = nil) {
        if let title = title {
            self.title = title
        }
        if let content = content {
            self.content = content
        }
        if shortcutKey != nil {
            self.shortcutKey = shortcutKey
        }
        self.updatedAt = Date()
    }
}
