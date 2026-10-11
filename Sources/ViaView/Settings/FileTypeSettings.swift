import AppKit
import SwiftUI

struct FileTypeSettings: View {
    @StateObject private var model = FileTypeSettingsModel()
    @State private var unbinding: FileTypeUnbindingRequest?
    var body: some View {
        Form {
            Section {
                HStack {
                    Text("\(model.configuredCount) / \(model.formats.count) 种文件类型已使用 ViaView")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                HStack {
                    Button("全部解绑…") { chooseReplacement(model.formats) }
                        .disabled(model.busy != nil || model.configuredCount == 0)
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
                Text("解绑时选择其他应用接管打开方式；全部解绑只修改仍使用 ViaView 的类型。macOS 可能逐项要求确认。")
            }
            Section {
                ForEach(model.formats, id: \.self) { ext in
                    HStack {
                        Text(ext.uppercased()).frame(width: 58, alignment: .leading)
                        Text(".\(ext)").foregroundStyle(.secondary).frame(width: 46, alignment: .leading)
                        Text(model.associations[ext]?.name ?? "未设置").foregroundStyle(.secondary).lineLimit(1)
                            .help(model.associations[ext]?.name ?? "未设置")
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        Group {
                            if model.isViaView(ext) {
                                Button("解绑…") { chooseReplacement([ext]) }.disabled(model.busy != nil)
                                    .accessibilityLabel("解绑 \(ext.uppercased()) 并更换打开应用")
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
        .sheet(item: $unbinding) { request in
            FileTypeReplacementPicker(model: model, request: request)
        }
    }

    private func chooseReplacement(_ formats: [String]) {
        model.refresh()
        let requested = formats.filter(model.isViaView)
        guard !requested.isEmpty else { return }
        unbinding = FileTypeUnbindingRequest(formats: requested, applications: model.replacementApplications(for: requested))
    }
}

private struct FileTypeUnbindingRequest: Identifiable {
    let id = UUID()
    let formats: [String]
    let applications: [FileTypeApplication]
}

private struct FileTypeReplacementPicker: View {
    @ObservedObject var model: FileTypeSettingsModel
    let request: FileTypeUnbindingRequest
    @Environment(\.dismiss) private var dismiss
    @State private var selected: String = ""
    @State private var customApplication: FileTypeApplication?
    @State private var error = ""

    private var applications: [FileTypeApplication] {
        guard let customApplication else { return request.applications }
        return request.applications.filter { $0.id != customApplication.id } + [customApplication]
    }
    private var selection: FileTypeApplication? { applications.first { $0.id == selected } }
    private var selectionHelp: String {
        if customApplication?.id == selected { return "请确认手动选择的应用能打开所选类型，也可以按格式分别解绑。" }
        return request.applications.isEmpty ? "未找到支持全部所选类型的其他应用，可分别解绑或手动选择。" : "列表显示能打开所选类型的应用，也可以手动选择其他应用。"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(request.formats.count == 1 ? "解绑 \(request.formats[0].uppercased())" : "解绑 \(request.formats.count) 种文件类型")
                .font(.headline)
            Text("选择今后双击这些文件时使用的应用。文件本身不会改变。")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Picker("改用", selection: $selected) {
                Text("选择应用…").tag("")
                ForEach(applications) { application in Text(application.name).tag(application.id) }
            }
            Button("选择其他应用…", action: chooseApplication)
            Text(selectionHelp)
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            if !error.isEmpty { Text(error).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Spacer()
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("解绑并更换") {
                    guard let selection else { return }
                    dismiss()
                    model.unbind(request.formats, to: selection)
                }.keyboardShortcut(.defaultAction).disabled(selection == nil || model.busy != nil)
            }
        }
        .padding(24).frame(width: 420)
    }

    private func chooseApplication() {
        let panel = NSOpenPanel()
        panel.title = "选择默认打开应用"; panel.prompt = "选择应用"
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.canChooseDirectories = false; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        guard let application = FileTypeApplication.read(at: url), model.canUnbind(to: application) else {
            selected = ""; error = "请选择有效的应用，且不能是 ViaView。"; return
        }
        customApplication = application; selected = application.id; error = ""
    }
}
