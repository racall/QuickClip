//
//  SnippetDetailView.swift
//  QuickClip
//
//  Created by Brian He on 2025/12/9.
//

import SwiftUI
import SwiftData

struct SnippetDetailView: View {
    @Bindable var snippet: Snippet
    @State private var isRecordingHotkey: Bool = false
    @Environment(\.modelContext) private var modelContext
    @State private var updateTask: Task<Void, Never>?
    @State private var isCopied: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // 标题输入
                VStack(alignment: .leading, spacing: 8) {
                    Text("标题")
                        .font(.headline)
                    TextField("输入片段标题", text: $snippet.title)
                        .textFieldStyle(.roundedBorder)
                }

                // 内容输入
                VStack(alignment: .leading, spacing: 8) {
                    // 操作按钮
                    HStack {
                        Text("内容")
                            .font(.headline)
                        Spacer()
                        Button {
                            ClipboardHelper.copyToClipboard(snippet.content)

                            // 显示复制成功状态
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isCopied = true
                            }

                            // 1.5秒后恢复
                            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    isCopied = false
                                }
                            }
                        } label: {
                            Image(systemName: isCopied ? "checkmark" : "doc.on.clipboard")
                                .font(.headline)
                                .foregroundColor(isCopied ? .green : .primary)
                        }
                        .buttonStyle(.plain)
                        .help(isCopied ? "已复制到剪贴板" : "复制内容到剪贴板")
                    }
                    .frame(height: 24)
                    
                    TextEditor(text: $snippet.content)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 300)
                        .border(Color.gray.opacity(0.3), width: 1)
                }

                // 快捷键设置
                VStack(alignment: .leading, spacing: 8) {
                    Text("快捷键")
                        .font(.headline)

                    HStack {
                        if let shortcut = snippet.shortcutKey, !shortcut.isEmpty {
                            Text(shortcut)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(Color.accentColor.opacity(0.2))
                                .cornerRadius(6)
                        } else {
                            Text("未设置")
                                .foregroundColor(.secondary)
                        }

                        Button(isRecordingHotkey ? "按下快捷键..." : "录制快捷键") {
                            isRecordingHotkey.toggle()
                        }
                        .buttonStyle(.bordered)

                        if snippet.shortcutKey != nil {
                            Button("清除") {
                                print("🗑️ 清除快捷键")

                                // 取消之前的任务
                                updateTask?.cancel()

                                snippet.shortcutKey = nil
                                snippet.updatedAt = Date()

                                // 保存数据
                                do {
                                    try modelContext.save()
                                    print("💾 数据已保存")
                                } catch {
                                    print("❌ 保存失败: \(error)")
                                }

                                // 只需要重新注册快捷键，菜单会自动刷新
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    NotificationCenter.default.post(name: NSNotification.Name("HotKeysNeedUpdate"), object: nil)
                                }
                            }
                            .buttonStyle(.borderless)
                            .foregroundColor(.red)
                        }
                    }

                    if isRecordingHotkey {
                        Text("请按下快捷键组合（如 ⌘⇧C）")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                Divider()

                // 时间信息
                HStack(alignment: .bottom, spacing: 10) {
                    Spacer()
                    Text("创建时间: \(snippet.createdAt, format: .dateTime)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("更新时间: \(snippet.updatedAt, format: .dateTime)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
            }
            .padding()
        }
        .background(
            HotkeyRecorderView(isRecording: $isRecordingHotkey) { keyCombo in
                print("🎯 录制到快捷键: \(keyCombo)")

                // 取消之前的任务
                updateTask?.cancel()

                snippet.shortcutKey = keyCombo
                snippet.updatedAt = Date()
                isRecordingHotkey = false

                // 保存数据
                do {
                    try modelContext.save()
                    print("💾 数据已保存")
                } catch {
                    print("❌ 保存失败: \(error)")
                }

                // 只需要重新注册快捷键，菜单会自动刷新
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    print("📣 发送快捷键更新通知")
                    NotificationCenter.default.post(name: NSNotification.Name("HotKeysNeedUpdate"), object: nil)
                }
            }
        )
        .onDisappear {
            // 视图消失时保存数据
            snippet.updatedAt = Date()
            try? modelContext.save()

            // 取消未完成的任务
            updateTask?.cancel()
        }
    }
}

// 快捷键录制视图
struct HotkeyRecorderView: NSViewRepresentable {
    @Binding var isRecording: Bool
    var onRecorded: (String) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = HotkeyRecorderNSView()
        view.onRecorded = onRecorded
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let recorderView = nsView as? HotkeyRecorderNSView {
            recorderView.isRecording = isRecording
        }
    }
}

class HotkeyRecorderNSView: NSView {
    var isRecording: Bool = false {
        didSet {
            if isRecording {
                window?.makeFirstResponder(self)
            }
        }
    }
    var onRecorded: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        guard isRecording else {
            super.keyDown(with: event)
            return
        }

        var modifiers: [String] = []
        if event.modifierFlags.contains(.command) { modifiers.append("⌘") }
        if event.modifierFlags.contains(.shift) { modifiers.append("⇧") }
        if event.modifierFlags.contains(.option) { modifiers.append("⌥") }
        if event.modifierFlags.contains(.control) { modifiers.append("⌃") }

        if let characters = event.charactersIgnoringModifiers?.uppercased(), !characters.isEmpty {
            let keyCombo = modifiers.joined() + characters
            if modifiers.count > 0 {
                onRecorded?(keyCombo)
            }
        }
    }
}
