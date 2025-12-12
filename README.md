QuickClip

[中文](./README.zh-Hans.md)

QuickClip is a macOS menu bar clipboard/snippet utility built with SwiftUI + SwiftData.


Features
--------
- Create, search, and edit text snippets.
- Global hotkeys (optional) to copy a snippet’s content to the clipboard.
- Menu bar menu shows only snippets you explicitly enable (default: none), up to 10 items sorted by recent update.
- Menu bar action toggles the main window: `Open QuickClip` / `Hide QuickClip`.

How It Works (Code Overview)
----------------------------
- App entry + SwiftData container: `QuickClip/QuickClipApp.swift`
- Data model (SwiftData `@Model`): `QuickClip/Snippet.swift`
- Main UI: `QuickClip/ContentView.swift`
  - Sidebar list: `QuickClip/SnippetListView.swift`
  - Detail editor: `QuickClip/SnippetDetailView.swift`
- Menu bar integration: `QuickClip/MenuBarManager.swift`
- Global hotkeys (Carbon): `QuickClip/HotKeyManager.swift`

Usage
-----
1. Click `New Snippet` to create one.
2. Edit title/content in the detail view.
3. To show a snippet in the menu bar, toggle `Show in menu bar` in the detail view.
4. If you set a global hotkey, grant Accessibility permission when prompted.

Permissions
-----------
Global hotkeys require **Accessibility** permission:
- System Settings → Privacy & Security → Accessibility → add/enable QuickClip

Build & Run
-----------
- Requirements: Xcode (Swift 5), macOS deployment target set to `26.0` in the project.
- Build: open `QuickClip.xcodeproj` and run the `QuickClip` scheme, or:
  - `xcodebuild -project QuickClip.xcodeproj -scheme QuickClip -configuration Debug -destination 'platform=macOS' build`

Notes
-----
- SwiftData model changes can require migration. This project keeps the `showInMenuBar` field optional for backwards compatibility with existing stores.

