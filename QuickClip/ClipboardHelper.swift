//
//  剪贴板工具
//  快速剪贴
//
//  创建者：Brian He（2025/12/9）
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
