import AppKit
import ViewerCore

private final class ZoomInputEvent: NSEvent {
    var amount: CGFloat = 0
    override var scrollingDeltaX: CGFloat { 0 }
    override var scrollingDeltaY: CGFloat { amount }
    override var hasPreciseScrollingDeltas: Bool { false }
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
}
