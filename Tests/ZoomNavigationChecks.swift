import AppKit
@_spi(Testing) import ViewerCore

@MainActor func runZoomNavigationChecks(_ check: (Bool, String) -> Void) {
    let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ViaView-zoom-navigation-\(UUID().uuidString)")
    do {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let urls = ["01.png", "02.png", "03-portrait.png", "04-small.png", "05.svg", "06-broken.png"]
            .map { folder.appendingPathComponent($0) }
        for (index, size) in [CGSize(width: 960, height: 640), CGSize(width: 960, height: 640),
                              CGSize(width: 640, height: 960), CGSize(width: 80, height: 60)].enumerated() {
            let context = CGContext(data: nil, width: Int(size.width), height: Int(size.height), bitsPerComponent: 8, bytesPerRow: 0,
                                    space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor((index == 0 ? NSColor.cyan : .red).cgColor)
            context.fill(CGRect(origin: .zero, size: size))
            let url = urls[index]
            try NSBitmapImageRep(cgImage: context.makeImage()!).representation(using: .png, properties: [:])!.write(to: url)
        }
        try Data("<svg xmlns='http://www.w3.org/2000/svg' width='960' height='640'><rect width='960' height='640' fill='teal'/></svg>".utf8).write(to: urls[4])
        try Data("broken".utf8).write(to: urls[5])
        let queue = OperationQueue()
        let pipeline = ImagePipeline(queue: queue)
        let viewer = ViewerController(imagePipeline: pipeline, scanFolder: { _, _, _ in urls })
        defer { viewer.close() }
        func ready(_ index: Int) -> Bool {
            let loaded = waitForCheck(timeout: index == 4 ? 15 : 5) {
                viewer.asset?.url == urls[index] && !viewer.isLoading && viewer.pendingSVG == nil
            }
            check(loaded, "zoom navigation loads \(urls[index].lastPathComponent)")
            return loaded
        }
        func select(_ index: Int) -> Bool {
            viewer.fileList.onSelect?(urls[index])
            return ready(index)
        }
        func checkScale(_ scale: CGFloat, _ name: String) {
            check(abs(viewer.scroll.magnification - scale) < 1e-9 && abs(viewer.zoomDriver.target - scale) < 1e-9,
                  "\(name) (expected=\(scale), actual=\(viewer.scroll.magnification), target=\(viewer.zoomDriver.target))")
        }
        viewer.gallery = Gallery(urls: urls)
        viewer.loadCurrent(); viewer.showWindow(nil)
        guard ready(0) else { return }
        let initialScale = viewer.scroll.magnification
        check(viewer.fitting, "first image starts in automatic sizing mode")
        viewer.zoomDriver.shouldReduceMotion = { true }
        let event = ZoomInputEvent(); event.amount = 1
        viewer.scroll.scrollWheel(with: event)
        let scale = viewer.scroll.magnification
        let size = viewer.window!.frame.size
        check(scale > initialScale, "one wheel step slightly enlarges the first image")
        viewer.next(nil)
        guard ready(1) else { return }
        checkScale(scale, "next image retains wheel zoom")
        check(abs(viewer.window!.frame.width - size.width) < 1 && abs(viewer.window!.frame.height - size.height) < 1,
              "same-size navigation retains the enlarged window dimensions")
        viewer.previous(nil)
        guard ready(0) else { return }
        checkScale(scale, "previous image retains wheel zoom")

        event.amount = 0.1
        viewer.scroll.magnify(with: event)
        let pinchedScale = viewer.scroll.magnification
        guard select(2) else { return }
        checkScale(pinchedScale, "file-list navigation to a portrait retains pinch zoom")
        check(!viewer.fitting && viewer.window!.contentAspectRatio == viewer.canvas.frame.size,
              "manual sizing survives while window constraints adopt the next image's aspect ratio")
        let canvasFrame = viewer.canvas.convert(viewer.canvas.bounds, to: viewer.stage)
        check(abs(canvasFrame.midX - viewer.stage.bounds.midX) < 1 && abs(canvasFrame.midY - viewer.stage.bounds.midY) < 1,
              "the replacement image is centered at the retained scale")
        viewer.zoomIn(nil)
        let keyboardScale = viewer.scroll.magnification
        guard select(1) else { return }
        checkScale(keyboardScale, "file-list navigation retains keyboard zoom")

        // Freeze decoding so rapid navigation deterministically cancels pending
        // requests, including when the zoom display link has not ticked yet.
        viewer.zoomDriver.shouldReduceMotion = { false }
        viewer.zoomIn(nil)
        let requestedScale = viewer.zoomDriver.target, displayedScale = viewer.scroll.magnification
        check(requestedScale > displayedScale, "rapid-navigation fixture starts during a pending zoom animation")
        queue.isSuspended = true; pipeline.clear()
        viewer.next(nil); viewer.previous(nil); viewer.previous(nil)
        check(viewer.isLoading && viewer.asset == nil && abs(viewer.scroll.magnification - displayedScale) < 1e-9,
              "pending replacements keep the already displayed scale")
        queue.isSuspended = false
        guard ready(0) else { return }
        checkScale(requestedScale, "rapid navigation retains the last requested zoom target")

        viewer.zoomDriver.shouldReduceMotion = { true }
        viewer.zoom(0.001)
        let minimum = viewer.scroll.magnification
        guard select(3) else { return }
        checkScale(max(minimum, viewer.minimumZoomScale), "a small replacement clamps to its reachable minimum")
        viewer.zoom(1.3)
        let vectorScale = viewer.scroll.magnification
        guard select(4) else { return }
        checkScale(vectorScale, "raster-to-SVG navigation retains manual zoom")
        guard select(1) else { return }
        checkScale(vectorScale, "SVG-to-raster navigation retains manual zoom")
        viewer.fileList.onSelect?(urls[5])
        check(waitForCheck { !viewer.isLoading } && viewer.asset == nil && viewer.scroll.isHidden,
              "a broken replacement still presents the existing recoverable error")
        guard select(0) else { return }
        checkScale(vectorScale, "navigation after a decode failure retains manual zoom")

        viewer.fit(nil)
        check(viewer.fitting && viewer.scroll.magnification >= viewer.minimumZoomScale,
              "fit explicitly restores automatic sizing")
        guard select(1) else { return }
        checkScale(initialScale, "automatic sizing retains the original initial-size policy on navigation")
        viewer.actualSize(nil)
        let actualScale = 1 / viewer.window!.backingScaleFactor
        checkScale(actualScale, "actual-size command still selects one image pixel per screen pixel")
        guard select(2) else { return }
        checkScale(actualScale, "actual size carries to the next image")
        viewer.zoom(1e6)
        guard select(0) else { return }
        checkScale(32, "navigation preserves the supported maximum zoom")

        viewer.openURLs([urls[1], urls[0]])
        guard ready(1) else { return }
        checkScale(initialScale, "explicitly opening new content restores default sizing")
        check(viewer.fitting, "explicit open clears manual sizing mode")
        viewer.zoom(1.2)
        let beforeEmptyOpen = viewer.scroll.magnification
        viewer.openURLs([])
        checkScale(beforeEmptyOpen, "an empty open request leaves the current zoom unchanged")

        let independent = ViewerController(imagePipeline: ImagePipeline())
        defer { independent.close() }
        independent.gallery = Gallery(urls: [urls[0]])
        independent.loadCurrent(); independent.showWindow(nil)
        check(waitForCheck { independent.asset?.url == urls[0] }
              && abs(independent.scroll.magnification - initialScale) < 1e-9 && independent.fitting,
              "another window starts at default size independently of the existing window")
    } catch { check(false, "zoom navigation fixtures: \(error.localizedDescription)") }
}
