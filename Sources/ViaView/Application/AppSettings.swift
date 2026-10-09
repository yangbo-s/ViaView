import AppKit
import ViewerCore

enum AppTheme: String, CaseIterable {
    case system, light, dark
    var title: String {
        switch self {
        case .system: return "跟随系统"
        case .light: return "浅色"
        case .dark: return "深色"
        }
    }
    var appearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

enum AppSettings {
    static let defaults: [String: Any] = [
        "wrap": true, "themeMode": AppTheme.system.rawValue, "slideDelay": 3,
        "selectOnDrag": false, "doubleClickZoom": true, "smoothRendering": true,
        "swipeNavigate": true, "zoomSensitivity": 1.0, "checkerboard": true,
        "openInNewWindow": false, "restoreWindows": false, "quitLastWindow": false,
        "preloadImages": true, "cacheMB": 256, "editorBundleID": "com.apple.Preview",
        "fileListGrid": false, "bookmarks": [Data](), "openImagePaths": [String]()
    ]
    static func register(in store: UserDefaults = .standard, domain: String? = Bundle.main.bundleIdentifier) {
        // Only migrate an explicitly saved old preference, never the old default.
        // Registration supplies first-launch defaults without overwriting user choices.
        if let domain, let saved = store.persistentDomain(forName: domain), saved["themeMode"] == nil,
           let dark = saved["darkCanvas"] as? Bool {
            store.set((dark ? AppTheme.dark : .light).rawValue, forKey: "themeMode")
        }
        store.register(defaults: defaults)
    }
    static func theme(in store: UserDefaults = .standard) -> AppTheme {
        AppTheme(rawValue: store.string(forKey: "themeMode") ?? "") ?? .system
    }
    static var editorURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: UserDefaults.standard.string(forKey: "editorBundleID") ?? "com.apple.Preview")
    }
    static var editorName: String {
        editorURL.map { (FileManager.default.displayName(atPath: $0.path) as NSString).deletingPathExtension } ?? "外部编辑器"
    }
}

extension AppDelegate {
    func viewerForOpening() -> ViewerController {
        if UserDefaults.standard.bool(forKey: "openInNewWindow"), activeViewer?.gallery.current != nil { return newViewer() }
        return activeViewer ?? newViewer()
    }
    func applySettings() {
        let appearance = AppSettings.theme().appearance
        if NSApp.appearance?.name != appearance?.name { NSApp.appearance = appearance }
        ImagePipeline.shared.setCacheLimit(megabytes: UserDefaults.standard.integer(forKey: "cacheMB"))
        viewers.forEach { viewer in
            viewer.refreshAppearance(); viewer.canvas.needsDisplay = true; viewer.updateUI()
            let delay = TimeInterval(max(2, UserDefaults.standard.integer(forKey: "slideDelay")))
            if let timer = viewer.timer, timer.timeInterval != delay {
                timer.invalidate(); viewer.timer = nil; viewer.slideshow(nil)
            }
        }
    }
    func saveSession() {
        UserDefaults.standard.set(viewers.compactMap { $0.gallery.current?.path }, forKey: "openImagePaths")
    }
    func foldersAuthorized(_ folders: [URL]) {
        for viewer in viewers where viewer.needsFolderAccess {
            guard let current = viewer.gallery.current, folders.contains(where: { current.path.hasPrefix($0.path.hasSuffix("/") ? $0.path : $0.path + "/") }) else { continue }
            let sort = viewer.sort, descending = viewer.descending, serial = viewer.loadSerial
            DispatchQueue.global(qos: .userInitiated).async { [weak viewer] in
                let files = try? Gallery.scan(current.deletingLastPathComponent(), sort: sort, descending: descending)
                DispatchQueue.main.async {
                    guard let viewer, viewer.loadSerial == serial, viewer.gallery.current == current, let files, files.contains(current) else { return }
                    // Refresh navigation without discarding the current zoom or unsaved edits.
                    viewer.galleryRevision += 1
                    viewer.gallery = Gallery(urls: viewer.excludingRecycledFiles(files), selected: current); viewer.needsFolderAccess = false
                    // Folder authorization may finish after a newer sort choice.
                    if viewer.sort != sort || viewer.descending != descending { viewer.reorderGallery() }
                    viewer.updateUI()
                }
            }
        }
    }
}
