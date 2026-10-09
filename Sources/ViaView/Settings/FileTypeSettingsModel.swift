import AppKit
import Combine
import UniformTypeIdentifiers

struct FileTypeAssociation {
    var applicationName: String
    var isViaView: Bool
}

/// Keep Launch Services at one boundary so checks never change the user's defaults.
struct FileTypeAssociationClient {
    var read: (String) -> FileTypeAssociation
    var set: (String, @escaping (Error?) -> Void) -> Void

    static let system = FileTypeAssociationClient(read: { ext in
        guard let type = UTType(filenameExtension: ext), let app = NSWorkspace.shared.urlForApplication(toOpen: type) else {
            return FileTypeAssociation(applicationName: "未设置", isViaView: false)
        }
        let ownID = Bundle.main.bundleIdentifier
        let isViaView = ownID != nil && Bundle(url: app)?.bundleIdentifier == ownID
        return FileTypeAssociation(applicationName: isViaView ? "ViaView" : (FileManager.default.displayName(atPath: app.path) as NSString).deletingPathExtension, isViaView: isViaView)
    }, set: { ext, completion in
        guard let type = UTType(filenameExtension: ext) else {
            completion(NSError(domain: "ViaView.FileTypes", code: 1, userInfo: [NSLocalizedDescriptionKey: "系统无法识别此文件类型。"])); return
        }
        NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type) { completion($0) }
    })
}

final class FileTypeSettingsModel: ObservableObject {
    static let supportedFormats = ["png", "jpg", "gif", "tiff", "bmp", "webp", "heic", "heif", "avif", "ico", "psd", "tga", "svg", "pdf", "dng", "cr2", "nef", "arw"]
    let formats: [String]
    private let client: FileTypeAssociationClient
    @Published private(set) var associations: [String: FileTypeAssociation] = [:]
    @Published private(set) var busy: String?
    @Published private(set) var completed = 0
    @Published private(set) var total = 0
    @Published private(set) var message = ""
    private var remaining: [String] = []
    private var failures: [(String, String)] = []
    private var succeeded = 0

    var configuredCount: Int { formats.filter { associations[$0]?.isViaView == true }.count }
    var allConfigured: Bool { configuredCount == formats.count }
    var progressText: String { busy.map { "正在设置 \($0.uppercased())（\(completed + 1)/\(total)）…" } ?? "" }

    init(formats: [String] = supportedFormats, client: FileTypeAssociationClient = .system) {
        self.formats = formats; self.client = client
        refresh()
    }

    func refresh() {
        associations = Dictionary(uniqueKeysWithValues: formats.map { ($0, client.read($0)) })
    }

    func setAll() { setDefaults(formats) }
    func setDefault(_ ext: String) { guard formats.contains(ext) else { return }; setDefaults([ext]) }

    private func setDefaults(_ requested: [String]) {
        guard busy == nil else { return }
        refresh()
        remaining = requested.filter { associations[$0]?.isViaView != true }
        completed = 0; total = remaining.count; succeeded = 0; failures = []; message = ""
        guard !remaining.isEmpty else { message = "所选文件类型已全部使用 ViaView 打开。"; return }
        setNext()
    }

    private func setNext() {
        guard !remaining.isEmpty else {
            busy = nil; refresh()
            if failures.isEmpty { message = "已将 \(succeeded) 种文件类型设为使用 ViaView 打开。" }
            else {
                let summary = succeeded > 0 ? "已设置 \(succeeded) 种，\(failures.count) 种未完成。" : "\(failures.count) 种文件类型未能修改。"
                message = summary + "\n" + failures.map { "\($0.0.uppercased())：\($0.1)" }.joined(separator: "\n") + "\n可以重试未完成的项目。"
            }
            return
        }
        let ext = remaining.removeFirst(); busy = ext
        // A batch stays serial, including any confirmation macOS needs to show.
        client.set(ext) { [weak self] error in
            DispatchQueue.main.async {
                guard let self else { return }
                let current = self.client.read(ext)
                self.associations[ext] = current
                if current.isViaView { self.succeeded += 1 }
                else { self.failures.append((ext, error?.localizedDescription ?? "系统尚未更改默认应用。")) }
                self.completed += 1
                self.setNext()
            }
        }
    }
}
