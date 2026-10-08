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
        root.layoutSubtreeIfNeeded()
        let clip = scroll.contentView
        let visible = document.convert(clip.bounds, from: clip)
        let oldCenter = NSPoint(x: visible.midX, y: visible.midY)
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
        scroll.tile()
        root.layoutSubtreeIfNeeded()
        var center = centerImage ? NSPoint(x: document.bounds.midX, y: document.bounds.midY) : oldCenter
        // A complete image always recenters, including fractional point sizes.
        let tolerance = 1 / scroll.magnification
        if document.bounds.width <= clip.bounds.width + tolerance { center.x = document.bounds.midX }
        if document.bounds.height <= clip.bounds.height + tolerance { center.y = document.bounds.midY }
        centerViewport(on: center)
        CATransaction.commit()
        applyingViewport = false
        if chromeVisible || titleUsesCanvas != (scale < geometry.minimumScale) { updateTitleContrast() }
        layoutChrome(); updateZoomLabel(); refreshChrome()
    }
    func resetEmptyWindow() {
        guard let window, !window.styleMask.contains(.fullScreen) else { return }
        applyingViewport = true
        window.contentResizeIncrements = NSSize(width: 1, height: 1)
        window.contentMinSize = NSSize(width: 480, height: 320)
        window.contentMaxSize = screenArea.size
        let old = window.frame
        let size = NSSize(width: 640, height: 420)
        window.setFrame(NSRect(x: old.midX - size.width / 2, y: old.midY - size.height / 2, width: size.width, height: size.height), display: true)
        applyingViewport = false
    }
    func centerDocument() {
        guard let doc = scroll.documentView else { return }
        centerViewport(on: NSPoint(x: doc.bounds.midX, y: doc.bounds.midY))
    }
    func centerViewport(on documentPoint: NSPoint) {
        guard let document = scroll.documentView else { return }
        let clip = scroll.contentView
        let point = clip.convert(documentPoint, from: document)
        var bounds = clip.bounds
        bounds.origin = NSPoint(x: point.x - bounds.width / 2, y: point.y - bounds.height / 2)
        clip.scroll(to: clip.constrainBoundsRect(bounds).origin)
        scroll.reflectScrolledClipView(clip)
    }
    func layoutChrome() {
        let width = stage.bounds.width
        bottomFullChrome.isHidden = width < 470
        bottomCompactChrome.isHidden = width >= 470
        alignTopChromeWithWindowControls()
        // Collapse complete groups, preserving a single centered filename row.
        for (group, threshold) in zip(toolGroups, [480.0, 580, 750, 810]) {
            group.isHidden = asset == nil || width < threshold
        }
        compactTools?.isHidden = asset == nil || width < 400 || width >= 480
        nameLabel.font = .systemFont(ofSize: 14, weight: .semibold)
        for key in ["out", "in", "fit"] { buttons[key]?.isHidden = width < 470 }
        zoomLabel.isHidden = width < 470
        for key in ["play", "rotate", "fullscreen"] { buttons[key]?.isHidden = width < 620 }
        // The compact transport contains only the two navigation buttons.
        countLabel.isHidden = width < 470
        if width < 170 { topChrome.isHidden = true; bottomChrome.isHidden = true }
    }
    func alignTopChromeWithWindowControls() {
        var inset: CGFloat = 8
        if window?.styleMask.contains(.fullScreen) != true,
           let button = windowButtons.first, button.window != nil, stage.bounds.height > 0 {
            let center = stage.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), from: button)
            inset = max(0, stage.bounds.height - center.y - 22)
        }
        if let constraint = topChromeTop, abs(constraint.constant - inset) > 0.01 {
            constraint.constant = inset
        }
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
    @objc func fullscreen(_ sender: Any?) {
        guard !transitioningFullScreen else { return }
        zoomDriver.reset(scroll.magnification)
        window?.toggleFullScreen(sender)
    }
    func handleFullScreenExit(_ event: NSEvent) -> Bool {
        guard let window, window.styleMask.contains(.fullScreen), window.attachedSheet == nil,
              !(window.firstResponder is NSTextView),
              isFullScreenExitKey(event) else { return false }
        if !event.isARepeat, !transitioningFullScreen { fullscreen(nil) }
        return true
    }
    func windowDidResize(_ notification: Notification) {
        layoutChrome()
        guard !applyingViewport, !transitioningFullScreen, let doc = scroll.documentView, asset != nil else { return }
        let scale = min(scroll.contentSize.width / max(1, doc.frame.width), scroll.contentSize.height / max(1, doc.frame.height))
        zoomDriver.reset(scale); scroll.magnification = scale; centerDocument(); updateZoomLabel(); refreshChrome()
    }
    func windowWillEnterFullScreen(_ notification: Notification) {
        transitioningFullScreen = true
        zoomDriver.reset(scroll.magnification)
        // Resize increments clear an existing aspect constraint without leaving a zero ratio
        // for AppKit to apply while restoring the window after full screen.
        window?.contentResizeIncrements = NSSize(width: 1, height: 1)
        window?.contentMaxSize = NSSize(width: 100_000, height: 100_000)
        window?.toolbar?.isVisible = false
        refreshAppearance(fullScreen: true)
    }
    func windowWillExitFullScreen(_ notification: Notification) {
        transitioningFullScreen = true
        zoomDriver.reset(scroll.magnification)
    }
    func windowDidEnterFullScreen(_ notification: Notification) {
        refreshAppearance()
        root.layoutSubtreeIfNeeded(); scroll.tile()
        transitioningFullScreen = false
        fit(nil)
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        restoreWindowedViewport()
    }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        restoreWindowedViewport()
    }
    func windowDidFailToExitFullScreen(_ window: NSWindow) {
        transitioningFullScreen = false
        fit(nil)
    }
    private func restoreWindowedViewport() {
        refreshAppearance()
        window?.toolbar?.isVisible = true
        root.layoutSubtreeIfNeeded(); scroll.tile()
        transitioningFullScreen = false
        if asset == nil { resetEmptyWindow() }
        else { prepareImageWindow() }
    }
    func windowDidChangeScreen(_ notification: Notification) {
        guard !applyingViewport, !transitioningFullScreen, asset != nil else { return }
        zoomDriver.reset(scroll.magnification); updateWindowLimits(); applyZoom(scroll.magnification)
    }
}

func isFullScreenExitKey(_ event: NSEvent) -> Bool {
    event.type == .keyDown && [53, 51, 117].contains(event.keyCode)
        && event.modifierFlags.intersection([.command, .control, .option, .shift]).isEmpty
}
