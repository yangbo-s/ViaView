import AppKit
@_spi(Testing) import ViewerCore

func runLoadingChecks(_ check: (Bool, String) -> Void) {
    func clickClose(_ viewer: ViewerController) {
        let window = viewer.window!
        window.contentView!.superview!.layoutSubtreeIfNeeded()
        viewer.windowDidUpdate(Notification(name: NSWindow.didUpdateNotification, object: window))
        let button = window.standardWindowButton(.closeButton)!
        let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
        let down = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        // Exercise the exact local-monitor route before AppKit's native action.
        // No document avoids entering a drag-tracking loop if the event is swallowed.
        viewer.scroll.documentView = nil
        if viewer.routeViewerEvent(down) != nil { button.performClick(nil) }
    }
    for ext in ["png", "svg"] {
        let viewer = ViewerController()
        let image = NSImage(size: NSSize(width: 2000, height: 2000))
        viewer.asset = ImageAsset(url: URL(fileURLWithPath: "/tmp/close-check.\(ext)"), image: image, cgImage: nil, properties: [:])
        viewer.canvas.image = image
        viewer.canvas.frame = NSRect(origin: .zero, size: image.size)
        viewer.scroll.isHidden = false
        viewer.prepareImageWindow()
        viewer.showWindow(nil)
        viewer.setChrome(true)
        clickClose(viewer)
        check(viewer.window?.isVisible == false, "native close click closes a \(ext.uppercased()) viewer")
        viewer.window?.close()
    }
    let viewer = ViewerController()
    viewer.openURLs([URL(fileURLWithPath: "/tmp/viaview-loading-check.png")])
    viewer.showWindow(nil)
    check(viewer.window?.isVisible == false, "first opening waits for an image or error before exposing the window")
    viewer.window?.close()

    let switching = ViewerController()
    let previous = NSImage(size: NSSize(width: 800, height: 600))
    switching.canvas.image = previous
    switching.scroll.isHidden = false
    switching.gallery = Gallery(urls: [URL(fileURLWithPath: "/tmp/viaview-loading-check.png")])
    switching.loadCurrent()
    check(switching.canvas.image === previous && !switching.scroll.isHidden,
          "switching retains the previous rendered image until its replacement is ready")
    switching.window?.close()
}

@discardableResult func waitForCheck(timeout: TimeInterval = 5, _ condition: () -> Bool) -> Bool {
    let deadline = Date(timeIntervalSinceNow: timeout)
    while !condition(), Date() < deadline { RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.005)) }
    return condition()
}

func runAsyncLoadingChecks(_ check: (Bool, String) -> Void) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ViaView-loading-\(UUID().uuidString)")
    do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let first = folder.appendingPathComponent("01.png"), second = folder.appendingPathComponent("02.png")
        let broken = folder.appendingPathComponent("03.png"), svg = folder.appendingPathComponent("04.svg")
        let context = CGContext(data: nil, width: 64, height: 48, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(NSColor.cyan.cgColor); context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        try NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!.write(to: first)
        context.setFillColor(NSColor.red.cgColor); context.fill(CGRect(x: 0, y: 0, width: 64, height: 48))
        try NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!.write(to: second)
        try Data("broken".utf8).write(to: broken)
        try Data("<svg xmlns='http://www.w3.org/2000/svg' width='800' height='600'><rect width='800' height='600' fill='teal'/></svg>".utf8).write(to: svg)

        let scanGate = DispatchSemaphore(value: 0)
        let direct = ViewerController(imagePipeline: ImagePipeline(), scanFolder: { _, _, _ in
            _ = scanGate.wait(timeout: .now() + 10); return [first, second]
        })
        direct.openURLs([first]); direct.showWindow(nil)
        let readyBeforeScan = waitForCheck { direct.asset?.url == first && direct.window?.isVisible == true }
        check(readyBeforeScan && direct.gallery.urls == [first], "requested image is visible before directory enumeration completes")
        scanGate.signal()
        check(waitForCheck { direct.gallery.urls.count == 2 } && direct.gallery.current == first,
              "directory results add neighbors without reloading or changing the selected image")
        check(direct.inspector.stack.arrangedSubviews.count == 1, "hidden inspector does not build metadata or histogram during opening")
        direct.move(1)
        check(direct.displayedCG == nil && direct.canvas.image != nil && !direct.scroll.isHidden,
              "retained pixels cannot be edited or copied as the pending file")
        check(waitForCheck { direct.asset?.url == second }, "navigation commits the replacement image")
        direct.window?.close()

        let lateScanGate = DispatchSemaphore(value: 0)
        let race = ViewerController(scanFolder: { _, _, _ in
            _ = lateScanGate.wait(timeout: .now() + 10); return [first]
        })
        race.openURLs([first]); race.openURLs([second, svg]); race.showWindow(nil)
        check(waitForCheck { race.asset?.url == second }, "a newer open request wins over pending work")
        lateScanGate.signal()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        check(Set(race.gallery.urls) == Set([second, svg]) && race.gallery.current == second,
              "late directory results cannot overwrite an explicitly selected gallery")
        race.gallery = Gallery(urls: [broken]); race.loadCurrent()
        check(waitForCheck { !race.isLoading } && race.emptyTitle.stringValue == "这张图片无法打开" && !race.empty.isHidden && race.scroll.isHidden,
              "decode failure replaces retained pixels with a recoverable error")
        race.window?.close()

        let failure = ViewerController()
        failure.gallery = Gallery(urls: [broken]); failure.loadCurrent(); failure.showWindow(nil)
        check(waitForCheck { failure.window?.isVisible == true && !failure.isLoading } && !failure.empty.isHidden,
              "a first-image error reveals the deferred window instead of leaving it invisible")
        failure.window?.close()

        let queue = OperationQueue(); queue.isSuspended = true
        let closed = ViewerController(imagePipeline: ImagePipeline(queue: queue))
        closed.gallery = Gallery(urls: [first]); closed.loadCurrent(); closed.showWindow(nil); closed.close()
        queue.isSuspended = false
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.1))
        check(!closed.showWhenReady && closed.window?.isVisible == false && closed.asset == nil,
              "closing before decode completes cannot reopen a deferred window")

        let vector = ViewerController()
        vector.gallery = Gallery(urls: [first, svg]); vector.loadCurrent(); vector.showWindow(nil)
        _ = waitForCheck { vector.asset != nil }
        let oldImage = vector.canvas.image
        vector.move(1)
        check(vector.canvas.image === oldImage && !vector.scroll.isHidden, "raster remains visible while WebKit initializes SVG")
        let svgReady = waitForCheck(timeout: 15) { vector.asset?.isSVG == true && vector.pendingSVG == nil }
        check(svgReady && vector.web === vector.scroll.documentView && !vector.scroll.isHidden && vector.empty.isHidden,
              "SVG commits only after navigation finishes in the offline renderer")
        if svgReady {
            vector.setChrome(true)
            for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
                let button = vector.window!.standardWindowButton(kind)!
                let point = button.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), to: nil)
                let event = NSEvent.mouseEvent(with: .leftMouseDown, location: point, modifierFlags: [], timestamp: 0, windowNumber: vector.window!.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
                check(vector.routeViewerEvent(event) === event, "SVG passes native window control \(kind.rawValue) through unchanged")
            }
        }
        let oldWeb = vector.web
        vector.move(-1)
        check(vector.scroll.documentView === oldWeb && !vector.scroll.isHidden, "SVG stays on screen while a raster replacement decodes")
        check(waitForCheck { vector.asset?.url == first } && vector.scroll.documentView === vector.canvas && vector.web == nil,
              "SVG-to-raster swap disposes the old renderer")
        if let oldWeb { vector.webView(oldWeb, didFinish: nil) }
        check(vector.asset?.url == first, "stale WebKit completion cannot replace the current raster")
        vector.move(1)
        _ = waitForCheck { vector.pendingSVG != nil || vector.asset?.isSVG == true }
        let pending = vector.pendingSVG?.browser ?? vector.web
        vector.close()
        if let pending { vector.webView(pending, didFinish: nil) }
        check(vector.pendingSVG == nil && vector.window?.isVisible == false && !vector.showWhenReady,
              "closing during SVG rendering invalidates its pending completion")

        let unreadable = folder.appendingPathComponent("removed.svg")
        let failedSVG = ViewerController()
        failedSVG.gallery = Gallery(urls: [unreadable]); failedSVG.isLoading = true; failedSVG.showWindow(nil)
        failedSVG.showSVG(ImageAsset(url: unreadable, image: NSImage(size: NSSize(width: 800, height: 600)), cgImage: nil, properties: [:]), serial: failedSVG.loadSerial)
        check(!failedSVG.isLoading && failedSVG.window?.isVisible == true && failedSVG.emptyTitle.stringValue == "SVG 无法读取" && failedSVG.nameLabel.stringValue == "removed.svg",
              "SVG removed after size decoding presents an error and clears the loading title")
        failedSVG.close()
    } catch { check(false, "loading fixtures: \(error.localizedDescription)") }
}
