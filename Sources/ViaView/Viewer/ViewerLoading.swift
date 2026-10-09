import AppKit
import ViewerCore

extension ViewerController {
    func openURLs(_ urls: [URL]) {
        guard let first = urls.first else { return }
        timer?.invalidate(); timer = nil
        galleryRevision += 1; let revision = galleryRevision
        urls.forEach { FileAccessStore.shared.retain($0) }
        let isFolder = (try? first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        needsFolderAccess = false
        gallery = Gallery(urls: excludingRecycledFiles(isFolder ? [] : urls.filter(Gallery.accepts)), selected: first)
        if gallery.current != nil {
            NSDocumentController.shared.noteNewRecentDocumentURL(first)
            loadCurrent()
            // Multiple explicitly selected files form their own gallery.
            if urls.count > 1 { reorderGallery(); return }
        } else {
            loadSerial += 1; resetImageState(preservingPresentation: true); isLoading = true
            showMessage("正在读取图片…", detail: "", loading: true); updateUI()
        }
        let folder = isFolder ? first : first.deletingLastPathComponent()
        let sort = self.sort, descending = self.descending, scan = scanFolder
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let scanned = Result { try scan(folder, sort, descending) }
            DispatchQueue.main.async {
                guard let self, self.galleryRevision == revision else { return }
                let selected = self.gallery.current
                switch scanned {
                case .success(let files):
                    var candidates = files
                    // A file selected explicitly may not be enumerable in its parent.
                    if let selected, !candidates.contains(selected) { candidates.append(selected) }
                    self.sortRevision += 1
                    self.gallery = Gallery(urls: self.excludingRecycledFiles(candidates), selected: selected)
                    self.needsFolderAccess = false
                case .failure:
                    self.needsFolderAccess = !isFolder
                }
                if self.sort != sort || self.descending != descending { self.reorderGallery() }
                if selected == nil, self.gallery.current != nil {
                    NSDocumentController.shared.noteNewRecentDocumentURL(first); self.loadCurrent()
                } else if self.gallery.current == nil {
                    self.resetImageState()
                    self.showMessage("没有可浏览的图片", detail: "选择包含常见图片格式的文件夹；若文件夹未授权，请重新通过“打开”选择它。", loading: false)
                }
                self.updateUI()
                if self.asset != nil { self.prefetchNeighbors() }
            }
        }
    }

    func loadCurrent() {
        guard let url = gallery.current else { return }
        loadSerial += 1; let serial = loadSerial
        resetImageState(preservingPresentation: true); isLoading = true
        showMessage("正在打开…", detail: url.lastPathComponent, loading: true); updateUI()
        loadOperation = imagePipeline.load(url) { [weak self] result in
            guard let self, self.loadSerial == serial else { return }
            switch result {
            case .success(let asset):
                if asset.isSVG { self.showSVG(asset, serial: serial) }
                else {
                    self.web?.navigationDelegate = nil; self.web?.stopLoading(); self.web?.removeFromSuperview(); self.web = nil
                    self.canvas.image = asset.image; self.canvas.animates = asset.canAnimate
                    self.scroll.documentView = self.canvas
                    self.canvas.frame = NSRect(origin: .zero, size: asset.image.size)
                    self.presentImage(asset)
                    self.window?.makeFirstResponder(self.canvas)
                }
            case .failure(let error):
                self.showMessage("这张图片无法打开", detail: error.localizedDescription + "\n可以继续切换其他图片。", loading: false); self.updateUI()
            }
        }
    }

    func presentImage(_ asset: ImageAsset) {
        self.asset = asset; displayedCG = asset.cgImage
        empty.isHidden = true; progress.stopAnimation(nil); progress.isHidden = true; scroll.isHidden = false
        isLoading = false
        zoomDriver.reset(1); prepareImageWindow(); updateUI(); finishWindowPresentation()
        let serial = loadSerial
        // Let the first frame reach the window before optional tool-panel work.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.loadSerial == serial else { return }
            if self.inspectorPanel?.isVisible == true { self.rebuildInspector() }
            self.prefetchNeighbors()
        }
    }

    func prefetchNeighbors() {
        guard UserDefaults.standard.bool(forKey: "preloadImages") else { return }
        let adjacent = [gallery.index - 1, gallery.index + 1].filter { gallery.urls.indices.contains($0) }.map { gallery.urls[$0] }
        imagePipeline.prefetch(adjacent)
    }

    func resetImageState(preservingPresentation: Bool = false) {
        zoomDriver.stop()
        loadOperation?.cancel(); editOperation?.cancel(); editSerial += 1; editPending = false
        asset = nil; displayedCG = nil; edits = ImageEdits(); canvas.selection = .zero
        feedbackGeneration += 1; colorFeedback.isHidden = true
        pendingSVG?.browser.navigationDelegate = nil; pendingSVG?.browser.stopLoading(); pendingSVG = nil
        if !preservingPresentation {
            zoomDriver.reset(1); canvas.image = nil
            web?.navigationDelegate = nil; web?.stopLoading(); web?.removeFromSuperview(); web = nil
            scroll.isHidden = true
        }
        if inspectorPanel?.isVisible == true { rebuildInspector() }
    }
}
