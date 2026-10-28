import AppKit
import VisionKit
import ViewerCore

@MainActor func runLiveTextChecks(_ check: (Bool, String) -> Void) {
    func fixture(text: Bool) -> CGImage {
        let image = NSImage(size: NSSize(width: 800, height: 300), flipped: false) { rect in
            NSColor.white.setFill(); rect.fill()
            if text {
                ("VIA VIEW 2026" as NSString).draw(at: NSPoint(x: 70, y: 100), withAttributes: [
                    .font: NSFont.systemFont(ofSize: 60, weight: .bold), .foregroundColor: NSColor.black
                ])
            }
            return true
        }
        return image.cgImage(forProposedRect: nil, context: nil, hints: nil)!
    }
    let pixels = fixture(text: true)
    let unsupported = LiveTextController(isSupported: false)
    unsupported.update(image: pixels, delay: 0)
    check(unsupported.state == .unavailable && unsupported.host.isHidden, "unsupported Live Text leaves the image unobstructed")
    var calls = 0
    let cancelled = LiveTextController(isSupported: true, analyze: { _ in calls += 1; throw CocoaError(.userCancelled) })
    cancelled.update(image: pixels); cancelled.reset()
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
    check(calls == 0 && cancelled.state == .unavailable, "rapid navigation cancels analysis before it starts")

    guard ImageAnalyzer.isSupported else {
        print("SKIP native Live Text recognition: unsupported device; fallback path checked")
        return
    }
    let analyzer = ImageAnalyzer()
    var textResult: ImageAnalysis?, blankResult: ImageAnalysis?, finished = false
    var failure: Error?
    Task { @MainActor in
        defer { finished = true }
        do {
            textResult = try await analyzer.analyze(pixels, orientation: .up, configuration: .init(.text))
            blankResult = try await analyzer.analyze(fixture(text: false), orientation: .up, configuration: .init(.text))
        } catch { failure = error }
    }
    _ = waitForCheck(timeout: 30) { finished }
    check(textResult?.transcript.contains("2026") == true && failure == nil, "native analyzer recognizes the local text fixture")
    guard let textResult, let blankResult else { return }
    check(!blankResult.hasResults(for: .text), "native analyzer reports no text for the blank fixture")

    var pending = [CheckedContinuation<ImageAnalysis, Error>]()
    let pasteboard = NSPasteboard.withUniqueName()
    defer { pasteboard.releaseGlobally() }
    let live = LiveTextController(isSupported: true, pasteboard: pasteboard, analyze: { _ in
        try await withCheckedThrowingContinuation { pending.append($0) }
    })
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 400, height: 150), styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let canvas = NSImageView(frame: window.contentView!.bounds)
    canvas.image = NSImage(cgImage: pixels, size: canvas.bounds.size)
    canvas.imageScaling = .scaleAxesIndependently
    window.contentView!.addSubview(canvas)
    live.host.frame = canvas.frame; window.contentView!.addSubview(live.host); live.attach(to: canvas)
    defer { live.reset(); window.close() }
    live.update(image: pixels, delay: 0)
    check(waitForCheck { pending.count == 1 }, "first Live Text request reaches its asynchronous boundary")
    live.update(image: pixels, delay: 0); live.beginSelection()
    check(waitForCheck { pending.count == 2 }, "a replacement image gets a separate analysis request")
    pending[1].resume(returning: textResult)
    check(waitForCheck { live.state == .ready } && live.isEngaged, "a pending explicit request opens text selection when analysis finishes")
    pending[0].resume(returning: blankResult)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    check(live.state == .ready && live.overlay.text.contains("2026"), "late analysis cannot replace the current image text")
    live.host.layoutSubtreeIfNeeded()
    canvas.frame = NSRect(x: -100, y: -60, width: 800, height: 300)
    live.updateGeometry()
    let croppedRect = live.contentsRect(for: live.overlay)
    check(abs(croppedRect.minX + 0.25) < 0.001 && abs(croppedRect.minY + 0.6) < 0.001
          && abs(croppedRect.width - 2) < 0.001 && abs(croppedRect.height - 2) < 0.001,
          "zoomed and panned text geometry retains the full image beyond the viewport")
    canvas.frame = live.host.bounds; live.updateGeometry()
    check(!live.copyAllSurface.isHidden, "Copy All is available only in active text mode")

    live.copyAllButton.performClick(nil)
    check(live.copyAllButton.title == "已复制" && pasteboard.string(forType: .string) == textResult.transcript,
          "the Copy All button dispatches its real action and confirms the copied transcript")
    check(live.copyAll(to: pasteboard) && pasteboard.string(forType: .string) == textResult.transcript,
          "Copy All writes the current transcript to the requested pasteboard")
    let all = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0,
                              windowNumber: window.windowNumber, context: nil, characters: "a", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: 0)!
    check(live.handleKey(all) && live.copySelection(to: pasteboard)
          && pasteboard.string(forType: .string) == live.selectedText && !live.selectedText.isEmpty,
          "Select All and copy use recognized text rather than image pixels")
    let escape = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                                 windowNumber: window.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 53)!
    live.setHoverVisible(false)
    check(live.handleKey(escape) && !live.isEngaged && live.copyAllSurface.isHidden && live.overlay.isSupplementaryInterfaceHidden,
          "Escape clears selection and returns to unobstructed viewing")
    check(!live.ownsInteraction(at: NSPoint(x: 200, y: 75)), "inactive Live Text passes image drags through")
    live.setHoverVisible(true)
    check(!live.overlay.isSupplementaryInterfaceHidden, "bottom hover reveals the native text entry")
    live.beginSelection(); live.setHoverVisible(true, suppressed: true)
    check(live.host.isHidden && live.copyAllSurface.isHidden, "color sampling suppresses all text overlays")
    live.setHoverVisible(false); live.reset()
    check(live.state == .unavailable && live.overlay.analysis == nil && live.selectedText.isEmpty
          && !live.copyAll(to: pasteboard), "reset discards text, selection and copy actions immediately")

    var notices = [String]()
    let empty = LiveTextController(isSupported: true, analyze: { _ in blankResult })
    empty.onNotice = { notices.append($0) }
    empty.update(image: pixels, delay: 0)
    check(waitForCheck { empty.state == .noText } && empty.host.isHidden && notices.isEmpty,
          "background no-text results stay silent and invisible")
    empty.beginSelection()
    check(notices.count == 1, "explicit no-text requests receive feedback")
    let failed = LiveTextController(isSupported: true, analyze: { _ in throw CocoaError(.fileReadUnknown) })
    failed.onNotice = { notices.append($0) }
    failed.update(image: pixels, delay: 0); failed.beginSelection()
    check(waitForCheck { failed.state == .failed } && failed.host.isHidden && notices.count == 2,
          "analysis failures preserve viewing and report only an explicit request")
    failed.reset(); empty.reset()

    let viewer = ViewerController()
    viewer.asset = ImageAsset(url: URL(fileURLWithPath: "/tmp/live-text.png"), image: NSImage(cgImage: pixels, size: .zero), cgImage: pixels, properties: [:])
    viewer.displayedCG = pixels; viewer.refreshLiveText()
    check(viewer.liveText.state == .analyzing, "committed static raster starts Live Text analysis")
    viewer.resetImageState(preservingPresentation: true)
    check(viewer.liveText.state == .unavailable, "retained loading pixels never retain old selectable text")
    viewer.liveText.update(image: pixels)
    viewer.close()
    check(viewer.liveText.state == .unavailable, "closing a viewer cancels its text analysis")
}
