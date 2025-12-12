# QuickClip

[English](./README.md)

QuickClip 是一个基于 SwiftUI + SwiftData 的 macOS 文本/代码片段管理工具。

## 功能

- 新建、搜索、编辑文本片段（snippets）。
- 可选：为片段设置全局快捷键，一键把内容复制到剪贴板。
- 菜单栏只展示你显式开启“在菜单栏中显示”的片段（默认全部不显示），最多显示 10 条，并按最近更新时间排序。
- 菜单栏支持根据主窗口状态动态显示：`Open QuickClip` / `Hide QuickClip`（显示/隐藏主界面）。

## 代码结构（以实际代码为准）

- 应用入口 + SwiftData 容器：`QuickClip/QuickClipApp.swift`
- 数据模型（SwiftData `@Model`）：`QuickClip/Snippet.swift`
- 主界面：`QuickClip/ContentView.swift`
  - 左侧列表：`QuickClip/SnippetListView.swift`
  - 右侧详情/编辑：`QuickClip/SnippetDetailView.swift`
- 菜单栏：`QuickClip/MenuBarManager.swift`
- 全局快捷键（Carbon）：`QuickClip/HotKeyManager.swift`

## 使用方式

1. 点击 `New Snippet` 新建片段。
2. 在详情页编辑标题和内容。
3. 需要在菜单栏中展示时，在详情页勾选 `Show in menu bar`。
4. 如需全局快捷键，按提示授予辅助功能权限。

## 权限说明

全局快捷键需要 **辅助功能（Accessibility）** 权限：

- 系统设置 → 隐私与安全性 → 辅助功能 → 添加/启用 QuickClip

## 构建与运行

- 依赖：Xcode（Swift 5），项目中 macOS 部署目标配置为 `26.0`。
- 构建方式：
  - 打开 `QuickClip.xcodeproj`，运行 `QuickClip` scheme
  - 或命令行：
    - `xcodebuild -project QuickClip.xcodeproj -scheme QuickClip -configuration Debug -destination 'platform=macOS' build`

## 备注

- SwiftData 模型变更可能涉及迁移。本项目把 `showInMenuBar` 设计为可选字段，以尽量兼容已有的本地数据存储。
