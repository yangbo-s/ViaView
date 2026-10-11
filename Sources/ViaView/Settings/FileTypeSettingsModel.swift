import AppKit
import Combine
import UniformTypeIdentifiers

struct FileTypeApplication: Identifiable, Equatable {
    let url: URL
    let id: String
    let name: String

    static func read(at url: URL) -> FileTypeApplication? {
        guard url.isFileURL, url.pathExtension.lowercased() == "app",
              let bundle = Bundle(url: url),
              bundle.object(forInfoDictionaryKey: "CFBundlePackageType") as? String == "APPL",
              let id = bundle.bundleIdentifier, !id.isEmpty else { return nil }
        return FileTypeApplication(url: url, id: id,
                                   name: (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension)
    }
}

/// Keep Launch Services at one boundary so checks never change the user's defaults.
struct FileTypeAssociationClient {
    var ownApplication: FileTypeApplication
    var read: (String) -> FileTypeApplication?
    var applications: (String) -> [FileTypeApplication]
    var set: (String, FileTypeApplication, @escaping (Error?) -> Void) -> Void

    static let system = FileTypeAssociationClient(
        ownApplication: FileTypeApplication(url: Bundle.main.bundleURL, id: Bundle.main.bundleIdentifier ?? "", name: "ViaView"),
        read: { ext in
            guard let type = UTType(filenameExtension: ext), let app = NSWorkspace.shared.urlForApplication(toOpen: type) else { return nil }
            return FileTypeApplication.read(at: app)
        }, applications: { ext in
            guard let type = UTType(filenameExtension: ext) else { return [] }
            return NSWorkspace.shared.urlsForApplications(toOpen: type).compactMap { FileTypeApplication.read(at: $0) }
        }, set: { ext, application, completion in
            guard let type = UTType(filenameExtension: ext) else {
                completion(NSError(domain: "ViaView.FileTypes", code: 1, userInfo: [NSLocalizedDescriptionKey: "系统无法识别此文件类型。"])); return
            }
            let access = application.url.startAccessingSecurityScopedResource()
            guard FileTypeApplication.read(at: application.url)?.id == application.id else {
                if access { application.url.stopAccessingSecurityScopedResource() }
                completion(NSError(domain: "ViaView.FileTypes", code: 2, userInfo: [NSLocalizedDescriptionKey: "所选应用已不可用，请重新选择。"])); return
            }
            NSWorkspace.shared.setDefaultApplication(at: application.url, toOpen: type) { error in
                if access { application.url.stopAccessingSecurityScopedResource() }
                completion(error)
            }
        })
}

final class FileTypeSettingsModel: ObservableObject {
    static let supportedFormats = ["png", "jpg", "gif", "tiff", "bmp", "webp", "heic", "heif", "avif", "ico", "psd", "tga", "svg", "pdf", "dng", "cr2", "nef", "arw"]
    let formats: [String]
    private let client: FileTypeAssociationClient
    @Published private(set) var associations: [String: FileTypeApplication] = [:]
    @Published private(set) var busy: String?
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var message = ""
    private var remaining: [String] = []
    private var failures: [(String, String)] = []
    private var succeeded = 0
    private var skipped = 0
    private var target: FileTypeApplication
    private var isUnbinding = false

    var configuredCount: Int { formats.filter(isViaView).count }
    var allConfigured: Bool { configuredCount == formats.count }
    var progressText: String { busy.map { "正在将 \($0.uppercased()) 改为 \(target.name)（\(completed + 1)/\(total)）…" } ?? "" }

    init(formats: [String] = supportedFormats, client: FileTypeAssociationClient = .system) {
        var seen = Set<String>()
        self.formats = formats.filter { seen.insert($0).inserted }
        self.client = client; target = client.ownApplication
        refresh()
    }

    func isViaView(_ ext: String) -> Bool { associations[ext]?.id == client.ownApplication.id }

    func refresh() {
        associations = Dictionary(uniqueKeysWithValues: formats.compactMap { ext in client.read(ext).map { (ext, $0) } })
    }

    /// For a batch, recommend only applications that advertise every selected type.
    func replacementApplications(for requested: [String]) -> [FileTypeApplication] {
        let lists = requested.filter { formats.contains($0) }.map { client.applications($0) }
        guard let first = lists.first else { return [] }
        var seen = Set<String>()
        return first.filter { app in
            app.id != client.ownApplication.id && seen.insert(app.id).inserted &&
            lists.dropFirst().allSatisfy { $0.contains { $0.id == app.id } }
        }
    }

    func canUnbind(to application: FileTypeApplication) -> Bool {
        !application.id.isEmpty && application.id != client.ownApplication.id && application.url.isFileURL
    }

    func setAll() { setDefaults(formats, to: client.ownApplication, unbinding: false) }
    func setDefault(_ ext: String) { guard formats.contains(ext) else { return }; setDefaults([ext], to: client.ownApplication, unbinding: false) }

    func unbind(_ requested: [String], to application: FileTypeApplication) {
        guard busy == nil else { return }
        guard canUnbind(to: application) else { message = "请选择 ViaView 以外的应用。"; return }
        setDefaults(requested, to: application, unbinding: true)
    }

    private func setDefaults(_ requested: [String], to application: FileTypeApplication, unbinding: Bool) {
        guard busy == nil else { return }
        refresh()
        target = application; isUnbinding = unbinding
        remaining = formats.filter { requested.contains($0) && (unbinding ? isViaView($0) : associations[$0]?.id != target.id) }
        completed = 0; total = remaining.count; succeeded = 0; skipped = 0; failures = []; message = ""
        guard !remaining.isEmpty else {
            message = unbinding ? "所选文件类型已不再使用 ViaView，无需解绑。" : "所选文件类型已全部使用 ViaView 打开。"
            return
        }
        setNext()
    }

    private func setNext() {
        // Recheck queued types: another app may have changed a default while a
        // system consent dialog was open. Unbinding must not overwrite that choice.
        while let ext = remaining.first {
            let current = client.read(ext)
            if isUnbinding ? current?.id == client.ownApplication.id : current?.id != target.id { break }
            remaining.removeFirst(); completed += 1; skipped += 1
        }
        guard !remaining.isEmpty else {
            busy = nil; refresh()
            if failures.isEmpty {
                message = isUnbinding ? "已解绑 \(succeeded) 种文件类型，改用 \(target.name) 打开。" : "已将 \(succeeded) 种文件类型设为使用 \(target.name) 打开。"
            } else {
                let summary = succeeded > 0 ? "已设置 \(succeeded) 种，\(failures.count) 种未完成。" : "\(failures.count) 种文件类型未能修改。"
                message = summary + "\n" + failures.map { "\($0.0.uppercased())：\($0.1)" }.joined(separator: "\n") + "\n可以重试未完成的项目。"
            }
            if skipped > 0 { message += "\n已跳过 \(skipped) 种默认应用已变化的类型。" }
            return
        }
        let ext = remaining.removeFirst(); busy = ext
        // A batch stays serial, including any confirmation macOS needs to show.
        client.set(ext, target) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                let current = self.client.read(ext)
                self.associations[ext] = current
                if current?.id == self.target.id { self.succeeded += 1 }
                else { self.failures.append((ext, error?.localizedDescription ?? "系统尚未更改为所选应用。")) }
                self.completed += 1
                self.setNext()
            }
        }
    }
}
