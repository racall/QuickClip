//
//  ClipboardHelper.swift
//  QuickClip
//
//  Created by Brian He on 2025/12/9.
//

import AppKit

class ClipboardHelper {
    static func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }

    static func getClipboardContent() -> String? {
        let pasteboard = NSPasteboard.general
        return pasteboard.string(forType: .string)
    }
}
