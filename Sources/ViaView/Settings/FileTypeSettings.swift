import AppKit
import SwiftUI

struct FileTypeSettings: View {
    @StateObject private var model = FileTypeSettingsModel()
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("\(model.configuredCount) / \(model.formats.count) 种文件类型已使用 ViaView")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(model.allConfigured ? "已全部设为 ViaView" : "全部设为 ViaView") { model.setAll() }
                        .disabled(model.busy != nil || model.allConfigured)
                }
                if model.busy != nil {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text(model.progressText).foregroundStyle(.secondary)
                    }.accessibilityElement(children: .combine)
                }
                if !model.message.isEmpty { Text(model.message).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
            } header: { Text("默认看图应用") } footer: {
                Text("一键设置下列全部类型，自动跳过已设置的项目。macOS 可能逐项要求确认。")
            }
            Section {
                ForEach(model.formats, id: \.self) { ext in
                    HStack {
                        Text(ext.uppercased()).frame(width: 58, alignment: .leading)
                        Text(".\(ext)").foregroundStyle(.secondary).frame(width: 46, alignment: .leading)
                        Text(model.associations[ext]?.applicationName ?? "未设置").foregroundStyle(.secondary).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Group {
                            if model.associations[ext]?.isViaView == true {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).accessibilityLabel("\(ext.uppercased()) 已设为 ViaView")
                            } else {
                                Button("设为 ViaView") { model.setDefault(ext) }.disabled(model.busy != nil)
                                    .accessibilityLabel("将 \(ext.uppercased()) 设为使用 ViaView 打开")
                            }
                        }.frame(width: 104)
                    }
                }
            } footer: {
                Text("也可以单独修改某种类型。RAW 格式是否可解码取决于系统对相机的支持。")
            }
        }
        .formStyle(.grouped).onAppear { model.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in model.refresh() }
    }
}
