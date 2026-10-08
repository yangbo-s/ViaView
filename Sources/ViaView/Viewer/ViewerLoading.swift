import AppKit
import ViewerCore

extension ViewerController {
    func openURLs(_ urls: [URL]) {
        guard let first = urls.first else { return }
        timer?.invalidate(); timer = nil
        galleryRevision += 1
        gallery = Gallery(); resetImageState(); updateUI()
        urls.forEach { FileAccessStore.shared.retain($0) }
        let isFolder = (try? first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        let folder = isFolder ? first : first.deletingLastPathComponent()
        loadSerial += 1; let serial = loadSerial
        let sort = self.sort, descending = self.descending
        showMessage("正在读取图片…", detail: "", loading: true)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scanned = Result { try Gallery.scan(folder, sort: sort, descending: descending) }
            DispatchQueue.main.async {
                guard let self, self.loadSerial == serial else { return }
                switch scanned {
                case .success(let files):
                    let usable = urls.count > 1 ? urls.filter(Gallery.accepts) : files
                    let candidates = usable.isEmpty && !isFolder && Gallery.accepts(first) ? [first] : usable
                    self.gallery = Gallery(urls: self.excludingRecycledFiles(candidates), selected: isFolder ? nil : first)
                    self.needsFolderAccess = false
                case .failure:
                    self.gallery = Gallery(urls: self.excludingRecycledFiles(isFolder ? [] : urls.filter(Gallery.accepts)), selected: first)
                    self.needsFolderAccess = !isFolder
                }
                if self.sort != sort || self.descending != descending { self.reorderGallery() }
                if self.gallery.current != nil { NSDocumentController.shared.noteNewRecentDocumentURL(first); self.loadCurrent() }
                else { self.asset = nil; self.showMessage("没有可浏览的图片", detail: "选择包含常见图片格式的文件夹；若文件夹未授权，请重新通过“打开”选择它。", loading: false); self.updateUI() }
            }
        }
    }
    func loadCurrent() {
        guard let url = gallery.current else { return }
        loadSerial += 1; let serial = loadSerial; resetImageState()
        showMessage("正在打开…", detail: url.lastPathComponent, loading: true); updateUI()
        loadOperation = ImagePipeline.shared.load(url) { [weak self] result in
            guard let self, self.loadSerial == serial else { return }
            switch result {
            case .success(let asset):
                self.asset = asset; self.displayedCG = asset.cgImage; self.empty.isHidden = true; self.progress.stopAnimation(nil)
                if asset.isSVG { self.showSVG(url, serial: serial) }
                else {
                    self.scroll.isHidden = false; self.web?.isHidden = true
                    self.canvas.image = asset.image; self.canvas.animates = asset.canAnimate
                    self.scroll.documentView = self.canvas
                    self.canvas.frame = NSRect(origin: .zero, size: asset.image.size)
                    self.prepareImageWindow(); self.window?.makeFirstResponder(self.canvas)
                }
                self.updateUI(); self.rebuildInspector()
                let adjacent = [self.gallery.index - 1, self.gallery.index + 1].filter { self.gallery.urls.indices.contains($0) }.map { self.gallery.urls[$0] }
                if UserDefaults.standard.bool(forKey: "preloadImages") { ImagePipeline.shared.prefetch(adjacent) }
            case .failure(let error): self.showMessage("这张图片无法打开", detail: error.localizedDescription + "\n可以继续切换其他图片。", loading: false); self.updateUI()
            }
        }
    }
    func resetImageState() {
        zoomDriver.reset(1)
        loadOperation?.cancel(); editOperation?.cancel(); editSerial += 1; editPending = false
        asset = nil; displayedCG = nil; edits = ImageEdits(); canvas.image = nil; canvas.selection = .zero
        feedbackGeneration += 1; colorFeedback.isHidden = true
        web?.stopLoading(); web?.isHidden = true; rebuildInspector()
    }
}
