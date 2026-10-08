import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct FileTypeSettings: View {
    private let formats = ["png", "jpg", "gif", "tiff", "bmp", "webp", "heic", "heif", "avif", "ico", "psd", "tga", "svg", "pdf", "dng", "cr2", "nef", "arw"]
    @State private var defaults: [String: String] = [:]
    @State private var busy: String?
    @State private var message = ""
    var body: some View {
        Form {
            Section {
                ForEach(formats, id: \.self) { ext in
                    HStack {
                        Text(ext.uppercased()).frame(width: 58, alignment: .leading)
                        Text(".\(ext)").foregroundStyle(.secondary).frame(width: 46, alignment: .leading)
                        Spacer()
                        Text(defaults[ext] ?? "未设置").foregroundStyle(.secondary).lineLimit(1)
                        if defaults[ext] == "ViaView" {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("已设为 ViaView")
                        } else {
                            Button("设为 ViaView") { setDefault(ext) }.disabled(busy != nil)
                        }
                    }
                }
            } header: { Text("默认看图应用") } footer: {
                Text("选择后仅修改该类文件的默认打开方式。macOS 可能要求确认；RAW 格式是否可解码取决于系统对相机的支持。")
            }
            if !message.isEmpty { Section { Text(message).foregroundStyle(.secondary) } }
        }
        .formStyle(.grouped).onAppear { refresh() }
    }
    private func refresh() {
        for ext in formats {
            if let type = UTType(filenameExtension: ext), let app = NSWorkspace.shared.urlForApplication(toOpen: type) {
                defaults[ext] = Bundle(url: app)?.bundleIdentifier == Bundle.main.bundleIdentifier ? "ViaView" : (FileManager.default.displayName(atPath: app.path) as NSString).deletingPathExtension
            } else { defaults[ext] = "未设置" }
        }
    }
    private func setDefault(_ ext: String) {
        guard let type = UTType(filenameExtension: ext) else { return }
        busy = ext; message = ""
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type) { error in
            DispatchQueue.main.async {
                busy = nil; refresh()
                message = error.map { "未能修改 \(ext.uppercased())：\($0.localizedDescription)" } ?? "\(ext.uppercased()) 已设为使用 ViaView 打开。"
            }
        }
    }
}
