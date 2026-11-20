import AppKit
import ViewerCore

extension ViewerController {
    func canNavigate(_ direction: Int) -> Bool {
        guard direction != 0 else { return false }
        if needsFolderAccess { return gallery.current != nil }
        guard gallery.urls.count > 1 else { return false }
        let wrap = UserDefaults.standard.object(forKey: "wrap") == nil || UserDefaults.standard.bool(forKey: "wrap")
        return wrap || (direction < 0 ? gallery.index > 0 : gallery.index < gallery.urls.count - 1)
    }

    func move(_ delta: Int) {
        if needsFolderAccess, delta != 0 {
            requestFolderAccess(navigateBy: delta)
            return
        }
        guard gallery.urls.count > 1 else { return }
        let before = gallery.index
        let wrap = UserDefaults.standard.object(forKey: "wrap") == nil || UserDefaults.standard.bool(forKey: "wrap")
        gallery.move(delta, wrap: wrap)
        if gallery.index != before { loadCurrent() } else if timer != nil { slideshow(nil) }
    }
    @objc func previous(_ sender: Any?) { move(-1) }
    @objc func next(_ sender: Any?) { move(1) }
    func reorderGallery(navigateBy step: Int? = nil) {
        sortRevision += 1
        let revision = sortRevision, context = galleryRevision
        let urls = gallery.urls, order = sort, reversed = descending
        guard !urls.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let ordered = Gallery.ordered(urls, by: order, descending: reversed)
            DispatchQueue.main.async {
                guard let self, self.galleryRevision == context, self.sortRevision == revision else { return }
                // Navigation and recycling can happen while sorting. Keep the live
                // selection and only reorder members still present in this gallery.
                let remaining = Set(self.gallery.urls)
                self.gallery = Gallery(urls: ordered.filter(remaining.contains), selected: self.gallery.current)
                self.updateUI()
                if let step { self.move(step) }
            }
        }
    }
    @objc func grantFolder(_ sender: Any?) { requestFolderAccess() }

    func offerFolderAccessIfNeeded() {
        guard pendingFolderAccessPrompt, !isLoading, window?.isVisible == true else { return }
        requestFolderAccess()
    }

    func dismissFolderAccessPrompt() {
        pendingFolderAccessPrompt = false
        let panel = folderAccessPanel
        folderAccessPanel = nil
        panel?.cancel(nil)
    }

    private func requestFolderAccess(navigateBy step: Int? = nil) {
        guard needsFolderAccess, let current = gallery.current, let window,
              window.attachedSheet == nil, folderAccessPanel == nil else { return }
        let folder = current.deletingLastPathComponent()
        let revision = galleryRevision
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = folder
        panel.message = "选择图片所在文件夹以浏览相邻图片"
        panel.prompt = "允许此文件夹"
        pendingFolderAccessPrompt = false
        folderAccessPanel = panel
        panel.beginSheetModal(for: window) { [weak self] response in
            guard let self, self.folderAccessPanel === panel else { return }
            self.folderAccessPanel = nil
            guard response == .OK, self.galleryRevision == revision, let authorized = panel.url else { return }
            guard folder.resolvingSymlinksInPath().pathComponents.starts(with: authorized.resolvingSymlinksInPath().pathComponents) else {
                let alert = NSAlert()
                alert.messageText = "请选择包含当前图片的文件夹"
                alert.beginSheetModal(for: window)
                return
            }
            FileAccessStore.shared.retain(authorized)
            self.refreshFolderGallery(navigateBy: step)
            (NSApp.delegate as? AppDelegate)?.foldersAuthorized([authorized])
        }
    }
    @objc func slideshow(_ sender: Any?) {
        if let timer { timer.invalidate(); self.timer = nil }
        else if gallery.urls.count > 1 {
            let interval = UserDefaults.standard.integer(forKey: "slideDelay")
            timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(interval > 0 ? interval : 3), repeats: true) { [weak self] _ in self?.move(1) }
        }
        updateCommandControls()
    }
}
