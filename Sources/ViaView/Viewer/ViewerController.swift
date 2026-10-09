import AppKit
@preconcurrency import WebKit
import ViewerCore

final class ViewerController: NSWindowController, NSWindowDelegate, NSMenuItemValidation, WKNavigationDelegate {
    var onClose: (() -> Void)?
    var gallery = Gallery()
    var asset: ImageAsset?
    var displayedCG: CGImage?
    var edits = ImageEdits()
    var loadSerial = 0
    let imagePipeline: ImagePipeline
    let scanFolder: (URL, GallerySort, Bool) throws -> [URL]
    var isLoading = false
    var showWhenReady = false
    var pendingSVG: (browser: WKWebView, asset: ImageAsset)?
    var editSerial = 0
    var fitting = true
    var sort: GallerySort = .name
    var descending = false
    var galleryRevision = 0
    var sortRevision = 0
    var timer: Timer?
    var samplingColor = false
    var feedbackGeneration = 0
    let root = NSView()
    let stage = WorkspaceView(frame: .zero)
    let scroll = ImageScrollView()
    let canvas = ImageCanvas(frame: .zero)
    let fileList = FileListController()
    let tagsController = TagsPanelController()
    var tagsPanel: NSPanel?
    let inspector = InspectorContentView(frame: NSRect(x: 0, y: 0, width: 320, height: 440))
    let glassLayer = GlassLayer(frame: .zero)
    let topChrome = ChromeRow()
    let bottomChrome = ChromeRow()
    let bottomFullChrome = GlassChrome()
    let bottomCompactChrome = NSStackView()
    let nameLabel = label("ViaView", size: 13, weight: .medium)
    var imageSummary = ""
    let countLabel = label("", size: 12, weight: .medium)
    let zoomLabel = label("适应", size: 11, color: .secondaryLabelColor)
    let empty = NSStackView()
    let emptyTitle = label("打开一张图片", size: 24, weight: .semibold)
    let emptyDetail = label("也可以将图片或文件夹拖到这里", size: 13, color: .secondaryLabelColor)
    let progress = NSProgressIndicator()
    let colorFeedback = label("", size: 12, weight: .medium)
    var web: WKWebView?
    var eventMonitor: Any?
    var chromeGeneration = 0
    var chromeVisible = true
    var inspectorMode = InspectorMode.information
    var buttons: [String: NSButton] = [:]
    let editQueue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 1; q.qualityOfService = .userInitiated; return q }()
    var editOperation: BlockOperation?
    var loadOperation: Operation?
    var editPending = false
    var sliderLabels: [String: NSTextField] = [:]
    var exportPanel: NSSavePanel?
    var exportInProgress = false
    var trashInProgress = false
    var recycledURLs = Set<URL>()
    let zoomDriver = ZoomDriver()
    var applyingViewport = false
    var transitioningFullScreen = false
    var usesFullScreenAppearance = false
    var fileListPanel: NSPanel?
    var inspectorPanel: NSPanel?
    var topActions: [NSButton] = []
    var needsFolderAccess = false
    var toolGroups: [GlassChrome] = []
    var titleUsesCanvas = false
    var topChromeTop: NSLayoutConstraint?
    var windowButtons: [NSButton] {
        [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].compactMap { window?.standardWindowButton($0) }
    }
    var compactTools: GlassChrome?
    let moreButton = toolbarButton(.more, "更多操作", target: nil, action: #selector(showMore(_:)), size: 32)

    init(imagePipeline: ImagePipeline = .shared,
         scanFolder: @escaping (URL, GallerySort, Bool) throws -> [URL] = { try Gallery.scan($0, sort: $1, descending: $2) }) {
        self.imagePipeline = imagePipeline; self.scanFolder = scanFolder
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 420), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = "ViaView"; window.titleVisibility = .hidden; window.titlebarAppearsTransparent = true
        let nativeToolbar = NSToolbar(identifier: "ViaViewWindowControls")
        nativeToolbar.displayMode = .iconOnly
        window.toolbar = nativeToolbar; window.toolbarStyle = .unified
        window.titlebarSeparatorStyle = .none
        window.minSize = NSSize(width: 160, height: 100); window.center(); window.isReleasedWhenClosed = false
        window.acceptsMouseMovedEvents = true; window.tabbingMode = .disallowed
        window.autorecalculatesKeyViewLoop = true
        super.init(window: window); window.delegate = self; window.contentView = root
        buildLayout()
        stage.onAppearanceChange = { [weak self] in self?.updateCanvasAppearance() }
        refreshAppearance()
        canvas.onNavigate = { [weak self] in self?.move($0) }
        canvas.onDoubleClick = { [weak self] in guard let self else { return }; self.fitting ? self.actualSize(nil) : self.fit(nil) }
        stage.onDrop = { [weak self] in self?.openURLs($0) }
        stage.onPointer = { [weak self] in self?.pointer($0) }
        scroll.onZoom = { [weak self] in self?.zoom($0) }
        zoomDriver.apply = { [weak self] in self?.applyZoom($0) }
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .mouseMoved, .leftMouseDown, .rightMouseDown, .scrollWheel, .magnify]) { [weak self] event in
            guard let self else { return event }; return self.routeViewerEvent(event)
        }
        updateUI()
    }
    required init?(coder: NSCoder) { fatalError() }
    deinit { if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }; timer?.invalidate(); zoomDriver.stop() }

    override func showWindow(_ sender: Any?) {
        if isLoading, window?.isVisible != true { showWhenReady = true; return }
        super.showWindow(sender)
    }

    func finishWindowPresentation() {
        isLoading = false
        if showWhenReady {
            showWhenReady = false
            window?.contentView?.layoutSubtreeIfNeeded()
            window?.displayIfNeeded()
            super.showWindow(nil)
        }
    }

    func routeViewerEvent(_ event: NSEvent) -> NSEvent? {
        if event.window === self.window {
            // Full-size content extends underneath the native titlebar buttons.
            // They are outside glassLayer, so its hit test alone cannot protect them.
            if windowButtons.contains(where: { !$0.isHiddenOrHasHiddenAncestor && $0.bounds.contains($0.convert(event.locationInWindow, from: nil)) }) {
                return event
            }
            if event.type == .keyDown {
                if self.handleFullScreenExit(event) { return nil }
                return event
            }
            let point = self.stage.convert(event.locationInWindow, from: nil)
            let contextClick = event.type == .rightMouseDown || (event.type == .leftMouseDown && event.modifierFlags.contains(.control))
            if contextClick, self.gallery.current != nil, self.stage.bounds.contains(point), self.glassLayer.hitTest(point) == nil {
                self.showImageContextMenu(with: event); return nil
            } else if event.type == .scrollWheel || event.type == .magnify {
                if self.asset?.isSVG == true, self.stage.bounds.contains(point) {
                    if event.type == .magnify { self.scroll.magnify(with: event) }
                    else { self.scroll.scrollWheel(with: event) }
                    return nil
                }
            } else if event.type == .leftMouseDown, self.asset?.isSVG == true,
                      self.stage.bounds.contains(point), self.glassLayer.hitTest(point) == nil {
                dragImageDocument(in: self.scroll, with: event); return nil
            } else { self.pointer(point) }
        }
        return event
    }

    @objc func toggleAnimation(_ sender: Any?) { canvas.animates.toggle() }
    @objc func alwaysOnTop(_ sender: Any?) { window?.level = window?.level == .floating ? .normal : .floating; updateTopActions() }
    func windowDidUpdate(_ notification: Notification) {
        // Native titlebar controls finish laying out after key/resize callbacks.
        // Align against their final position, including first display and toolbar restoration.
        layoutChrome()
        if chromeVisible {
            let available = stage.bounds.width >= 170 && stage.bounds.height >= 100
            topChrome.isHidden = !available
            bottomChrome.isHidden = asset == nil || !available || stage.bounds.height < 180
            windowButtons.forEach { $0.isHidden = !available }
        }
    }
    func windowDidBecomeKey(_ notification: Notification) {
        windowButtons.forEach { $0.needsDisplay = true }
        layoutChrome(); refreshChrome()
    }
    func windowDidBecomeMain(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        (NSApp.delegate as? AppDelegate)?.lastActiveViewer = self
    }
    func windowWillClose(_ notification: Notification) {
        guard notification.object as? NSWindow === window else { return }
        zoomDriver.stop(); fileListPanel?.close(); inspectorPanel?.close(); tagsPanel?.close()
        timer?.invalidate(); loadSerial += 1; galleryRevision += 1
        showWhenReady = false; isLoading = false
        loadOperation?.cancel(); editOperation?.cancel()
        pendingSVG?.browser.navigationDelegate = nil; pendingSVG?.browser.stopLoading(); pendingSVG = nil
        web?.navigationDelegate = nil; web?.stopLoading(); onClose?()
    }
    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if isLoading {
            let allowed = [#selector(previous(_:)), #selector(next(_:)), #selector(fullscreen(_:)), #selector(toggleFileList(_:)), #selector(alwaysOnTop(_:))]
            return menuItem.action.map { allowed.contains($0) } == true && (menuItem.action != #selector(previous(_:)) && menuItem.action != #selector(next(_:)) || gallery.urls.count > 1)
        }
        if menuItem.action == #selector(pickColor(_:)) { return gallery.current != nil && !samplingColor }
        if menuItem.action == #selector(openEditor(_:)) {
            menuItem.title = "用\(AppSettings.editorName)打开"
            return gallery.current != nil && AppSettings.editorURL != nil
        }
        if menuItem.action == #selector(moveToTrash(_:)) { return gallery.current != nil && !trashInProgress && !exportInProgress }
        if [#selector(previous(_:)), #selector(next(_:)), #selector(slideshow(_:))].contains(menuItem.action) { return gallery.urls.count > 1 }
        if menuItem.action == #selector(exportImage(_:)) { return asset?.cgImage != nil && !exportInProgress }
        if menuItem.action == #selector(toggleAnimation(_:)) { return asset?.canAnimate == true && edits.isIdentity }
        if editPending, let action = menuItem.action, [#selector(copyImage(_:)), #selector(printImage(_:)), #selector(recognizeText(_:))].contains(action) { return false }
        if menuItem.action == #selector(alwaysOnTop(_:)) { menuItem.state = window?.level == .floating ? .on : .off }
        let independent: [Selector] = [#selector(fullscreen(_:)), #selector(toggleFileList(_:)), #selector(toggleInfo(_:)), #selector(toggleAdjustments(_:)), #selector(alwaysOnTop(_:))]
        if let action = menuItem.action, independent.contains(action) { return true }
        let raster: [Selector] = [#selector(rotateLeft(_:)), #selector(rotateRight(_:)), #selector(flip(_:)), #selector(resetEdits(_:)), #selector(copyImage(_:)), #selector(exportImage(_:)), #selector(printImage(_:)), #selector(recognizeText(_:))]
        if let action = menuItem.action, raster.contains(action) { return displayedCG != nil }
        return gallery.current != nil
    }
    func showError(_ error: Error) { let alert = NSAlert(error: error); if let window { alert.beginSheetModal(for: window) } }
}
