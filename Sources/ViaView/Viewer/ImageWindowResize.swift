import AppKit

enum ImageResizeEdge: CaseIterable {
    case bottomLeft, bottomRight, topLeft, topRight, left, right, bottom, top

    var horizontal: CGFloat {
        switch self {
        case .left, .bottomLeft, .topLeft: return -1
        case .right, .bottomRight, .topRight: return 1
        default: return 0
        }
    }
    var vertical: CGFloat {
        switch self {
        case .bottom, .bottomLeft, .bottomRight: return -1
        case .top, .topLeft, .topRight: return 1
        default: return 0
        }
    }

    func hitRect(in bounds: NSRect) -> NSRect {
        let corner = min(22, min(bounds.width, bounds.height) / 2)
        let edge = min(10, corner)
        if horizontal != 0 && vertical != 0 {
            return NSRect(x: horizontal < 0 ? bounds.minX : bounds.maxX - corner,
                          y: vertical < 0 ? bounds.minY : bounds.maxY - corner, width: corner, height: corner)
        }
        if horizontal != 0 {
            return NSRect(x: horizontal < 0 ? bounds.minX : bounds.maxX - edge,
                          y: bounds.minY + corner, width: edge, height: bounds.height - 2 * corner)
        }
        return NSRect(x: bounds.minX + corner, y: vertical < 0 ? bounds.minY : bounds.maxY - edge,
                      width: bounds.width - 2 * corner, height: edge)
    }

    func frame(from initial: NSRect, contentSize: NSSize, delta: NSPoint, minimum: NSSize, maximum: NSSize) -> NSRect {
        let width = max(1, contentSize.width), height = max(1, contentSize.height)
        let change: CGFloat
        if horizontal == 0 { change = vertical * delta.y / height }
        else if vertical == 0 { change = horizontal * delta.x / width }
        else {
            // Project the pointer onto the image diagonal, so either axis can
            // resize a corner without changing the image's aspect ratio.
            change = (horizontal * delta.x * width + vertical * delta.y * height) / (width * width + height * height)
        }
        let lower = max(minimum.width / width, minimum.height / height)
        let upper = max(lower, min(maximum.width / width, maximum.height / height))
        let scale = min(upper, max(lower, 1 + change))
        let size = NSSize(width: initial.width + width * (scale - 1), height: initial.height + height * (scale - 1))
        return NSRect(x: horizontal < 0 ? initial.maxX - size.width : horizontal > 0 ? initial.minX : initial.midX - size.width / 2,
                      y: vertical < 0 ? initial.maxY - size.height : vertical > 0 ? initial.minY : initial.midY - size.height / 2,
                      width: size.width, height: size.height)
    }

    var cursor: NSCursor {
        if #available(macOS 15, *) {
            let position: NSCursor.FrameResizePosition
            switch self {
            case .bottomLeft: position = .bottomLeft
            case .bottomRight: position = .bottomRight
            case .topLeft: position = .topLeft
            case .topRight: position = .topRight
            case .left: position = .left
            case .right: position = .right
            case .bottom: position = .bottom
            case .top: position = .top
            }
            return .frameResize(position: position, directions: [.inward, .outward])
        }
        if horizontal == 0 { return .resizeUpDown }
        if vertical == 0 { return .resizeLeftRight }
        return horizontal == vertical ? Self.risingCursor : Self.fallingCursor
    }

    // macOS 14 has no public diagonal frame cursor. Draw a small outlined
    // double arrow instead of relying on a private AppKit cursor selector.
    private static let risingCursor = diagonalCursor(rising: true)
    private static let fallingCursor = diagonalCursor(rising: false)
    private static func diagonalCursor(rising: Bool) -> NSCursor {
        let image = NSImage(size: NSSize(width: 24, height: 24), flipped: false) { _ in
            let path = NSBezierPath()
            func point(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x, y: rising ? y : 24 - y) }
            path.move(to: point(5, 5)); path.line(to: point(19, 19))
            path.move(to: point(5, 11)); path.line(to: point(5, 5)); path.line(to: point(11, 5))
            path.move(to: point(13, 19)); path.line(to: point(19, 19)); path.line(to: point(19, 13))
            path.lineCapStyle = .round; path.lineJoinStyle = .round
            NSColor.white.setStroke(); path.lineWidth = 4; path.stroke()
            NSColor.black.setStroke(); path.lineWidth = 2; path.stroke()
            return true
        }
        return NSCursor(image: image, hotSpot: NSPoint(x: 12, y: 12))
    }
}

final class ImageResizeOverlay: NSView {
    struct Region: Equatable { let edge: ImageResizeEdge; let rect: NSRect }
    private(set) var regions: [Region] = []
    var onResize: ((ImageResizeEdge, NSEvent) -> Void)?

    func update(enabled: Bool, excluding protectedRects: [NSRect]) {
        let next = enabled ? ImageResizeEdge.allCases.flatMap { edge in
            protectedRects.reduce([edge.hitRect(in: bounds)]) { rects, obstacle in
                rects.flatMap { Self.subtract(obstacle, from: $0) }
            }.filter { !$0.isEmpty }.map { Region(edge: edge, rect: $0) }
        } : []
        guard next != regions else { return }
        regions = next
        window?.invalidateCursorRects(for: self)
    }

    func edge(at point: NSPoint) -> ImageResizeEdge? { regions.first { $0.rect.contains(point) }?.edge }
    override func hitTest(_ point: NSPoint) -> NSView? {
        edge(at: convert(point, from: superview)) == nil ? nil : self
    }
    override func resetCursorRects() {
        for region in regions { addCursorRect(region.rect, cursor: region.edge.cursor) }
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) {
        guard let edge = edge(at: convert(event.locationInWindow, from: nil)) else { return }
        onResize?(edge, event)
    }
    private static func subtract(_ obstacle: NSRect, from rect: NSRect) -> [NSRect] {
        let overlap = rect.intersection(obstacle)
        guard !overlap.isEmpty else { return [rect] }
        return [NSRect(x: rect.minX, y: rect.minY, width: rect.width, height: overlap.minY - rect.minY),
                NSRect(x: rect.minX, y: overlap.maxY, width: rect.width, height: rect.maxY - overlap.maxY),
                NSRect(x: rect.minX, y: overlap.minY, width: overlap.minX - rect.minX, height: overlap.height),
                NSRect(x: overlap.maxX, y: overlap.minY, width: rect.maxX - overlap.maxX, height: overlap.height)]
    }
}

extension ViewerController {
    func updateResizeRegions() {
        guard let window else { return }
        let enabled = asset != nil && !isLoading && !scroll.isHidden && !samplingColor && !liveText.isEngaged
            && !transitioningFullScreen && !window.styleMask.contains(.fullScreen) && window.attachedSheet == nil
        var protected: [NSView] = windowButtons + topActions + Array(buttons.values)
        func controls(in view: NSView) -> [NSView] {
            view.subviews.flatMap { child -> [NSView] in
                if child is NSControl || child.accessibilityIdentifier() == "com.apple.visionkit.liveTextButton" { return [child] }
                return controls(in: child)
            }
        }
        protected += controls(in: liveText.host)
        let rects = protected.filter { !$0.isHiddenOrHasHiddenAncestor }.map { resizeOverlay.convert($0.bounds, from: $0) }
        resizeOverlay.update(enabled: enabled, excluding: rects)
    }

    func resizeImageWindow(from edge: ImageResizeEdge, with event: NSEvent) {
        guard let window else { return }
        let initial = window.frame
        let contentSize = window.contentRect(forFrameRect: initial).size
        let start = resizeScreenPoint(for: event, in: window)
        let minimum = window.contentMinSize, maximum = window.contentMaxSize
        fitting = false; zoomWindowAnchor = nil; zoomDriver.reset(scroll.magnification)
        window.makeKeyAndOrderFront(nil)
        window.disableCursorRects(); edge.cursor.push()
        defer {
            NSCursor.pop(); window.enableCursorRects()
            updateResizeRegions(); window.invalidateCursorRects(for: resizeOverlay)
        }
        // Keep the edge and initial screen position for the entire gesture.
        // Window-local coordinates change as its left or bottom edge moves.
        while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            let point = resizeScreenPoint(for: next, in: window)
            let frame = edge.frame(from: initial, contentSize: contentSize,
                                   delta: NSPoint(x: point.x - start.x, y: point.y - start.y), minimum: minimum, maximum: maximum)
            if frame != window.frame { window.setFrame(frame, display: true) }
            if next.type == .leftMouseUp { break }
        }
    }

    private func resizeScreenPoint(for event: NSEvent, in window: NSWindow) -> NSPoint {
        // Queued NSEvents can retain coordinates from before the window moved.
        // Quartz keeps the original global position, independent of its frame.
        if let point = event.cgEvent?.location, let primary = NSScreen.screens.first {
            return NSPoint(x: point.x, y: primary.frame.maxY - point.y)
        }
        return window.convertPoint(toScreen: event.locationInWindow)
    }
}
