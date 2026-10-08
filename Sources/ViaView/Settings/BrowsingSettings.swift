import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct BrowsingSettings: View {
    @AppStorage("wrap") private var wrap = true
    @AppStorage("slideDelay") private var delay = 3
    @State private var folders: [URL] = []
    var body: some View {
        Form {
            Section("浏览行为") {
                Toggle("到达末尾后回到第一张", isOn: $wrap)
                Picker("幻灯片间隔", selection: $delay) {
                    ForEach([2, 3, 5, 10, 15, 30], id: \.self) { Text("\($0) 秒").tag($0) }
                }
            }
            Section {
                if folders.isEmpty {
                    Label("尚未授权文件夹", systemImage: "folder.badge.questionmark")
                        .foregroundStyle(.secondary)
                }
                ForEach(folders, id: \.self) { folder in
                    HStack(spacing: 12) {
                        Image(systemName: "folder.fill").foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(folder.lastPathComponent.isEmpty ? folder.path : folder.lastPathComponent)
                            Text(folder.path).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Button { FileAccessStore.shared.remove(folder); reload() } label: { Image(systemName: "minus.circle") }
                            .buttonStyle(.borderless).help("移除此文件夹的授权")
                            .accessibilityLabel("移除 \(folder.lastPathComponent) 的授权")
                    }
                }
                Button("添加文件夹…", systemImage: "plus") {
                    let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = false
                    panel.allowsMultipleSelection = true; panel.prompt = "允许浏览"
                    panel.message = "选择需要浏览相邻图片的文件夹"
                    guard let window = NSApp.keyWindow else { return }
                    panel.beginSheetModal(for: window) { response in
                        if response == .OK {
                            panel.urls.forEach { FileAccessStore.shared.retain($0) }; reload()
                            (NSApp.delegate as? AppDelegate)?.foldersAuthorized(panel.urls)
                        }
                    }
                }
            } header: { Text("已授权的文件夹") } footer: {
                Text("单独打开文件时，macOS 可能只允许读取这一张。添加所在文件夹后，即可浏览相邻图片。移除授权不会删除文件；已有的单文件授权仍保留。")
            }
        }
        .formStyle(.grouped).onAppear { reload() }
    }
    private func reload() { folders = FileAccessStore.shared.authorizedFolders }
}
