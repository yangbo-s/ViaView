import AppKit
import ViewerCore

extension ViewerController {
    func openURLs(_ urls: [URL], offerFolderAccess: Bool = false) {
        guard let first = urls.first else { return }
        fitting = true
        timer?.invalidate(); timer = nil
        galleryRevision += 1
        dismissFolderAccessPrompt()
        urls.forEach { FileAccessStore.shared.retain($0) }
        let isFolder = (try? first.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true
        needsFolderAccess = false
        gallery = Gallery(urls: excludingRecycledFiles(isFolder ? [] : urls.filter(Gallery.accepts)), selected: first)
        if gallery.current != nil {
            pendingFolderAccessPrompt = offerFolderAccess && urls.count == 1
            NSDocumentController.shared.noteNewRecentDocumentURL(first)
            loadCurrent()
            // Multiple explicitly selected files form their own gallery.
            if urls.count > 1 { reorderGallery(); return }
        } else {
            loadSerial += 1; resetImageState(preservingPresentation: true); isLoading = true
            showMessage("正在读取图片…", detail: "", loading: true); updateUI()
        }
        let folder = isFolder ? first : first.deletingLastPathComponent()
        scanGallery(in: folder, recentDocument: first)
    }

    func refreshFolderGallery(navigateBy step: Int? = nil) {
        guard needsFolderAccess, let current = gallery.current else { return }
        galleryRevision += 1
        dismissFolderAccessPrompt()
        needsFolderAccess = false
        updateUI()
        scanGallery(in: current.deletingLastPathComponent(), navigateBy: step)
    }

    private func scanGallery(in folder: URL, recentDocument: URL? = nil, navigateBy step: Int? = nil) {
        let revision = galleryRevision
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
                case .failure(let error):
                    let cocoa = (error as? CocoaError)?.code
                    let posix = (error as? POSIXError)?.code
                    self.needsFolderAccess = selected != nil &&
                        (cocoa == .fileReadNoPermission || posix == .EACCES || posix == .EPERM)
                }
                if !self.needsFolderAccess { self.pendingFolderAccessPrompt = false }
                if selected == nil, self.gallery.current != nil {
                    if let recentDocument { NSDocumentController.shared.noteNewRecentDocumentURL(recentDocument) }
                    self.loadCurrent()
                } else if self.gallery.current == nil {
                    self.resetImageState()
                    self.showMessage("没有可浏览的图片", detail: "选择包含常见图片格式的文件夹；若文件夹未授权，请重新通过“打开”选择它。", loading: false)
                }
                self.updateUI()
                let pendingStep = self.gallery.current == selected && !self.needsFolderAccess ? step : nil
                if self.sort != sort || self.descending != descending {
                    self.reorderGallery(navigateBy: pendingStep)
                } else if let pendingStep {
                    self.move(pendingStep)
                }
                if self.asset != nil { self.prefetchNeighbors() }
                self.offerFolderAccessIfNeeded()
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
        // Hidden AppKit stacks still contribute their text's fitting width to
        // the window. Retire the loading message before applying image geometry.
        emptyTitle.stringValue = ""; emptyDetail.stringValue = ""
        empty.isHidden = true; progress.stopAnimation(nil); progress.isHidden = true; scroll.isHidden = false
        isLoading = false
        prepareImageWindow(preservingZoom: true); updateUI(); finishWindowPresentation()
        let serial = loadSerial
        // Let the first frame reach the window before optional tool-panel work.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.loadSerial == serial else { return }
            self.refreshLiveText()
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
        liveText.reset()
        zoomDriver.stop()
        loadOperation?.cancel(); editOperation?.cancel(); editSerial += 1; editPending = false
        asset = nil; displayedCG = nil; edits = ImageEdits(); canvas.selection = .zero
        feedbackGeneration += 1; colorFeedback.isHidden = true
        pendingSVG?.browser.navigationDelegate = nil; pendingSVG?.browser.stopLoading(); pendingSVG = nil
        if !preservingPresentation {
            fitting = true; zoomDriver.reset(1); canvas.image = nil
            web?.navigationDelegate = nil; web?.stopLoading(); web?.removeFromSuperview(); web = nil
            scroll.isHidden = true
        }
        if inspectorPanel?.isVisible == true { rebuildInspector() }
    }
}
