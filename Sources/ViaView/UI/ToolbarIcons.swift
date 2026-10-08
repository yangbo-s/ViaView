import AppKit

/// Official Lucide SVGs, bundled locally. The same 24-unit artwork is rendered
/// at 20 pt in both bars; resizing a window never resizes an individual glyph.
enum ToolbarIcon: String, CaseIterable {
    case list, tag, info, folder, share, pin, play, pause, maximize
    case pipette
    case adjustments = "sliders-horizontal"
    case unpin = "pin-off"
    case more = "chevrons-right"
    case zoomIn = "zoom-in"
    case zoomOut = "zoom-out"
    case fit = "minimize-2"
    case previous = "chevron-left"
    case next = "chevron-right"
    case rotateRight = "rotate-cw"
    case externalEditor = "external-link"

    static let pointSize: CGFloat = 20
    private static var images: [ToolbarIcon: NSImage] = [:]
    private static var applicationImages: [URL: NSImage] = [:]
    // SwiftPM's generated lookup checks the app root, whereas a signed macOS
    // application keeps resource bundles in Contents/Resources.
    private static let resources: Bundle = {
        if let url = Bundle.main.url(forResource: "ViaView_ViaView", withExtension: "bundle"),
           let bundle = Bundle(url: url) { return bundle }
        return Bundle.module
    }()

    var image: NSImage {
        if let cached = Self.images[self] { return cached }
        guard let url = Self.resources.url(forResource: rawValue, withExtension: "svg", subdirectory: "Lucide"),
              let image = NSImage(contentsOf: url) else {
            assertionFailure("Missing bundled Lucide icon: \(rawValue)")
            return NSImage()
        }
        image.size = NSSize(width: Self.pointSize, height: Self.pointSize)
        image.isTemplate = true
        Self.images[self] = image
        return image
    }

    static func applicationImage(at url: URL?) -> NSImage {
        guard let url else { return ToolbarIcon.externalEditor.image }
        if let cached = applicationImages[url] { return cached }
        let image = NSWorkspace.shared.icon(forFile: url.path)
        image.size = NSSize(width: pointSize, height: pointSize)
        applicationImages[url] = image
        return image
    }
}

func toolbarButton(_ icon: ToolbarIcon, _ title: String, target: AnyObject?, action: Selector, size: CGFloat = 36) -> NSButton {
    let button = NSButton(image: icon.image, target: target, action: action)
    button.bezelStyle = .texturedRounded; button.isBordered = false
    button.imageScaling = .scaleNone
    button.contentTintColor = .labelColor; button.toolTip = title; button.setAccessibilityLabel(title)
    button.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([button.widthAnchor.constraint(equalToConstant: size), button.heightAnchor.constraint(equalToConstant: size)])
    return button
}
