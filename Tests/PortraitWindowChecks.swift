import AppKit
import ViewerCore

@MainActor func runPortraitWindowChecks(_ check: (Bool, String) -> Void, source: URL? = nil) {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent("ViaView-portrait-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: directory) }
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let image = NSImage(size: NSSize(width: 1638, height: 2048), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            ("PORTRAIT VIEW 2026" as NSString).draw(at: NSPoint(x: 100, y: 1000), withAttributes: [.font: NSFont.systemFont(ofSize: 100), .foregroundColor: NSColor.black])
            return true
        }
        let pixels = image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let data = NSBitmapImageRep(cgImage: pixels).representation(using: .png, properties: [:])!
        for name in ["portrait.png", "123456789_1234567890123456_1234567890123456789_n.png"] {
            let url = directory.appendingPathComponent(name)
            if let source { try FileManager.default.copyItem(at: source, to: url) }
            else { try data.write(to: url) }
            let viewer = ViewerController(imagePipeline: ImagePipeline(), scanFolder: { _, _, _ in [url] })
            defer { viewer.close() }
            viewer.openURLs([url]); viewer.showWindow(nil)
            check(waitForCheck { !viewer.isLoading && viewer.asset != nil && viewer.window?.isVisible == true }, "portrait opens through the real loading path (\(name))")
            let window = viewer.window!, area = viewer.screenArea
            window.setFrameOrigin(NSPoint(x: area.midX - window.frame.width / 2, y: area.midY - window.frame.height / 2))
            let initialCenter = window.frame.midX
            viewer.zoomDriver.shouldReduceMotion = { true }
            var times = [Double](), maximumDrift: CGFloat = 0
            let apply = viewer.zoomDriver.apply
            viewer.zoomDriver.apply = { scale in
                let start = CACurrentMediaTime(); apply?(scale)
                times.append((CACurrentMediaTime() - start) * 1000)
            }
            for _ in 0..<100 {
                viewer.zoom(exp(-0.1))
                RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.002))
                while let event = NSApp.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) { NSApp.sendEvent(event) }
                NSApp.updateWindows()
                maximumDrift = max(maximumDrift, abs(window.frame.midX - initialCenter))
            }
            let canvas = viewer.canvas.convert(viewer.canvas.bounds, to: viewer.stage)
            let bars = viewer.stage.bounds.width - canvas.width
            check(maximumDrift < 1, "loaded portrait keeps its window center (\(name), drift=\(maximumDrift) pt)")
            check(abs(bars) < 2, "loaded portrait minimum has no expanding side bars (\(name), bars=\(bars) pt)")
            check(abs(viewer.scroll.magnification - viewer.minimumZoomScale) < 1e-10,
                  "loaded portrait reaches its actual minimum (\(name))")
            viewer.zoomDriver.apply = apply
            let ordered = times.sorted()
            print("PERF portrait \(name): calls=\(times.count), max=\(times.max() ?? 0) ms, p95=\(ordered.isEmpty ? 0 : ordered[min(ordered.count - 1, Int(Double(ordered.count) * 0.95))]) ms")
            if name != "portrait.png" {
                // Exercise the actual navigation/loading path, not just a new canvas size.
                let landscapeURL = directory.appendingPathComponent("landscape.png")
                let landscape = NSImage(size: NSSize(width: 1200, height: 800), flipped: false) { rect in
                    NSColor.gray.setFill(); rect.fill(); return true
                }
                let cg = landscape.cgImage(forProposedRect: nil, context: nil, hints: nil)!
                try NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: landscapeURL)
                viewer.openURLs([landscapeURL, url])
                check(waitForCheck { viewer.asset?.url == landscapeURL }, "landscape loads before navigating to portrait")
                viewer.gallery.select(viewer.gallery.urls.firstIndex(of: url)!)
                viewer.loadCurrent()
                check(waitForCheck { viewer.asset?.url == url }, "navigation restores the long-name portrait")
                let event = ZoomInputEvent(); event.precise = true
                for pinch in [false, true] {
                    viewer.actualSize(nil)
                    window.setFrameOrigin(NSPoint(x: area.midX - window.frame.width / 2, y: area.midY - window.frame.height / 2))
                    let center = window.frame.midX
                    viewer.zoomDriver.shouldReduceMotion = { false }
                    var drift: CGFloat = 0, sideGap: CGFloat = 0
                    let start = CACurrentMediaTime()
                    var firstResponse: Double?, frameCosts = [Double]()
                    viewer.zoomDriver.apply = { scale in
                        let frameStart = CACurrentMediaTime(); apply?(scale)
                        frameCosts.append((CACurrentMediaTime() - frameStart) * 1000)
                        if firstResponse == nil { firstResponse = (CACurrentMediaTime() - start) * 1000 }
                    }
                    for _ in 0..<120 {
                        event.amount = pinch ? -0.1 : -32
                        if pinch { viewer.scroll.magnify(with: event) }
                        else { viewer.scroll.scrollWheel(with: event) }
                        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.008))
                        while let event = NSApp.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) { NSApp.sendEvent(event) }
                        NSApp.updateWindows()
                        drift = max(drift, abs(window.frame.midX - center))
                        sideGap = max(sideGap, viewer.stage.bounds.width - viewer.canvas.convert(viewer.canvas.bounds, to: viewer.stage).width)
                    }
                    let settled = waitForCheck { abs(viewer.scroll.magnification - viewer.minimumZoomScale) < 1e-10 }
                    check(settled && drift < 1 && sideGap < 2,
                          "navigated portrait animated \(pinch ? "pinch" : "wheel") stays filled and centered (drift=\(drift), gap=\(sideGap) pt)")
                    print("PERF animated \(pinch ? "pinch" : "wheel"): first response=\(firstResponse ?? -1) ms, max apply=\(frameCosts.max() ?? 0) ms")
                    let frame = window.frame
                    var extraFrames = 0
                    viewer.zoomDriver.apply = { extraFrames += 1; apply?($0) }
                    for _ in 0..<200 {
                        if pinch { viewer.scroll.magnify(with: event) }
                        else { viewer.scroll.scrollWheel(with: event) }
                    }
                    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
                    check(extraFrames == 0 && window.frame == frame,
                          "long-name portrait ignores further \(pinch ? "pinches" : "wheel events") at minimum")
                    viewer.zoomDriver.apply = apply
                }
            }
        }
    } catch { check(false, "portrait fixture failed: \(error)") }
}
