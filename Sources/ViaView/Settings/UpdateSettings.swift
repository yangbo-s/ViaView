import SwiftUI
import Sparkle
import Combine

final class UpdateSettingsModel: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    @Published private(set) var automaticallyChecksForUpdates = false
    @Published private(set) var automaticallyInstallsUpdates = false
    @Published private(set) var allowsAutomaticUpdates = false
    @Published private(set) var lastUpdateCheckDate: Date?
    private let updater: SPUUpdater

    init(updater: SPUUpdater) {
        self.updater = updater
        updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
        updater.publisher(for: \.automaticallyChecksForUpdates).assign(to: &$automaticallyChecksForUpdates)
        updater.publisher(for: \.automaticallyDownloadsUpdates).assign(to: &$automaticallyInstallsUpdates)
        updater.publisher(for: \.allowsAutomaticUpdates).assign(to: &$allowsAutomaticUpdates)
        updater.publisher(for: \.lastUpdateCheckDate).assign(to: &$lastUpdateCheckDate)
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        updater.automaticallyChecksForUpdates = enabled
    }

    func setAutomaticallyInstallsUpdates(_ enabled: Bool) {
        guard allowsAutomaticUpdates else { return }
        updater.automaticallyDownloadsUpdates = enabled
    }

    func checkForUpdates() {
        guard updater.canCheckForUpdates else { return }
        updater.checkForUpdates()
    }
}

struct UpdateSettings: View {
    @StateObject private var model: UpdateSettingsModel
    private let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"

    init(updater: SPUUpdater) {
        _model = StateObject(wrappedValue: UpdateSettingsModel(updater: updater))
    }

    var body: some View {
        Form {
            Section {
                LabeledContent("当前版本", value: "ViaView \(version)")
                HStack {
                    Button("检查更新…", action: model.checkForUpdates)
                        .disabled(!model.canCheckForUpdates)
                    Spacer()
                    if let date = model.lastUpdateCheckDate {
                        Text("上次检查：\(date.formatted(date: .abbreviated, time: .shortened))")
                            .foregroundStyle(.secondary)
                    }
                }
            } header: { Text("软件更新") }
            Section {
                Toggle("自动检查更新", isOn: Binding(get: { model.automaticallyChecksForUpdates }, set: model.setAutomaticallyChecksForUpdates))
                Toggle("自动安装更新", isOn: Binding(get: { model.automaticallyInstallsUpdates }, set: model.setAutomaticallyInstallsUpdates))
                    .disabled(!model.allowsAutomaticUpdates)
            } header: { Text("自动更新") } footer: {
                Text("自动检查开启时，ViaView 会定期查找新版本。开启自动安装后，会在后台下载更新，并在退出应用时安装。")
            }
        }
        .formStyle(.grouped)
    }
}
