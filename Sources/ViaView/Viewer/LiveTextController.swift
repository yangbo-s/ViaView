import AppKit
import VisionKit

// Keep native text selection in viewport points, independent of image magnification.
@MainActor final class LiveTextHost: NSView {
    weak var controller: LiveTextController?
    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let controller, !isHidden,
              controller.ownsInteraction(at: convert(point, from: superview)) else { return nil }
        let hit = super.hitTest(point)
        return hit === self ? nil : hit
    }
}

@MainActor final class LiveTextController: NSObject, ImageAnalysisOverlayViewDelegate {
    enum State: Equatable { case unavailable, analyzing, ready, noText, failed }
    typealias Analyze = (CGImage) async throws -> ImageAnalysis
    private static let analyzer = ImageAnalyzer()
    let host = LiveTextHost()
    let overlay = ImageAnalysisOverlayView(frame: .zero)
    let copyAllSurface = GlassChrome(radius: ChromeMetrics.radius)
    let copyAllButton = NSButton(title: "复制全部", target: nil, action: nil)
    private(set) var state: State = .unavailable
    private let analyze: Analyze
    private let pasteboard: NSPasteboard
    private var copyFeedbackGeneration = 0
    let isSupported: Bool
    private var task: Task<Void, Never>?
    private var generation = 0
    private var activationRequested = false
    private var hoverVisible = false
    private var suppressed = false
    private var lastContentsRect = NSRect.zero
    private weak var imageView: NSImageView?
    var onActivityChange: (() -> Void)?
    var onNotice: ((String) -> Void)?

    var isEngaged: Bool { overlay.selectableItemsHighlighted || overlay.hasActiveTextSelection }
    var selectedText: String { overlay.selectedText }

    init(isSupported: Bool = ImageAnalyzer.isSupported, pasteboard: NSPasteboard = .general, analyze: Analyze? = nil) {
        self.isSupported = isSupported
        self.pasteboard = pasteboard
        self.analyze = analyze ?? { image in
            try await Self.analyzer.analyze(image, orientation: .up, configuration: .init(.text))
        }
        super.init()
        host.controller = self
        host.isHidden = true
        overlay.delegate = self
        overlay.preferredInteractionTypes = .textSelection
        overlay.isSupplementaryInterfaceHidden = true
        overlay.supplementaryInterfaceContentInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        host.addSubview(overlay)
        overlay.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: host.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: host.bottomAnchor)
        ])
        host.addSubview(copyAllSurface)
        copyAllSurface.isHidden = true
        copyAllSurface.translatesAutoresizingMaskIntoConstraints = false
        copyAllButton.target = self; copyAllButton.action = #selector(copyAll(_:))
        copyAllButton.isBordered = false; copyAllButton.font = .systemFont(ofSize: 12, weight: .medium)
        copyAllButton.setAccessibilityLabel("复制全部识别文字")
        copyAllButton.translatesAutoresizingMaskIntoConstraints = false
        copyAllSurface.content.addSubview(copyAllButton)
        NSLayoutConstraint.activate([
            copyAllSurface.leadingAnchor.constraint(equalTo: host.leadingAnchor, constant: ChromeMetrics.edgeInset),
            copyAllSurface.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -ChromeMetrics.edgeInset),
            copyAllSurface.heightAnchor.constraint(equalToConstant: ChromeMetrics.height),
            copyAllButton.leadingAnchor.constraint(equalTo: copyAllSurface.content.leadingAnchor, constant: 12),
            copyAllButton.trailingAnchor.constraint(equalTo: copyAllSurface.content.trailingAnchor, constant: -12),
            copyAllButton.centerYAnchor.constraint(equalTo: copyAllSurface.content.centerYAnchor),
            copyAllButton.heightAnchor.constraint(equalToConstant: ChromeMetrics.buttonSize)
        ])
        copyAllButton.widthAnchor.constraint(greaterThanOrEqualToConstant: 48).isActive = true
    }

    func attach(to imageView: NSImageView) { self.imageView = imageView }

    func reset() {
        generation += 1; task?.cancel(); task = nil
        copyFeedbackGeneration += 1; copyAllButton.title = "复制全部"
        activationRequested = false
        overlay.resetSelection(); overlay.selectableItemsHighlighted = false; overlay.analysis = nil
        state = .unavailable; host.isHidden = true
        copyAllSurface.isHidden = true
        overlay.isSupplementaryInterfaceHidden = true
    }

    func update(image: CGImage?, delay: UInt64 = 250_000_000) {
        reset()
        guard isSupported, let image else { return }
        state = .analyzing
        let revision = generation, analyze = self.analyze
        task = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: delay)
                try Task.checkCancellation()
                let result = try await analyze(image)
                guard !Task.isCancelled, let self, self.generation == revision else { return }
                self.task = nil
                self.overlay.analysis = result
                self.state = result.hasResults(for: .text) ? .ready : .noText
                self.host.isHidden = self.state != .ready
                self.updateGeometry()
                if self.activationRequested { self.beginSelection() }
                self.refreshVisibility()
            } catch {
                guard !Task.isCancelled, let self, self.generation == revision else { return }
                self.task = nil; self.state = .failed
                if self.activationRequested { self.onNotice?("文字识别暂时不可用，请重试。") }
                self.activationRequested = false
            }
        }
    }

    func beginSelection() {
        switch state {
        case .ready:
            activationRequested = false
            overlay.selectableItemsHighlighted = true
            refreshVisibility(); onActivityChange?()
        case .analyzing: activationRequested = true
        case .noText: activationRequested = false; onNotice?("这张图片中未识别到文字。")
        case .failed: onNotice?("文字识别暂时不可用，请重试。")
        case .unavailable: break
        }
    }

    func endSelection() {
        activationRequested = false
        overlay.resetSelection(); overlay.selectableItemsHighlighted = false
        refreshVisibility(); onActivityChange?()
    }

    func setHoverVisible(_ visible: Bool, suppressed: Bool = false) {
        hoverVisible = visible; self.suppressed = suppressed
        refreshVisibility()
    }

    private func refreshVisibility() {
        host.isHidden = state != .ready || suppressed
        copyAllSurface.isHidden = state != .ready || suppressed || !isEngaged
        overlay.isSupplementaryInterfaceHidden = !(state == .ready && !suppressed && (hoverVisible || isEngaged))
    }

    func updateGeometry() {
        guard let canvas = imageView, overlay.bounds.width > 0, overlay.bounds.height > 0 else { return }
        let rect = overlay.convert(canvas.bounds, from: canvas)
        if rect != lastContentsRect { lastContentsRect = rect; overlay.setContentsRectNeedsUpdate() }
    }

    func ownsInteraction(at point: NSPoint) -> Bool {
        guard !host.isHidden, state == .ready else { return false }
        guard host.bounds.contains(point) else { return false }
        // The native selection view owns drags once text mode is active. Its hit
        // test handles text, selection margins and the click that clears a range.
        if isEngaged { return true }
        guard !overlay.isSupplementaryInterfaceHidden else { return false }
        var location = overlay.convert(point, from: host)
        // VisionKit's interaction queries use a top-left origin, even when the
        // AppKit overlay is unflipped (as with its contentsRect coordinates).
        if !overlay.isFlipped { location.y = overlay.bounds.maxY - location.y + overlay.bounds.minY }
        return overlay.hasSupplementaryInterface(at: location)
    }

    @discardableResult func copySelection(to pasteboard: NSPasteboard) -> Bool {
        guard !selectedText.isEmpty else { return false }
        pasteboard.clearContents(); pasteboard.setString(selectedText, forType: .string)
        return true
    }

    @discardableResult func copyAll(to pasteboard: NSPasteboard) -> Bool {
        guard state == .ready, let text = overlay.analysis?.transcript, !text.isEmpty else { return false }
        pasteboard.clearContents(); pasteboard.setString(text, forType: .string)
        return true
    }

    @objc private func copyAll(_ sender: Any?) {
        if copyAll(to: pasteboard) {
            copyFeedbackGeneration += 1; let feedback = copyFeedbackGeneration
            copyAllButton.title = "已复制"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.copyFeedbackGeneration == feedback else { return }
                self.copyAllButton.title = "复制全部"
            }
            NSAccessibility.post(element: host, notification: .announcementRequested,
                                 userInfo: [.announcement: "已复制全部文字", .priority: NSAccessibilityPriorityLevel.medium.rawValue])
        }
    }

    func handleKey(_ event: NSEvent) -> Bool {
        guard isEngaged else { return false }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting([.capsLock, .numericPad, .function])
        if event.keyCode == 53, modifiers.isEmpty { endSelection(); return true }
        if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "a", !overlay.text.isEmpty {
            overlay.selectedRanges = [overlay.text.startIndex..<overlay.text.endIndex]; return true
        }
        return false
    }

    func contentView(for overlayView: ImageAnalysisOverlayView) -> NSView? {
        // VisionKit samples the visible content for its highlight treatment.
        // Use the viewport so a clipped/rotated canvas is not sampled twice.
        imageView?.enclosingScrollView ?? imageView
    }
    func contentsRect(for overlayView: ImageAnalysisOverlayView) -> CGRect {
        guard let imageView, overlayView.bounds.width > 0, overlayView.bounds.height > 0 else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        // The canvas can extend beyond the viewport. Keep the full image rect,
        // including negative origins, instead of fitting it to the visible crop.
        let rect = overlayView.convert(imageView.bounds, from: imageView)
        let bounds = overlayView.bounds
        // VisionKit unit coordinates start at the top-left, unlike an unflipped NSView.
        let top = overlayView.isFlipped ? rect.minY - bounds.minY : bounds.maxY - rect.maxY
        return CGRect(x: (rect.minX - bounds.minX) / bounds.width,
                      y: top / bounds.height,
                      width: rect.width / bounds.width, height: rect.height / bounds.height)
    }
    func overlayView(_ overlayView: ImageAnalysisOverlayView, highlightSelectedItemsDidChange highlighted: Bool) {
        refreshVisibility(); onActivityChange?()
    }
    func textSelectionDidChange(_ overlayView: ImageAnalysisOverlayView) { refreshVisibility(); onActivityChange?() }
}

extension ViewerController {
    var supportsLiveTextForCurrentImage: Bool {
        liveText.isSupported && !isLoading && !editPending && displayedCG != nil && (asset?.canAnimate != true || !edits.isIdentity)
    }
    func refreshLiveText() {
        liveText.update(image: supportsLiveTextForCurrentImage ? displayedCG : nil)
    }
    func configureLiveText() {
        liveText.attach(to: canvas)
        liveText.onActivityChange = { [weak self] in
            guard let self else { return }
            if self.liveText.isEngaged {
                self.canvas.selection = .zero
                self.timer?.invalidate(); self.timer = nil
            }
            self.refreshChrome(); self.updateCommandControls()
        }
        liveText.onNotice = { [weak self] message in
            guard let window = self?.window else { return }
            let alert = NSAlert(); alert.messageText = message; alert.beginSheetModal(for: window)
        }
    }
}
