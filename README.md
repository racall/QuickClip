# QuickClip - macOS 代码片段管理工具

## 功能特性

### ✅ 已实现功能

1. **主界面**
   - 左右分栏布局
   - 左侧：片段列表 + 搜索框 + 新建按钮
   - 右侧：片段详情编辑（标题、内容、快捷键设置）

2. **状态栏菜单**
   - 显示剪贴板图标
   - 点击展示前10个片段
   - 快速复制功能
   - "打开 QuickClip" 菜单项
   - "退出" 菜单项（完全退出应用）

3. **全局快捷键**
   - 支持快捷键录制（如 ⌘⇧C、⌃⌥V 等）
   - 按下快捷键后自动复制到剪贴板
   - 状态栏图标变化提示（显示对勾图标1.5秒）

4. **搜索功能**
   - 实时搜索片段标题和内容
   - 显示匹配片段数量

5. **窗口管理**
   - 点击关闭按钮隐藏窗口（不退出应用）
   - 只有在状态栏点击"退出"才完全退出

## 使用说明

### 创建新片段
1. 点击左下角"新建片段"按钮
2. 输入标题和内容
3. （可选）设置快捷键：点击"录制快捷键"，按下想要的组合键

### 使用快捷键
1. 设置快捷键后，无论应用是否在前台
2. 按下快捷键即可复制片段到剪贴板
3. 状态栏图标会变成对勾图标1.5秒作为反馈

### 从状态栏复制
1. 点击状态栏的剪贴板图标
2. 选择要复制的片段
3. 片段自动复制到剪贴板

### 快捷键格式
支持的修饰键组合：
- ⌘ Command
- ⇧ Shift
- ⌥ Option
- ⌃ Control

示例：⌘⇧C、⌃⌥1、⌘⇧⌥K 等

## 技术栈

- SwiftUI - 界面构建
- SwiftData - 数据持久化
- AppKit - 状态栏和窗口管理
- Carbon - 全局快捷键监听

## 项目结构

```
QuickClip/
├── QuickClipApp.swift          # 应用入口、AppDelegate
├── Snippet.swift               # 数据模型
├── ContentView.swift           # 主界面
├── SnippetListView.swift       # 片段列表视图
├── SnippetDetailView.swift     # 片段详情编辑
├── MenuBarManager.swift        # 状态栏管理
├── HotKeyManager.swift         # 全局快捷键管理
├── ClipboardHelper.swift       # 剪贴板工具
└── QuickClip.entitlements     # 权限配置
```

## 注意事项

1. **首次运行**：如果全局快捷键不生效，需要在"系统偏好设置 > 隐私与安全性 > 辅助功能"中授予 QuickClip 权限

2. **Entitlements 配置**：
   - 需要在 Xcode 项目设置中关联 `QuickClip.entitlements` 文件
   - 路径：Target > Signing & Capabilities > Code Signing Entitlements

3. **快捷键冲突**：如果设置的快捷键与系统或其他应用冲突，可能无法注册成功

## 下一步优化建议

- [ ] 添加片段分类/标签功能
- [ ] 支持代码高亮显示
- [ ] 导入/导出片段功能
- [ ] iCloud 同步
- [ ] 快捷键冲突检测和提示
