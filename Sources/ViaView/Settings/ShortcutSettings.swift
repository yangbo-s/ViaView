import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ShortcutSettings: View {
    @State private var search = ""
    private var entries: [(group: String, title: String, key: String)] {
        (NSApp.mainMenu?.items ?? []).flatMap { section in
            (section.submenu?.items ?? []).compactMap { item in
                guard !item.keyEquivalent.isEmpty else { return nil }
                var key = ""
                if item.keyEquivalentModifierMask.contains(.control) { key += "⌃" }
                if item.keyEquivalentModifierMask.contains(.option) { key += "⌥" }
                if item.keyEquivalentModifierMask.contains(.shift) { key += "⇧" }
                if item.keyEquivalentModifierMask.contains(.command) { key += "⌘" }
                let symbols = [String(UnicodeScalar(NSLeftArrowFunctionKey)!): "←", String(UnicodeScalar(NSRightArrowFunctionKey)!): "→", String(UnicodeScalar(NSBackspaceCharacter)!): "⌫", " ": "空格"]
                key += symbols[item.keyEquivalent] ?? item.keyEquivalent.uppercased()
                return (section.title, item.title, key)
            }
        }
    }
    var body: some View {
        VStack(spacing: 0) {
            TextField("搜索操作或快捷键", text: $search).textFieldStyle(.roundedBorder).padding(20)
            Form {
                ForEach(["ViaView", "文件", "编辑", "显示", "窗口"], id: \.self) { group in
                    let matches = entries.filter { $0.group == group && (search.isEmpty || ($0.title + $0.key).localizedCaseInsensitiveContains(search)) }
                    if !matches.isEmpty {
                        Section(group) {
                            ForEach(matches, id: \.title) { entry in
                                HStack { Text(entry.title); Spacer(); Text(entry.key).font(.system(.body, design: .monospaced)).foregroundStyle(.secondary) }
                            }
                        }
                    }
                }
                if search.isEmpty {
                    Section("鼠标与触控板") {
                        LabeledContent("缩放", value: "滚轮 / 双指捏合")
                        LabeledContent("平移", value: "拖动 / Shift + 滚轮")
                        LabeledContent("框选", value: "⌘ 拖动（可在通用中互换）")
                        LabeledContent("快捷菜单", value: "右键 / Control + 点击")
                    }
                } else if !entries.contains(where: { ($0.title + $0.key).localizedCaseInsensitiveContains(search) }) {
                    Text("没有匹配的快捷键").foregroundStyle(.secondary)
                }
            }.formStyle(.grouped)
        }
    }
}
