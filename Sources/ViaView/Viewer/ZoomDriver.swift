import AppKit
import QuartzCore
import ViewerCore

private final class ZoomTick: NSObject {
    weak var owner: ZoomDriver?
    @objc func tick(_ link: CADisplayLink) { owner?.tick(link) }
}

final class ZoomDriver {
    private let proxy = ZoomTick()
    private var link: CADisplayLink?
    private var lastTime: CFTimeInterval = 0
    private var motion = SmoothZoom()
    var apply: ((CGFloat) -> Void)?
    var target: CGFloat { motion.targetScale }
    init() { proxy.owner = self }
    func reset(_ scale: CGFloat) { link?.isPaused = true; lastTime = 0; motion.reset(scale) }
    func aim(_ scale: CGFloat, in view: NSView) {
        motion.aim(min(32, max(0.001, scale)))
        if link == nil {
            let displayLink = view.displayLink(target: proxy, selector: #selector(ZoomTick.tick(_:)))
            displayLink.add(to: .main, forMode: .common); link = displayLink
        }
        if link?.isPaused == true { lastTime = 0 }
        link?.isPaused = false
    }
    fileprivate func tick(_ link: CADisplayLink) {
        let dt = lastTime == 0 ? max(link.duration, 1 / 120) : min(0.05, max(0, link.timestamp - lastTime))
        lastTime = link.timestamp
        apply?(motion.advance(seconds: dt))
        if motion.isSettled { link.isPaused = true; lastTime = 0 }
    }
    func stop() { link?.invalidate(); link = nil; lastTime = 0 }
    deinit { stop() }
}

final class ImageScrollView: NSScrollView {
    var onZoom: ((CGFloat) -> Void)?
    override func scrollWheel(with event: NSEvent) {
        // Let horizontal/Shift scrolling pan details; vertical input always zooms.
        if event.modifierFlags.contains(.shift) || abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.5 {
            super.scrollWheel(with: event); return
        }
        let configured = CGFloat(UserDefaults.standard.double(forKey: "zoomSensitivity"))
        let sensitivity: CGFloat = (event.hasPreciseScrollingDeltas ? 0.003 : 0.065) * min(2, max(0.3, configured))
        onZoom?(exp(max(-0.6, min(0.6, event.scrollingDeltaY * sensitivity))))
    }
    override func magnify(with event: NSEvent) { onZoom?(exp(event.magnification)) }
}
