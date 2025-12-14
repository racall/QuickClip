# QuickClip 上线前检查清单

## 📋 总览

- [ ] 1. 代码质量检查
- [ ] 2. 版本号和构建号
- [ ] 3. 移除调试代码
- [ ] 4. CloudKit 配置
- [ ] 5. 签名和证书
- [ ] 6. 权限和 Entitlements
- [ ] 7. 编译和打包
- [ ] 8. 功能测试
- [ ] 9. App Store 元数据
- [ ] 10. 隐私政策和文档
- [ ] 11. 最终验证

---

## 1. 代码质量检查

### 1.1 清理调试代码
- [ ] 搜索并移除或注释掉所有 `print()` 语句（或保留关键错误日志）
  ```bash
  # 搜索所有 print 语句
  grep -r "print(" QuickClip/ --include="*.swift" | grep -v "//"
  ```

- [ ] 检查是否有 `TODO`、`FIXME`、`HACK` 注释
  ```bash
  grep -r "TODO\|FIXME\|HACK" QuickClip/ --include="*.swift"
  ```

- [ ] 移除测试代码和临时代码

### 1.2 代码质量
- [ ] 运行 SwiftLint（如果使用）
- [ ] 检查编译警告，确保无警告
  ```bash
  xcodebuild -scheme QuickClip -configuration Release clean build | grep "warning:"
  ```

### 1.3 文件整理
- [ ] 删除未使用的文件
- [ ] 确保 `.gitignore` 正确配置
- [ ] 移除开发文档中的敏感信息

---

## 2. 版本号和构建号

### 2.1 设置版本号
**文件**: `Info.plist` 或 Xcode 项目设置

- [ ] 设置 `CFBundleShortVersionString` (版本号)
  - 示例: `1.0.0`
  - 格式: `主版本.次版本.修订版本`

- [ ] 设置 `CFBundleVersion` (构建号)
  - 示例: `1` 或 `100`
  - 规则: 每次提交到 App Store 必须递增

### 2.2 检查版本号
```bash
# 查看当前版本号
/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" QuickClip/Info.plist
/usr/libexec/PlistBuddy -c "Print CFBundleVersion" QuickClip/Info.plist
```

**位置**: Xcode → 项目设置 → General → Identity
- Version: `1.0.0`
- Build: `1`

---

## 3. 移除调试代码

### 3.1 日志输出
建议保留方式：
```swift
#if DEBUG
    print("🔍 Debug info: \(info)")
#endif
```

或者使用统一的日志系统：
```swift
// 只在 Debug 模式输出
func debugLog(_ message: String) {
    #if DEBUG
    print(message)
    #endif
}
```

### 3.2 需要移除的内容
- [ ] 测试用的假数据
- [ ] 开发环境的特殊配置
- [ ] 调试用的弹窗和提示
- [ ] 未使用的导入语句

---

## 4. CloudKit 配置

### 4.1 Production Environment
**重要**: CloudKit 有两个环境：Development 和 Production

- [ ] 登录 [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard/)
- [ ] 选择 `iCloud.io.0os.QuickClip` 容器
- [ ] 确认 Production Environment 中的 Schema 已部署

#### 4.1.1 部署 Schema 到 Production
1. 进入 Development Environment
2. 点击 "Schema" → "Deploy to Production"
3. 确认以下 Record Types 已部署：
   - ✅ `Snippet` (Private Database)
   - ✅ `UsingUsers` (Public Database)

#### 4.1.2 验证 Schema
**Private Database - Snippet**:
- [ ] `snippetID` (String)
- [ ] `title` (String)
- [ ] `content` (String)
- [ ] `shortcutKey` (String, Optional)
- [ ] `showInMenuBar` (Int64)
- [ ] `createdAt` (Date)
- [ ] `updatedAt` (Date)

**Public Database - UsingUsers**:
- [ ] `uid` (String, Indexed)
- [ ] `os` (String)
- [ ] `sv` (String)
- [ ] `firstSendDate` (Date)
- [ ] `sendDate` (Date, Indexed)

### 4.2 测试 Production Environment

**新版 Xcode (16.0+)**: CloudKit 环境根据构建配置自动选择
- Debug 构建 → Development 环境
- Release 构建 → Production 环境

**测试 Production 环境的方法**:

#### 方法1: 使用 Release 配置运行（推荐）
```bash
# 1. 编辑 Scheme
Xcode → Product → Scheme → Edit Scheme

# 2. 切换到 Release 配置
Run → Build Configuration → Release

# 3. 运行 App
Product → Run (Cmd + R)
```

#### 方法2: 测试 Archive 构建
```bash
# 1. Archive
Product → Archive

# 2. 导出 App
Organizer → Distribute App → Development
选择导出位置

# 3. 直接运行导出的 .app
打开导出的 .app 文件测试
```

**验证当前环境**:
- [ ] 在代码中添加日志输出当前 CloudKit 环境
  ```swift
  #if DEBUG
  print("🔧 Using CloudKit Development Environment")
  #else
  print("🚀 Using CloudKit Production Environment")
  #endif
  ```
- [ ] 在 CloudKit Dashboard 中查看数据写入到哪个环境

---

## 5. 签名和证书

### 5.1 开发者账号
- [ ] 确认已加入 Apple Developer Program
- [ ] 确认账号状态正常（未过期）

### 5.2 证书和 Provisioning Profile
**位置**: Xcode → 项目设置 → Signing & Capabilities

- [ ] Signing Certificate: "Developer ID Application: Your Name (Team ID)" 或 "Apple Distribution"
- [ ] Provisioning Profile: 自动管理或手动选择
- [ ] Team: 选择正确的开发团队

### 5.3 Bundle Identifier
- [ ] 确认 Bundle Identifier: `io.0os.QuickClip`
- [ ] 确认与 App Store Connect 中的一致

### 5.4 Capabilities
- [ ] iCloud
  - ✅ CloudKit
  - ✅ Key-value storage
- [ ] App Sandbox
  - ✅ Network: Outgoing Connections (Client)
- [ ] Hardened Runtime（如果是 Mac App Store）

---

## 6. 权限和 Entitlements

### 6.1 检查 Entitlements 文件
**文件**: `QuickClip.entitlements`

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <!-- iCloud -->
    <key>com.apple.developer.icloud-container-identifiers</key>
    <array>
        <string>iCloud.io.0os.QuickClip</string>
    </array>
    <key>com.apple.developer.icloud-services</key>
    <array>
        <string>CloudKit</string>
    </array>
    <key>com.apple.developer.ubiquity-kvstore-identifier</key>
    <string>$(TeamIdentifierPrefix)$(CFBundleIdentifier)</string>

    <!-- App Sandbox -->
    <key>com.apple.security.app-sandbox</key>
    <true/>
    <key>com.apple.security.network.client</key>
    <true/>
</dict>
</plist>
```

### 6.2 Info.plist 检查
- [ ] `CFBundleDisplayName` (App 显示名称)
- [ ] `CFBundleName` (Bundle 名称)
- [ ] `CFBundleIdentifier` (Bundle ID)
- [ ] `LSMinimumSystemVersion` (最低系统版本，如 "13.0")
- [ ] `LSUIElement` (如果是纯菜单栏应用，设为 true)
- [ ] `NSHumanReadableCopyright` (版权信息)

---

## 7. 编译和打包

### 7.1 清理项目
```bash
# 清理构建缓存
rm -rf ~/Library/Developer/Xcode/DerivedData/QuickClip-*

# 在 Xcode 中
# Product → Clean Build Folder (Shift + Cmd + K)
```

### 7.2 Release 构建
- [ ] 切换到 Release 配置
  - Xcode → Product → Scheme → Edit Scheme
  - Run → Build Configuration: Release

- [ ] 禁用调试选项
  - Debug executable: 取消勾选
  - GPU Frame Capture: 禁用

### 7.3 Archive
```bash
# 命令行方式
xcodebuild -scheme QuickClip -configuration Release clean archive \
    -archivePath ~/Desktop/QuickClip.xcarchive

# 或者在 Xcode 中
# Product → Archive
```

### 7.4 导出 .app
- [ ] 打开 Organizer (Window → Organizer)
- [ ] 选择最新的 Archive
- [ ] 点击 "Distribute App"
- [ ] 选择分发方式：
  - **App Store Connect**: 上传到 App Store
  - **Developer ID**: 在 Mac App Store 外分发
  - **Export**: 导出未签名或 Ad Hoc 版本

### 7.5 公证（Notarization）
**如果是 Developer ID 分发（Mac App Store 外）**:
```bash
# 1. 打包为 DMG 或 ZIP
# 2. 提交公证
xcrun notarytool submit QuickClip.dmg --keychain-profile "AC_PASSWORD" --wait

# 3. 装订公证票据
xcrun stapler staple QuickClip.dmg
```

---

## 8. 功能测试

### 8.1 基本功能
- [ ] 创建新片段
- [ ] 编辑片段（title, content, shortcutKey, showInMenuBar）
- [ ] 删除片段
- [ ] 搜索片段
- [ ] 复制片段到剪贴板
- [ ] 菜单栏显示和操作

### 8.2 快捷键功能
- [ ] 录制快捷键
- [ ] 触发快捷键复制片段
- [ ] 清除快捷键
- [ ] 快捷键冲突处理
- [ ] 重启 App 后快捷键仍然有效

### 8.3 iCloud 同步
- [ ] 开启 iCloud 同步，检查完整同步
- [ ] 关闭 iCloud 同步
- [ ] 新增片段，检查是否上传到 iCloud
- [ ] 修改片段，等待 3 秒，检查是否上传
- [ ] 删除片段，检查云端是否删除
- [ ] 手动同步功能
- [ ] 两台设备同步测试（如果可以）
- [ ] 同步进度显示
- [ ] 冲突处理（内容重复、快捷键冲突）

### 8.4 设置功能
- [ ] 导出 JSON
- [ ] 导入 JSON
- [ ] 清空所有数据（确认对话框）
- [ ] iCloud 同步开关
- [ ] 同步状态显示

### 8.5 用户统计
- [ ] 首次启动，检查是否创建统计记录
- [ ] 重启 App，检查是否更新 sendDate
- [ ] 未登录 iCloud 时 App 正常运行
- [ ] 网络断开时 App 正常运行
- [ ] CloudKit Dashboard 中查看统计数据

### 8.6 边界测试
- [ ] 空标题片段
- [ ] 超长内容片段（10000+ 字符）
- [ ] 特殊字符（emoji、中文、符号）
- [ ] 快速连续操作（防止崩溃）
- [ ] 内存泄漏检查（Instruments）

### 8.7 系统兼容性
- [ ] 最低支持的 macOS 版本测试（如 macOS 13）
- [ ] 最新 macOS 版本测试（如 macOS 15）
- [ ] 深色模式 / 浅色模式
- [ ] 不同屏幕分辨率

---

## 9. App Store 元数据

### 9.1 App Store Connect 设置
登录 [App Store Connect](https://appstoreconnect.apple.com/)

#### 9.1.1 App 信息
- [ ] App 名称（最多 30 字符）
- [ ] 副标题（最多 30 字符）
- [ ] 类别
  - 主要类别: Utilities
  - 次要类别: Productivity
- [ ] Bundle ID: `io.0os.QuickClip`

#### 9.1.2 定价和供应情况
- [ ] 价格（免费或付费）
- [ ] 供应国家/地区

#### 9.1.3 App 隐私
- [ ] 隐私政策 URL: `https://your-website.com/privacy`
- [ ] 数据收集说明：
  ```
  我们收集以下匿名数据用于改进产品：
  - 匿名用户标识（userRecordID 的 MD5 哈希）
  - 操作系统版本
  - App 版本号
  - App 使用时间

  我们不收集任何个人身份信息或用户内容。
  ```

#### 9.1.4 版本信息
- [ ] 版本号: `1.0.0`
- [ ] 版本说明（What's New）:
  ```
  QuickClip 1.0.0 首次发布！

  主要功能：
  • 快速保存和管理代码片段、文本片段
  • 全局快捷键快速复制
  • 菜单栏快速访问
  • iCloud 同步，多设备同步数据
  • JSON 导入导出

  让您的工作更高效！
  ```

#### 9.1.5 描述
- [ ] App 描述（最多 4000 字符）
  ```
  QuickClip 是一款简洁高效的 macOS 代码片段和文本片段管理工具。

  ✨ 主要功能
  • 📝 片段管理：快速保存和编辑代码片段、文本模板
  • ⌨️ 全局快捷键：自定义快捷键，一键复制常用片段
  • 📋 菜单栏访问：快速从菜单栏访问所有片段
  • ☁️ iCloud 同步：多设备无缝同步您的片段
  • 📤 导入导出：支持 JSON 格式导入导出，方便备份和迁移

  🎯 适用场景
  • 开发者：保存常用代码片段、命令行命令
  • 写作者：保存文本模板、常用短语
  • 客服：快速回复常用话术
  • 任何需要快速输入重复内容的工作

  🔒 隐私保护
  • 数据存储在您的 iCloud 账户中，我们无法访问
  • 只收集匿名使用统计，不收集个人信息

  立即下载，让工作更高效！
  ```

- [ ] 关键词（最多 100 字符，逗号分隔）
  ```
  snippet,clipboard,code,text,productivity,shortcut,menubar,icloud,sync
  ```

- [ ] 支持 URL（可选）: `https://your-website.com/support`
- [ ] 营销 URL（可选）: `https://your-website.com`

#### 9.1.6 截图
**要求**:
- 分辨率: 至少 1280x800
- 格式: PNG 或 JPEG
- 数量: 1-10 张

**建议截图**:
1. 主界面（片段列表 + 详情）
2. 快捷键设置界面
3. iCloud 同步设置
4. 菜单栏展示
5. 导入导出功能

**提示**:
- 使用干净的示例数据
- 截图前清理 macOS 菜单栏图标
- 使用 macOS 截图工具: `Cmd + Shift + 4`

#### 9.1.7 App 预览视频（可选）
- 时长: 15-30 秒
- 格式: .mov, .mp4, .m4v
- 分辨率: 1920x1080 或更高

---

## 10. 隐私政策和文档

### 10.1 隐私政策
**必须项**: 在网站上发布隐私政策

**最低要求内容**:
```markdown
# QuickClip 隐私政策

最后更新：2025-12-13

## 数据收集

QuickClip 收集以下匿名数据用于改进产品：

### 自动收集的数据
- **匿名用户标识**: 您的 iCloud userRecordID 的 MD5 哈希值
- **系统信息**: macOS 版本号
- **应用信息**: QuickClip 版本号
- **使用时间**: 应用打开时间

### 我们不收集的数据
- 个人身份信息
- 片段内容
- 快捷键设置
- 任何其他个人数据

## 数据存储

### iCloud 同步
- 您的片段数据存储在您的 iCloud 账户中
- 我们无法访问您的片段内容
- 数据在您的设备和 iCloud 之间传输时已加密

### 匿名统计
- 存储在 Apple CloudKit Public Database
- 数据已匿名化，无法关联到具体用户
- 仅用于统计分析，不与第三方共享

## 数据使用

我们使用收集的匿名数据用于：
- 统计活跃用户数量
- 了解系统版本分布，优化兼容性
- 了解应用版本使用情况

## 用户权利

- 如果您未登录 iCloud，统计功能会自动跳过
- 您可以随时删除 iCloud 中的片段数据
- 您的片段内容完全私密，我们无法访问

## 联系我们

如有任何隐私相关问题，请联系：
- 邮箱: privacy@your-domain.com
- 网站: https://your-website.com
```

### 10.2 README 文档
- [ ] 更新 `README.md`
- [ ] 添加使用说明
- [ ] 添加截图
- [ ] 添加下载链接（上线后）

### 10.3 网站（推荐）
- [ ] 产品介绍页面
- [ ] 下载链接
- [ ] 使用教程
- [ ] FAQ
- [ ] 隐私政策页面
- [ ] 联系方式

---

## 11. 最终验证

### 11.1 上传前最后检查
- [ ] 所有功能正常运行
- [ ] 无崩溃、无严重 bug
- [ ] Release 构建成功
- [ ] 版本号正确
- [ ] CloudKit Production Schema 已部署
- [ ] 隐私政策已发布
- [ ] App Store 元数据已准备

### 11.2 上传到 App Store Connect
```bash
# 使用 Xcode 上传
# 1. Organizer → 选择 Archive
# 2. Distribute App → App Store Connect
# 3. 选择 Team 和 Provisioning Profile
# 4. Upload

# 或使用命令行（需要先配置 API Key）
xcrun altool --upload-app --type macos --file QuickClip.pkg \
    --apiKey YOUR_API_KEY --apiIssuer YOUR_ISSUER_ID
```

### 11.3 TestFlight（可选）
- [ ] 上传成功后，在 App Store Connect 中选择构建版本
- [ ] 添加 TestFlight Beta 测试人员
- [ ] 发送测试邀请
- [ ] 收集测试反馈

### 11.4 提交审核
**App Store Connect 中**:
1. 选择 App 版本
2. 填写版本信息
3. 选择构建版本
4. 点击 "提交审核"

**审核注意事项**:
- [ ] 确保 App 符合 [App Store 审核指南](https://developer.apple.com/app-store/review/guidelines/)
- [ ] 提供测试账号（如果需要）
- [ ] 准备审核说明（如特殊功能说明）
- [ ] 确保联系方式可用

### 11.5 审核后
**如果被拒绝**:
1. 查看拒绝原因
2. 修复问题
3. 回复审核团队或重新提交

**如果通过**:
1. 选择发布方式：
   - 自动发布
   - 手动发布
   - 定时发布
2. 准备发布公告
3. 更新网站和社交媒体

---

## 12. 上线后

### 12.1 监控
- [ ] 监控崩溃报告（Xcode Organizer → Crashes）
- [ ] 检查用户评论和评分
- [ ] 监控 CloudKit 使用情况
- [ ] 检查用户统计数据

### 12.2 推广
- [ ] 社交媒体发布
- [ ] Product Hunt 发布
- [ ] 技术论坛分享
- [ ] 更新 GitHub README

### 12.3 用户反馈
- [ ] 设置反馈渠道（邮箱、GitHub Issues）
- [ ] 收集功能建议
- [ ] 规划下一个版本

---

## 📝 清单完成记录

**检查日期**: _______________
**检查人员**: _______________
**版本号**: _______________
**构建号**: _______________

**提交审核日期**: _______________
**审核通过日期**: _______________
**正式发布日期**: _______________

---

## 🔗 有用的链接

- [App Store Connect](https://appstoreconnect.apple.com/)
- [CloudKit Dashboard](https://icloud.developer.apple.com/dashboard/)
- [Apple Developer](https://developer.apple.com/)
- [App Store 审核指南](https://developer.apple.com/app-store/review/guidelines/)
- [App Store Connect 帮助](https://help.apple.com/app-store-connect/)

---

**祝发布顺利！🚀**
