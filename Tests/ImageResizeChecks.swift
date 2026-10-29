import AppKit
import ViewerCore

@MainActor func runImageResizeChecks(_ check: (Bool, String) -> Void) {
    let overlay = ImageResizeOverlay(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
    overlay.update(enabled: true, excluding: [])
    let targets: [(NSPoint, ImageResizeEdge)] = [
        (NSPoint(x: 9, y: 200), .left), (NSPoint(x: 591, y: 200), .right),
        (NSPoint(x: 300, y: 9), .bottom), (NSPoint(x: 300, y: 391), .top),
        (NSPoint(x: 21, y: 21), .bottomLeft), (NSPoint(x: 579, y: 21), .bottomRight),
        (NSPoint(x: 21, y: 379), .topLeft), (NSPoint(x: 579, y: 379), .topRight)
    ]
    for (point, edge) in targets {
        check(overlay.hitTest(point) === overlay && overlay.edge(at: point) == edge, "expanded hit region reaches \(edge) at \(point)")
    }
    for point in [NSPoint(x: 10.1, y: 200), NSPoint(x: 589.9, y: 200), NSPoint(x: 300, y: 10.1),
                  NSPoint(x: 300, y: 389.9), NSPoint(x: 22.1, y: 22.1), NSPoint(x: 300, y: 200), NSPoint(x: -1, y: 20)] {
        check(overlay.hitTest(point) == nil, "resize overlay passes through outside the hot regions at \(point)")
    }
    let protected = NSRect(x: 12, y: 12, width: 32, height: 32)
    overlay.update(enabled: true, excluding: [protected])
    check(overlay.hitTest(NSPoint(x: 18, y: 18)) == nil && overlay.edge(at: NSPoint(x: 6, y: 18)) == .bottomLeft
          && overlay.regions.allSatisfy { $0.rect.intersection(protected).isEmpty },
          "button exclusion removes both the click and cursor region while retaining the adjacent corner")

    for size in [NSSize(width: 600, height: 400), NSSize(width: 400, height: 600)] {
        let initial = NSRect(origin: NSPoint(x: 200, y: 200), size: size)
        let minimum = NSSize(width: size.width / 2, height: size.height / 2)
        let maximum = NSSize(width: size.width * 2, height: size.height * 2)
        for edge in ImageResizeEdge.allCases {
            let resized = edge.frame(from: initial, contentSize: size,
                                     delta: NSPoint(x: edge.horizontal * size.width / 4, y: edge.vertical * size.height / 4),
                                     minimum: minimum, maximum: maximum)
            let anchorX = edge.horizontal < 0 ? resized.maxX : edge.horizontal > 0 ? resized.minX : resized.midX
            let anchorY = edge.vertical < 0 ? resized.maxY : edge.vertical > 0 ? resized.minY : resized.midY
            let expectedX = edge.horizontal < 0 ? initial.maxX : edge.horizontal > 0 ? initial.minX : initial.midX
            let expectedY = edge.vertical < 0 ? initial.maxY : edge.vertical > 0 ? initial.minY : initial.midY
            check(abs(resized.width - size.width * 1.25) < 0.001 && abs(resized.height - size.height * 1.25) < 0.001
                  && anchorX == expectedX && anchorY == expectedY, "\(edge) preserves image ratio and opposite anchor for \(size)")
            for direction: CGFloat in [-1, 1] {
                let limited = edge.frame(from: initial, contentSize: size,
                                         delta: NSPoint(x: edge.horizontal * 10000 * direction, y: edge.vertical * 10000 * direction),
                                         minimum: minimum, maximum: maximum)
                check(limited.size == (direction < 0 ? minimum : maximum), "\(edge) clamps at \(direction < 0 ? "minimum" : "maximum") for \(size)")
            }
        }
    }

    let viewer = ViewerController()
    defer { viewer.close() }
    let window = viewer.window!
    let size = NSSize(width: 1200, height: 800), image = NSImage(size: NSSize(width: 1200, height: 800))
    viewer.asset = ImageAsset(url: URL(fileURLWithPath: "/tmp/resize-check.png"), image: image, cgImage: nil, properties: [:])
    viewer.canvas.image = image; viewer.canvas.frame = NSRect(origin: .zero, size: size)
    viewer.scroll.isHidden = false
    viewer.empty.isHidden = true; viewer.emptyTitle.stringValue = ""; viewer.emptyDetail.stringValue = ""
    viewer.root.layoutSubtreeIfNeeded(); viewer.prepareImageWindow(); viewer.showWindow(nil)
    func settle() {
        window.contentView!.superview!.layoutSubtreeIfNeeded()
        viewer.layoutChrome(); viewer.pointer(nil)
        window.displayIfNeeded()
    }
    func mouse(_ type: NSEvent.EventType, _ location: NSPoint) -> NSEvent {
        NSEvent.mouseEvent(with: type, location: location, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                          windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
    }
    for edge in ImageResizeEdge.allCases {
        window.setContentSize(NSSize(width: 480, height: 320)); settle()
        window.setFrameOrigin(NSPoint(x: viewer.screenArea.midX - 240, y: viewer.screenArea.midY - 160))
        let initial = window.frame, contentSize = window.contentRect(forFrameRect: initial).size
        let rect = edge.hitRect(in: viewer.resizeOverlay.bounds)
        // 18 pt inside corners and 9 pt inside edges exercises the added area.
        let inset: CGFloat = edge.horizontal != 0 && edge.vertical != 0 ? 18 : 9
        let horizontalInset: CGFloat = edge == .topRight ? 8 : inset
        let location = NSPoint(x: edge.horizontal < 0 ? horizontalInset : edge.horizontal > 0 ? contentSize.width - horizontalInset : rect.midX,
                               y: edge.vertical < 0 ? inset : edge.vertical > 0 ? contentSize.height - inset : rect.midY)
        let down = mouse(.leftMouseDown, location)
        let routed = viewer.routeViewerEvent(down)
        let hit = viewer.root.hitTest(viewer.root.convert(location, from: nil))
        check(routed === down && hit === viewer.resizeOverlay, "real viewer dispatch reaches expanded \(edge) handle")
        let delta = NSPoint(x: edge.horizontal * 48, y: edge.vertical * 32)
        let expected = edge.frame(from: initial, contentSize: contentSize, delta: delta, minimum: window.contentMinSize, maximum: window.contentMaxSize)
        NSApp.postEvent(mouse(.leftMouseDragged, NSPoint(x: location.x + delta.x, y: location.y + delta.y)), atStart: false)
        // Both events are queued before the window moves. Their global Quartz
        // position must remain stable even when NSEvent's local position changes.
        NSApp.postEvent(mouse(.leftMouseUp, NSPoint(x: location.x + delta.x, y: location.y + delta.y)), atStart: false)
        hit?.mouseDown(with: down)
        settle()
        check(abs(window.frame.width - expected.width) < 1 && abs(window.frame.height - expected.height) < 1
              && abs(window.frame.minX - expected.minX) < 1 && abs(window.frame.minY - expected.minY) < 1,
              "queued mouse drag/up resizes \(edge) with a fixed screen anchor (actual=\(window.frame), expected=\(expected))")
        check(abs(viewer.scroll.magnification - window.contentView!.bounds.width / size.width) < 0.002
              && viewer.zoomWindowAnchor == nil, "\(edge) resize synchronizes image zoom and clears the old wheel anchor")
    }
    viewer.setWindowControls(true); viewer.setChrome(true); viewer.updateResizeRegions()
    for button in viewer.windowButtons + viewer.topActions + Array(viewer.buttons.values) where !button.isHiddenOrHasHiddenAncestor {
        let point = viewer.resizeOverlay.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), from: button)
        check(viewer.resizeOverlay.edge(at: point) == nil, "resize leaves \(button.toolTip ?? button.title) button clicks available")
    }
    let center = NSPoint(x: viewer.root.bounds.midX, y: viewer.root.bounds.midY)
    check(viewer.root.hitTest(center) === viewer.canvas, "central picture clicks retain the original drag responder")
    viewer.asset = ImageAsset(url: URL(fileURLWithPath: "/tmp/resize-check.svg"), image: image, cgImage: nil, properties: [:])
    let svgLocation = NSPoint(x: viewer.root.bounds.width - 9, y: viewer.root.bounds.midY)
    let svgDown = mouse(.leftMouseDown, svgLocation)
    NSApp.postEvent(mouse(.leftMouseUp, svgLocation), atStart: true)
    check(viewer.routeViewerEvent(svgDown) === svgDown && viewer.root.hitTest(svgLocation) === viewer.resizeOverlay,
          "SVG event routing leaves the expanded resize handle ahead of document dragging")
    _ = NSApp.nextEvent(matching: .leftMouseUp, until: Date(), inMode: .default, dequeue: true)
    viewer.samplingColor = true; viewer.updateResizeRegions()
    check(viewer.resizeOverlay.regions.isEmpty, "color sampling disables expanded resize regions")
    viewer.samplingColor = false; viewer.transitioningFullScreen = true; viewer.updateResizeRegions()
    check(viewer.resizeOverlay.regions.isEmpty, "fullscreen transitions disable expanded resize regions")
    viewer.transitioningFullScreen = false
    viewer.asset = nil; viewer.updateResizeRegions()
    check(viewer.resizeOverlay.regions.isEmpty, "empty viewer retains system window behavior")
}
