import AppKit

// Empty space between controls remains part of the draggable image.
final class ChromeRow: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let hit = super.hitTest(point) else { return nil }
        var view: NSView? = hit
        while let current = view, current !== self {
            if current is NSButton || current is GlassChrome { return hit }
            view = current.superview
        }
        return nil
    }
}

// Keep a real NSButton cell for native enabled, pressed and accessibility behavior.
// Center the icon/title pair together, with explicit breathing room inside the glass.
private final class ExternalEditorButtonCell: NSButtonCell {
    private let gap: CGFloat = 8
    private let inset: CGFloat = 6 // Plus the glass group's 4 pt: matches normal icon groups.
    private var titleWidth: CGFloat { min(100, ceil(attributedTitle.size().width)) }

    override var cellSize: NSSize {
        NSSize(width: ToolbarIcon.pointSize + gap + titleWidth + inset * 2, height: 32)
    }

    private func contentFrames(in bounds: NSRect) -> (image: NSRect, title: NSRect) {
        let iconSize = ToolbarIcon.pointSize
        let titleWidth = min(self.titleWidth, max(0, bounds.width - inset * 2 - iconSize - gap))
        let start = bounds.midX - (iconSize + gap + titleWidth) / 2
        return (
            NSRect(x: start, y: bounds.midY - iconSize / 2, width: iconSize, height: iconSize),
            NSRect(x: start + iconSize + gap, y: bounds.minY, width: titleWidth, height: bounds.height)
        )
    }

    override func drawImage(_ image: NSImage, withFrame frame: NSRect, in controlView: NSView) {
        super.drawImage(image, withFrame: contentFrames(in: controlView.bounds).image, in: controlView)
    }

    override func drawTitle(_ title: NSAttributedString, withFrame frame: NSRect, in controlView: NSView) -> NSRect {
        var titleFrame = contentFrames(in: controlView.bounds).title
        // AppKit determines the vertical text alignment; only the horizontal layout changes.
        titleFrame.origin.y = frame.origin.y
        titleFrame.size.height = frame.height
        return super.drawTitle(title, withFrame: titleFrame, in: controlView)
    }
}

extension ViewerController {
    func buildTopChrome() {
        let traffic = NSView(); traffic.translatesAutoresizingMaskIntoConstraints = false
        let trafficWidth = traffic.widthAnchor.constraint(equalToConstant: 80)
        NSLayoutConstraint.activate([trafficWidth, traffic.heightAnchor.constraint(equalToConstant: 36)])
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        nameLabel.setContentHuggingPriority(NSLayoutConstraint.Priority(1), for: .horizontal)
        nameLabel.wantsLayer = true
        nameLabel.layer?.shadowRadius = 2
        nameLabel.layer?.shadowOffset = CGSize(width: 0, height: -0.5)
        func action(_ icon: ToolbarIcon, _ title: String, _ selector: Selector) -> NSButton {
            let button = toolbarButton(icon, title, target: self, action: selector, size: 32)
            topActions.append(button); return button
        }
        func group(_ views: [NSView]) -> GlassChrome {
            let chrome = GlassChrome(radius: 20)
            let stack = NSStackView(views: views); stack.spacing = 4; stack.alignment = .centerY
            pin(stack, to: chrome.content, inset: 4)
            return chrome
        }
        let tools = group([
            action(.list, "文件列表 · ⌘B", #selector(toggleFileList(_:))),
            action(.tag, "Finder 标签", #selector(editTags(_:))),
            action(.pipette, "取色并复制色号 · ⌘E", #selector(pickColor(_:))),
            action(.adjustments, "图像调整 · ⌘F", #selector(toggleAdjustments(_:))),
            action(.info, "图片信息 · ⌘I", #selector(toggleInfo(_:)))])
        let essentials = group([
            action(.list, "文件列表 · ⌘B", #selector(toggleFileList(_:))),
            action(.tag, "Finder 标签", #selector(editTags(_:)))])
        compactTools = essentials
        let files = group([
            action(.folder, "在 Finder 中显示", #selector(reveal(_:))),
            action(.share, "分享图片", #selector(share(_:)))])
        let previewButton = NSButton(frame: .zero)
        previewButton.cell = ExternalEditorButtonCell(textCell: AppSettings.editorName)
        previewButton.setButtonType(.momentaryPushIn)
        previewButton.target = self; previewButton.action = #selector(openEditor(_:))
        previewButton.alignment = .left
        previewButton.isBordered = false; previewButton.font = .systemFont(ofSize: 12, weight: .medium)
        previewButton.image = ToolbarIcon.applicationImage(at: AppSettings.editorURL)
        previewButton.imageScaling = .scaleNone
        previewButton.imagePosition = .imageLeading
        previewButton.cell?.lineBreakMode = .byTruncatingTail
        previewButton.translatesAutoresizingMaskIntoConstraints = false
        previewButton.setContentHuggingPriority(.required, for: .horizontal)
        previewButton.setContentCompressionResistancePriority(.required, for: .horizontal)
        previewButton.heightAnchor.constraint(equalToConstant: 32).isActive = true
        previewButton.setAccessibilityLabel("在预览中打开"); topActions.append(previewButton)
        let preview = group([previewButton])
        let pinButton = action(.pin, "窗口置顶", #selector(alwaysOnTop(_:)))
        let pinGroup = group([pinButton])
        moreButton.target = self
        let overflow = group([moreButton])
        toolGroups = [tools, files, preview, pinGroup]
        let stack = NSStackView(views: [traffic, nameLabel, essentials] + toolGroups + [overflow])
        stack.spacing = 8; stack.alignment = .centerY; stack.detachesHiddenViews = true
        stack.setCustomSpacing(16, after: traffic)
        pin(stack, to: topChrome)
        topChromeTop = topChrome.topAnchor.constraint(equalTo: glassLayer.content.topAnchor, constant: 8)
        NSLayoutConstraint.activate([
            topChrome.leadingAnchor.constraint(equalTo: glassLayer.content.leadingAnchor, constant: 16),
            topChrome.trailingAnchor.constraint(equalTo: glassLayer.content.trailingAnchor, constant: -12),
            topChromeTop!,
            topChrome.heightAnchor.constraint(equalToConstant: 44)])
    }

    func updateTopActions() {
        for button in topActions {
            guard let action = button.action else { continue }
            let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
            button.isEnabled = validateMenuItem(item)
            if action == #selector(alwaysOnTop(_:)) {
                let pinned = window?.level == .floating
                button.image = (pinned ? ToolbarIcon.unpin : .pin).image
                button.toolTip = pinned ? "取消窗口置顶" : "窗口置顶"
                button.setAccessibilityLabel(button.toolTip)
            }
            if action == #selector(openEditor(_:)) {
                button.title = AppSettings.editorName
                button.image = ToolbarIcon.applicationImage(at: AppSettings.editorURL)
                button.toolTip = "用\(AppSettings.editorName)打开原文件"
                button.setAccessibilityLabel(button.toolTip)
            }
        }
    }

    func updateTitleContrast() {
        // Sample the pixels actually underneath the filename, not the whole photograph.
        // Only a tiny crop of the decoded preview is drawn; hidden chrome does no per-frame work.
        titleUsesCanvas = scroll.magnification < (viewportGeometry?.minimumScale ?? 0)
        var luminance: Double = usesDarkAppearance ? 0 : 1
        var titleRect = nameLabel.bounds
        titleRect.size.width = min(titleRect.width, nameLabel.attributedStringValue.size().width)
        let imageRect = canvas.convert(titleRect, from: nameLabel).intersection(canvas.bounds)
        let titleOverImage = imageRect.width > 1 && imageRect.height > 1
        if let source = displayedCG, titleOverImage, let image = source.cropping(to: imageRect.integral) {
            var pixels = [UInt8](repeating: 0, count: 8 * 8 * 4)
            pixels.withUnsafeMutableBytes { bytes in
                if let context = CGContext(data: bytes.baseAddress, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 32, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
                    context.setFillColor(usesDarkAppearance ? NSColor.black.cgColor : NSColor.white.cgColor)
                    context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
                    context.draw(image, in: CGRect(x: 0, y: 0, width: 8, height: 8))
                }
            }
            var total = 0.0
            for i in stride(from: 0, to: pixels.count, by: 4) {
                let red = Double(pixels[i]) * 0.2126
                let green = Double(pixels[i + 1]) * 0.7152
                let blue = Double(pixels[i + 2]) * 0.0722
                total += red + green + blue
            }
            luminance = total / 16320.0
        }
        let darkText = luminance > 0.52
        nameLabel.textColor = darkText ? .black : .white
        nameLabel.layer?.shadowColor = (darkText ? NSColor.white : NSColor.black).cgColor
        nameLabel.layer?.shadowOpacity = darkText ? 0.3 : 0.75
        nameLabel.toolTip = nameLabel.stringValue + "\n" + imageSummary
        updateTopActions()
    }
}
