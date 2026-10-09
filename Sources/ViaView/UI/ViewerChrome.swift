import AppKit
import ViewerCore

extension ViewerController {
    func showMessage(_ title: String, detail: String, loading: Bool) {
        // Keep the current document on screen while its replacement decodes.
        if loading, !scroll.isHidden, canvas.image != nil || web != nil { return }
        scroll.isHidden = true; web?.isHidden = true
        if !loading, asset == nil { resetEmptyWindow() }
        empty.isHidden = false; emptyTitle.stringValue = title; emptyDetail.stringValue = detail
        progress.isHidden = !loading
        loading ? progress.startAnimation(nil) : progress.stopAnimation(nil)
        if !loading { finishWindowPresentation() }
    }
    func updateUI() {
        window?.title = gallery.current?.lastPathComponent ?? "ViaView"; window?.representedURL = gallery.current
        nameLabel.stringValue = isLoading ? "正在打开 \(gallery.current?.lastPathComponent ?? "图片…")" : (gallery.current?.lastPathComponent ?? "ViaView")
        countLabel.stringValue = gallery.urls.isEmpty ? "—" : "\(gallery.index + 1) / \(gallery.urls.count)"
        if let asset {
            let w = edits.turns % 2 == 0 ? asset.pixelWidth : asset.pixelHeight, h = edits.turns % 2 == 0 ? asset.pixelHeight : asset.pixelWidth
            imageSummary = asset.isSVG ? "SVG · 矢量图像" : "\(w) × \(h) px  ·  \(asset.url.pathExtension.uppercased())\(asset.isPreview ? " · 大图预览" : "")"
        }
        else { imageSummary = "本地图片 · 原生浏览" }
        for (key, button) in buttons { button.isEnabled = ["previous", "next", "compactPrevious", "compactNext"].contains(key) ? gallery.urls.count > 1 : (key == "fullscreen" || asset != nil) }
        buttons["rotate"]?.isEnabled = displayedCG != nil
        updateSlideshowButton()
        if fileListPanel?.isVisible == true { fileList.update(urls: gallery.urls, selected: gallery.current, sort: sort, descending: descending) }
        if tagsPanel?.isVisible == true { tagsController.setURL(gallery.current) }
        updateTitleContrast(); updateZoomLabel(); layoutChrome(); refreshChrome()
    }
    func updateZoomLabel() {
        let percent = scroll.magnification * (window?.backingScaleFactor ?? 2) * 100
        zoomLabel.stringValue = asset == nil ? "—" : String(format: "%.0f%%", percent)
        canvas.setAccessibilityValue(gallery.urls.isEmpty ? "尚未打开图片" : "\(gallery.current?.lastPathComponent ?? "")，\(gallery.index + 1) / \(gallery.urls.count)，缩放 \(Int(percent))%")
    }
    func pointer(_ point: NSPoint?) {
        guard !samplingColor else { setChrome(false); return }
        let inChrome = point.map { stage.bounds.contains($0) && ($0.y > stage.bounds.height - 64 || $0.y < min(80, stage.bounds.height / 3)) } ?? false
        setChrome(asset == nil || inChrome || NSWorkspace.shared.isVoiceOverEnabled)
    }
    func refreshChrome() {
        guard let window else { return }
        pointer(stage.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil))
    }
    func setChrome(_ visible: Bool) {
        let available = stage.bounds.width >= 170 && stage.bounds.height >= 100
        if visible && available { topChrome.layoutSubtreeIfNeeded(); updateTitleContrast() }
        windowButtons.forEach { $0.isHidden = !visible || !available }
        guard chromeVisible != visible else {
            topChrome.isHidden = !visible || !available
            bottomChrome.isHidden = asset == nil || !visible || stage.bounds.height < 180 || stage.bounds.width < 170
            return
        }
        chromeVisible = visible; chromeGeneration += 1; let generation = chromeGeneration
        if visible { topChrome.isHidden = !available; bottomChrome.isHidden = asset == nil || stage.bounds.height < 180 || stage.bounds.width < 170 }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
            topChrome.animator().alphaValue = visible ? 1 : 0; bottomChrome.animator().alphaValue = visible ? 1 : 0
        } completionHandler: { [weak self] in
            guard let self, self.chromeGeneration == generation, !visible else { return }; self.topChrome.isHidden = true; self.bottomChrome.isHidden = true
        }
    }
}
