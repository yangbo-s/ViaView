import AppKit
import ViewerCore

final class CenteredClipView: NSClipView {
    override func constrainBoundsRect(_ proposed: NSRect) -> NSRect {
        guard let documentView else { return super.constrainBoundsRect(proposed) }
        // Keep the image's real frame as the boundary. Title-bar insets and
        // rubber-band allowances must not become part of the image coordinates.
        var result = proposed
        let image = documentView.frame
        result.origin.x = image.width <= result.width ? image.midX - result.width / 2
            : min(image.maxX - result.width, max(image.minX, proposed.minX))
        result.origin.y = image.height <= result.height ? image.midY - result.height / 2
            : min(image.maxY - result.height, max(image.minY, proposed.minY))
        return result
    }
}

final class ImageCanvas: NSImageView {
    private static let checkerboard = NSColor(patternImage: NSImage(size: NSSize(width: 32, height: 32), flipped: false) { rect in
        NSColor(white: 0.22, alpha: 1).setFill(); rect.fill()
        NSColor(white: 0.28, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: 16, height: 16).fill(); NSRect(x: 16, y: 16, width: 16, height: 16).fill()
        return true
    })
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    var selection = NSRect.zero { didSet { needsDisplay = true } }
    var onNavigate: ((Int) -> Void)?
    var onDoubleClick: (() -> Void)?
    override func swipe(with event: NSEvent) { if UserDefaults.standard.bool(forKey: "swipeNavigate"), abs(event.deltaX) > 0 { onNavigate?(event.deltaX > 0 ? -1 : 1) } }
    override func keyDown(with event: NSEvent) {
        if event.keyCode == 123 { onNavigate?(-1) }
        else if event.keyCode == 124 { onNavigate?(1) }
        else if event.keyCode == 53 { selection = .zero }
        else { super.keyDown(with: event) }
    }
    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        if event.clickCount == 2, UserDefaults.standard.bool(forKey: "doubleClickZoom") { onDoubleClick?(); return }
        dragImageDocument(in: enclosingScrollView, with: event, selectionImage: self)
    }
    override func draw(_ dirtyRect: NSRect) {
        // A neutral checkerboard makes transparency visible, independent of the photo.
        (UserDefaults.standard.bool(forKey: "checkerboard") ? Self.checkerboard : .clear).setFill(); dirtyRect.fill()
        NSGraphicsContext.current?.imageInterpolation = UserDefaults.standard.bool(forKey: "smoothRendering") ? .high : .none
        super.draw(dirtyRect)
        if selection.width > 1 && selection.height > 1 {
            NSColor.controlAccentColor.withAlphaComponent(0.15).setFill(); selection.fill()
            let path = NSBezierPath(rect: selection); path.lineWidth = 1 / (enclosingScrollView?.magnification ?? 1)
            NSColor.white.setStroke(); path.stroke()
        }
    }
}

// Shared by raster and SVG content so zoomed images keep the same drag behavior.
func dragImageDocument(in candidate: NSScrollView?, with event: NSEvent, selectionImage: ImageCanvas? = nil) {
    guard let scroll = candidate, let document = scroll.documentView, let window = scroll.window else { return }
    let selecting = selectionImage != nil && (event.modifierFlags.contains(.command) != UserDefaults.standard.bool(forKey: "selectOnDrag"))
    if !selecting, document.frame.width <= scroll.contentView.bounds.width + 1,
       document.frame.height <= scroll.contentView.bounds.height + 1 {
        window.performDrag(with: event); return
    }
    let start = document.convert(event.locationInWindow, from: nil)
    let initialWindowPoint = event.locationInWindow
    let initialOrigin = scroll.contentView.bounds.origin
    if selecting { selectionImage?.selection = .zero }
    while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
        if next.type == .leftMouseUp { break }
        if selecting {
            let end = document.convert(next.locationInWindow, from: nil)
            selectionImage?.selection = NSRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)).intersection(document.bounds)
        } else {
            let dx = next.locationInWindow.x - initialWindowPoint.x
            let dy = next.locationInWindow.y - initialWindowPoint.y
            let vertical = document.isFlipped ? dy : -dy
            scroll.contentView.scroll(to: NSPoint(x: initialOrigin.x - dx / scroll.magnification, y: initialOrigin.y + vertical / scroll.magnification))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
}

final class WorkspaceView: NSView {
    var onDrop: (([URL]) -> Void)?
    var onPointer: ((NSPoint?) -> Void)?
    private var tracking: NSTrackingArea?
    override init(frame: NSRect) { super.init(frame: frame); registerForDraggedTypes([.fileURL]) }
    required init?(coder: NSCoder) { fatalError() }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { .copy }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else { return false }
        onDrop?(urls); return true
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas(); if let tracking { removeTrackingArea(tracking) }
        tracking = NSTrackingArea(rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(tracking!)
    }
    override func mouseMoved(with event: NSEvent) { onPointer?(convert(event.locationInWindow, from: nil)) }
    override func mouseEntered(with event: NSEvent) { mouseMoved(with: event) }
    override func mouseExited(with event: NSEvent) { onPointer?(nil) }
}
