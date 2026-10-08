import AppKit
import QuartzCore
import ViewerCore

extension ViewerController {
    var screenArea: NSRect {
        (window?.screen ?? NSScreen.main)?.visibleFrame.insetBy(dx: 16, dy: 16) ?? NSRect(x: 0, y: 0, width: 1280, height: 800)
    }
    var viewportGeometry: ImageWindowGeometry? {
        guard asset != nil, let document = scroll.documentView else { return nil }
        let available = window?.styleMask.contains(.fullScreen) == true ? scroll.contentSize : screenArea.size
        return ImageWindowGeometry(image: document.frame.size, available: available)
    }
    func prepareImageWindow() {
        guard let geometry = viewportGeometry else { return }
        updateWindowLimits()
        fitting = true
        let initial = min(1 / (window?.backingScaleFactor ?? 2), geometry.maximumScale * 0.82)
        zoomDriver.reset(initial); applyZoom(initial, centerImage: true)
    }
    func updateWindowLimits() {
        guard let window, let geometry = viewportGeometry, !window.styleMask.contains(.fullScreen) else { return }
        window.contentAspectRatio = geometry.image
        window.contentMinSize = geometry.windowSize(at: 0)
        window.contentMaxSize = geometry.windowSize(at: .greatestFiniteMagnitude)
    }
    func applyZoom(_ scale: CGFloat, centerImage: Bool = false) {
        guard let window, let document = scroll.documentView, let geometry = viewportGeometry else { return }
        let oldCenter = NSPoint(x: scroll.contentView.bounds.midX, y: scroll.contentView.bounds.midY)
        applyingViewport = true
        CATransaction.begin(); CATransaction.setDisableActions(true)
        if !window.styleMask.contains(.fullScreen), !transitioningFullScreen {
            let desired = window.frameRect(forContentRect: NSRect(origin: .zero, size: geometry.windowSize(at: scale))).size
            let old = window.frame
            var frame = NSRect(x: old.midX - desired.width / 2, y: old.midY - desired.height / 2, width: desired.width, height: desired.height)
            let area = screenArea
            frame.origin.x = max(area.minX, min(area.maxX - frame.width, frame.minX))
            frame.origin.y = max(area.minY, min(area.maxY - frame.height, frame.minY))
            if abs(old.width - frame.width) > 0.1 || abs(old.height - frame.height) > 0.1 {
                // A single display-linked frame change, never a chain of NSWindow animations.
                window.setFrame(frame, display: false)
                root.layoutSubtreeIfNeeded()
            }
        }
        scroll.magnification = min(32, max(0.001, scale))
        let center = centerImage ? NSPoint(x: document.frame.width / 2, y: document.frame.height / 2) : oldCenter
        scroll.contentView.scroll(to: NSPoint(x: center.x - scroll.contentView.bounds.width / 2, y: center.y - scroll.contentView.bounds.height / 2))
        scroll.reflectScrolledClipView(scroll.contentView)
        CATransaction.commit()
        applyingViewport = false
        if chromeVisible || titleUsesCanvas != (scale < geometry.minimumScale) { updateTitleContrast() }
        layoutChrome(); updateZoomLabel(); refreshChrome()
    }
    func resetEmptyWindow() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        applyingViewport = true
        window.contentAspectRatio = .zero
        window.contentMinSize = NSSize(width: 480, height: 320)
        window.contentMaxSize = screenArea.size
        let old = window.frame
        let size = NSSize(width: 640, height: 420)
        window.setFrame(NSRect(x: old.midX - size.width / 2, y: old.midY - size.height / 2, width: size.width, height: size.height), display: true)
        applyingViewport = false
    }
    func centerDocument() {
        guard let doc = scroll.documentView else { return }
        scroll.contentView.scroll(to: NSPoint(x: (doc.frame.width - scroll.contentView.bounds.width) / 2, y: (doc.frame.height - scroll.contentView.bounds.height) / 2))
        scroll.reflectScrolledClipView(scroll.contentView)
    }
    func layoutChrome() {
        let width = stage.bounds.width
        bottomFullChrome.isHidden = width < 470
        bottomCompactChrome.isHidden = width >= 470
        if let button = windowButtons.first, button.window != nil, window?.styleMask.contains(.fullScreen) != true {
            let center = stage.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), from: button)
            topChromeTop?.constant = max(0, stage.bounds.height - center.y - 22)
        }
        // Collapse complete groups, preserving a single centered filename row.
        for (group, threshold) in zip(toolGroups, [480.0, 580, 750, 810]) {
            group.isHidden = width < threshold
        }
        nameLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        for key in ["out", "in", "fit"] { buttons[key]?.isHidden = width < 470 }
        zoomLabel.isHidden = width < 470
        for key in ["play", "rotate", "fullscreen"] { buttons[key]?.isHidden = width < 620 }
        // The compact transport contains only the two navigation buttons.
        countLabel.isHidden = width < 470
        if width < 170 { topChrome.isHidden = true; bottomChrome.isHidden = true }
    }
    @objc func fit(_ sender: Any?) {
        guard let geometry = viewportGeometry else { return }
        fitting = true
        let value = geometry.maximumScale * (window?.styleMask.contains(.fullScreen) == true ? 1 : 0.82)
        zoomDriver.reset(value); applyZoom(value, centerImage: true)
    }
    @objc func actualSize(_ sender: Any?) {
        fitting = false
        let value = 1 / (window?.backingScaleFactor ?? 2)
        zoomDriver.reset(value); applyZoom(value, centerImage: true)
    }
    @objc func zoomIn(_ sender: Any?) { zoom(1.15) }
    @objc func zoomOut(_ sender: Any?) { zoom(1 / 1.15) }
    func zoom(_ multiplier: CGFloat) {
        guard asset != nil, !scroll.isHidden else { return }
        fitting = false
        zoomDriver.aim(zoomDriver.target * multiplier, in: stage)
    }
    @objc func fullscreen(_ sender: Any?) { zoomDriver.reset(scroll.magnification); window?.toggleFullScreen(sender) }
    func windowDidResize(_ notification: Notification) {
        layoutChrome()
        guard !applyingViewport, !transitioningFullScreen, let doc = scroll.documentView, asset != nil else { return }
        let scale = min(scroll.contentSize.width / max(1, doc.frame.width), scroll.contentSize.height / max(1, doc.frame.height))
        zoomDriver.reset(scale); scroll.magnification = scale; centerDocument(); updateZoomLabel(); refreshChrome()
    }
    func windowWillEnterFullScreen(_ notification: Notification) { transitioningFullScreen = true; zoomDriver.reset(scroll.magnification) }
    func windowWillExitFullScreen(_ notification: Notification) { transitioningFullScreen = true; zoomDriver.reset(scroll.magnification) }
    func windowDidEnterFullScreen(_ notification: Notification) { transitioningFullScreen = false; fit(nil) }
    func windowDidExitFullScreen(_ notification: Notification) { transitioningFullScreen = false; prepareImageWindow() }
    func windowDidChangeScreen(_ notification: Notification) {
        guard !applyingViewport, !transitioningFullScreen, asset != nil else { return }
        zoomDriver.reset(scroll.magnification); updateWindowLimits(); applyZoom(scroll.magnification)
    }
}
