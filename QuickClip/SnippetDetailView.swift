//
//  片段详情视图
//  快速剪贴
//
//  创建者：Brian He（2025/12/9）
//

import SwiftUI
import SwiftData

struct SnippetDetailView: View {
    @Bindable var snippet: Snippet
    @State private var isRecordingHotkey: Bool = false
    @Environment(\.modelContext) private var modelContext
    @State private var updateTask: Task<Void, Never>?
    @State private var isCopied: Bool = false
    
    private var showInMenuBarBinding: Binding<Bool> {
        Binding(
            get: { snippet.showInMenuBar ?? false },
            set: { newValue in
                snippet.showInMenuBar = newValue
                snippet.updatedAt = Date()
                try? modelContext.save()
                NotificationCenter.default.post(name: NSNotification.Name("MenuBarNeedUpdate"), object: nil)
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 16) {
                DetailSectionCard(title: "Title") {
                    TextField("Enter snippet title", text: $snippet.title)
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor))
                                .shadow(color: Color.black.opacity(0.03), radius: 1, x: 0, y: 1)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                        )
                }

                DetailSectionCard(title: "Content", trailing: {
                    Button {
                        ClipboardHelper.copyToClipboard(snippet.content)

                        withAnimation(.easeInOut(duration: 0.2)) {
                            isCopied = true
                        }

                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                isCopied = false
                            }
                        }
                    } label: {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.clipboard")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(isCopied ? .green : .primary)
                            .frame(width: 28, height: 28)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Color.black.opacity(0.04))
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .stroke(Color.black.opacity(0.06), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .help(isCopied ? "Copied to clipboard" : "Copy to clipboard")
                }) {
                    TextEditor(text: $snippet.content)
                        .font(.system(.body, design: .monospaced))
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(Color(nsColor: .textBackgroundColor))
                                .shadow(color: Color.black.opacity(0.03), radius: 1, x: 0, y: 1)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.black.opacity(0.06), lineWidth: 1)
                        )
                }

                DetailSectionCard(title: "Hotkey") {
                    HStack(spacing: 10) {
                        if let shortcut = snippet.shortcutKey, !shortcut.isEmpty {
                            Text(shortcut)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(
                                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                                        .fill(Color.accentColor.opacity(0.12))
                                )
                        } else {
                            Text("Not set")
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        Button(isRecordingHotkey ? "Press keys..." : "Record hotkey") {
                            isRecordingHotkey.toggle()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)

                        if snippet.shortcutKey != nil {
                            Button("Clear") {
                                print("🗑️ Clear hotkey")

                                updateTask?.cancel()

                                snippet.shortcutKey = nil
                                snippet.updatedAt = Date()

                                do {
                                    try modelContext.save()
                                    print("💾 Saved")
                                } catch {
                                    print("❌ Save failed: \(error)")
                                }

                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                    NotificationCenter.default.post(name: NSNotification.Name("HotKeysNeedUpdate"), object: nil)
                                }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .tint(.red)
                        }
                    }

                    if isRecordingHotkey {
                        Text("Press a key combination (e.g. ⌘⇧C)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.top, 2)
                    }
                }

                DetailSectionCard(title: "Menu Bar") {
                    Toggle("Show in menu bar", isOn: showInMenuBarBinding)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            .padding(20)

            Spacer(minLength: 0)

            Divider()
            HStack(alignment: .bottom, spacing: 10) {
                Spacer()
                Text("Created: \(snippet.createdAt, format: .dateTime)")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Text("Updated: \(snippet.updatedAt, format: .dateTime)")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 20)
            .background(Color.black.opacity(0.02))
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .background(
            HotkeyRecorderView(isRecording: $isRecordingHotkey) { keyCombo in
                print("🎯 Recorded hotkey: \(keyCombo)")

                // 取消之前的任务
                updateTask?.cancel()

                snippet.shortcutKey = keyCombo
                snippet.updatedAt = Date()
                isRecordingHotkey = false

                // 保存数据
                do {
                    try modelContext.save()
                    print("💾 Saved")
                } catch {
                    print("❌ Save failed: \(error)")
                }

                // 只需要重新注册快捷键，菜单会自动刷新
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                    print("📣 Posting hotkey update notification")
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

private struct DetailSectionCard<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing
    @ViewBuilder let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) where Trailing == EmptyView {
        self.title = title
        self.trailing = { EmptyView() }
        self.content = content
    }

    init(title: String, @ViewBuilder trailing: @escaping () -> Trailing, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 10) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.secondary)
                Spacer()
                trailing()
            }
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.02))
                .shadow(color: Color.black.opacity(0.04), radius: 2, x: 0, y: 1)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
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
