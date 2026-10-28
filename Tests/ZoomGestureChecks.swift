import AppKit
import ViewerCore

final class ZoomInputEvent: NSEvent {
    var amount: CGFloat = 0
    var precise = false
    override var scrollingDeltaX: CGFloat { 0 }
    override var scrollingDeltaY: CGFloat { amount }
    override var hasPreciseScrollingDeltas: Bool { precise }
    override var modifierFlags: NSEvent.ModifierFlags { [] }
    override var magnification: CGFloat { amount }
}

@MainActor func runZoomGestureChecks(_ check: (Bool, String) -> Void) {
    let viewer = ViewerController()
    defer { viewer.close() }
    let size = NSSize(width: 960, height: 640), image = NSImage(size: NSSize(width: 960, height: 640))
    viewer.asset = ImageAsset(url: URL(fileURLWithPath: "/tmp/zoom-gesture.png"), image: image, cgImage: nil, properties: [:])
    viewer.canvas.image = image; viewer.canvas.frame = NSRect(origin: .zero, size: size)
    viewer.scroll.isHidden = false
    viewer.root.layoutSubtreeIfNeeded(); viewer.prepareImageWindow()
    viewer.zoomDriver.shouldReduceMotion = { true }
    let event = ZoomInputEvent()
    for pinch in [false, true] {
        for reducedMotion in [true, false] {
            viewer.actualSize(nil)
            let window = viewer.window!, area = viewer.screenArea
            let x = reducedMotion ? area.minX + 30 : area.maxX - window.frame.width - 30
            window.setFrameOrigin(NSPoint(x: x, y: area.minY + 30))
            viewer.showWindow(nil)
            viewer.zoomDriver.shouldReduceMotion = { reducedMotion }
            let original = window.frame
            var imageOffset: CGFloat = 0, settled = true
            for direction: CGFloat in [1, -1] {
                for _ in 0..<30 {
                    event.amount = pinch ? direction * 0.065 : direction
                    if pinch { viewer.scroll.magnify(with: event) }
                    else { viewer.scroll.scrollWheel(with: event) }
                }
                settled = waitForCheck(timeout: 3) {
                    let frame = viewer.canvas.convert(viewer.canvas.bounds, to: viewer.stage)
                    imageOffset = max(imageOffset, abs(frame.midX - viewer.stage.bounds.midX))
                    return abs(viewer.scroll.magnification - viewer.zoomDriver.target) < 0.0001
                } && settled
            }
            let dx = window.frame.midX - original.midX, dy = window.frame.midY - original.midY
            let name = "\(pinch ? "pinch" : "wheel") / \(reducedMotion ? "immediate" : "animated")"
            check(settled && abs(dx) < 1 && abs(dy) < 1,
                  "\(name) zoom restores moved window center (drift=\(dx),\(dy) pt)")
            check(imageOffset < 1, "\(name) zoom keeps image centered inside viewport (offset=\(imageOffset) pt)")
        }
    }
    for size in [NSSize(width: 960, height: 640), NSSize(width: 641, height: 937)] {
        viewer.canvas.frame = NSRect(origin: .zero, size: size)
        viewer.prepareImageWindow()
        for pinch in [false, true] {
            for direction: CGFloat in [-1, 1] {
                viewer.zoomDriver.shouldReduceMotion = { true }
                viewer.actualSize(nil)
                let window = viewer.window!, area = viewer.screenArea
                window.setFrameOrigin(NSPoint(x: area.midX - window.frame.width / 2, y: area.midY - window.frame.height / 2))
                viewer.showWindow(nil)
                viewer.zoomDriver.shouldReduceMotion = { false }
                let original = window.frame
                var drift: CGFloat = 0
                for _ in 0..<180 {
                    event.precise = true
                    event.amount = direction * (pinch ? 0.08 : 24)
                    if pinch { viewer.scroll.magnify(with: event) }
                    else { viewer.scroll.scrollWheel(with: event) }
                    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.008))
                    while let pending = NSApp.nextEvent(matching: .any, until: Date(), inMode: .default, dequeue: true) {
                        NSApp.sendEvent(pending)
                    }
                    NSApp.updateWindows()
                    drift = max(drift, abs(window.frame.midX - original.midX))
                }
                _ = waitForCheck { abs(viewer.scroll.magnification - viewer.zoomDriver.target) < 1e-12 }
                drift = max(drift, abs(window.frame.midX - original.midX))
                check(drift < 1, "continuous \(pinch ? "pinch" : "wheel") \(direction) at \(size) retains horizontal center (\(drift) pt)")
                if direction < 0 {
                    let minimum = min(viewer.viewportGeometry!.minimumScale, 1 / window.backingScaleFactor)
                    check(abs(viewer.scroll.magnification - minimum) < 1e-12,
                          "\(pinch ? "pinch" : "wheel") stops at the preset minimum instead of shrinking to a dot")
                    let frame = window.frame, scale = viewer.scroll.magnification
                    let apply = viewer.zoomDriver.apply
                    var extraFrames = 0
                    viewer.zoomDriver.apply = { extraFrames += 1; apply?($0) }
                    for reduced in [false, true] {
                        viewer.zoomDriver.shouldReduceMotion = { reduced }
                        for _ in 0..<200 {
                            if pinch { viewer.scroll.magnify(with: event) }
                            else { viewer.scroll.scrollWheel(with: event) }
                        }
                        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
                    }
                    check(extraFrames == 0 && window.frame == frame && viewer.scroll.magnification == scale,
                          "400 more \(pinch ? "pinches" : "wheel events") at minimum do not reapply zoom or move the window")
                    viewer.zoomDriver.apply = apply
                }
            }
        }
    }
    for size in [NSSize(width: 80, height: 60), NSSize(width: 10000, height: 10)] {
        viewer.canvas.frame = NSRect(origin: .zero, size: size)
        viewer.prepareImageWindow()
        check(abs(viewer.scroll.magnification - viewer.zoomDriver.target) < 1e-12,
              "initial zoom stays synchronized for small or panoramic images (\(size))")
        viewer.zoomDriver.shouldReduceMotion = { true }
        event.amount = -100
        for _ in 0..<100 { viewer.scroll.scrollWheel(with: event) }
        let minimum = min(viewer.viewportGeometry!.minimumScale, 1 / viewer.window!.backingScaleFactor)
        check(abs(viewer.scroll.magnification - minimum) < 1e-12,
              "small or panoramic images respect their reachable minimum (\(size))")
    }
}
