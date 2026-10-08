import AppKit
import ViewerCore

enum AppSettings {
    static let defaults: [String: Any] = [
        "wrap": true, "darkCanvas": false, "slideDelay": 3,
        "selectOnDrag": false, "doubleClickZoom": true, "smoothRendering": true,
        "swipeNavigate": true, "zoomSensitivity": 1.0, "checkerboard": true,
        "openInNewWindow": false, "restoreWindows": false, "quitLastWindow": false,
        "preloadImages": true, "cacheMB": 256, "editorBundleID": "com.apple.Preview"
    ]
    static func register() { UserDefaults.standard.register(defaults: defaults) }
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
