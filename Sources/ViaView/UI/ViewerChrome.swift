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
        nameLabel.toolTip = nameLabel.stringValue
        updatePageCount(current: gallery.index + 1, total: gallery.urls.count)
        if let asset {
            let w = edits.turns % 2 == 0 ? asset.pixelWidth : asset.pixelHeight, h = edits.turns % 2 == 0 ? asset.pixelHeight : asset.pixelWidth
            imageSummary = asset.isSVG ? "SVG · 矢量图像" : "\(w) × \(h) px  ·  \(asset.url.pathExtension.uppercased())\(asset.isPreview ? " · 大图预览" : "")"
        }
        else { imageSummary = "本地图片 · 原生浏览" }
        for (key, button) in buttons {
            switch key {
            case "previous": button.isEnabled = canNavigate(-1)
            case "next": button.isEnabled = canNavigate(1)
            default: button.isEnabled = key == "fullscreen" || asset != nil
            }
        }
        if fileListPanel?.isVisible == true { fileList.update(urls: gallery.urls, selected: gallery.current, sort: sort, descending: descending) }
        if tagsPanel?.isVisible == true { tagsController.setURL(gallery.current) }
        updateCommandControls(); updateCanvasAccessibility(); layoutChrome(); refreshChrome()
    }
    func updateCanvasAccessibility() {
        let percent = scroll.magnification * (window?.backingScaleFactor ?? 2) * 100
        canvas.setAccessibilityValue(gallery.urls.isEmpty ? "尚未打开图片" : "\(gallery.current?.lastPathComponent ?? "")，\(gallery.index + 1) / \(gallery.urls.count)，缩放 \(Int(percent))%")
    }
    func setWindowControls(_ visible: Bool) {
        windowControlsVisible = visible && !samplingColor && (asset == nil || stage.bounds.width >= 170)
        windowButtons.forEach { $0.isHidden = !windowControlsVisible }
        topChrome.isHidden = !windowControlsVisible
        if windowControlsVisible { topChrome.layoutSubtreeIfNeeded(); updateTitleContrast() }
    }
    func pointer(_ point: NSPoint?) {
        guard !samplingColor else {
            liveText.setHoverVisible(false, suppressed: true)
            setWindowControls(false); setChrome(false); return
        }
        let inside = point.map { stage.bounds.contains($0) } ?? false
        let accessible = NSWorkspace.shared.isVoiceOverEnabled
        setWindowControls(asset == nil || accessible || (inside && point!.y > stage.bounds.height - 64))
        let nearBottom = inside && point!.y < min(72, stage.bounds.height / 3)
        liveText.setHoverVisible(accessible || nearBottom)
        setChrome(accessible || nearBottom)
    }
    func refreshChrome() {
        guard let window else { return }
        pointer(stage.convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil))
    }
    func setChrome(_ visible: Bool) {
        let available = asset != nil && stage.bounds.width >= 180 && stage.bounds.height >= 180 && !liveText.isEngaged
        guard chromeVisible != visible else {
            bottomChrome.isHidden = !visible || !available
            return
        }
        chromeVisible = visible; chromeGeneration += 1; let generation = chromeGeneration
        if visible { bottomChrome.isHidden = !available }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : 0.12
            bottomChrome.animator().alphaValue = visible ? 1 : 0
        } completionHandler: { [weak self] in
            guard let self, self.chromeGeneration == generation, !visible else { return }
            self.bottomChrome.isHidden = true
        }
    }
}
