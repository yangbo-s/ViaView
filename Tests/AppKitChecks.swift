import AppKit
import ViewerCore

@main enum AppKitChecks {
    static func main() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        AppSettings.register()
        if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--benchmark" {
            runOpeningBenchmark(URL(fileURLWithPath: CommandLine.arguments[2])); return
        }
        var failures = 0
        var checks = 0
        func check(_ condition: Bool, _ name: String) {
            checks += 1
            if !condition { failures += 1 }
            print("\(condition ? "PASS" : "FAIL") \(name)")
        }
        let viewer = ViewerController()
        viewer.window!.contentView!.superview!.layoutSubtreeIfNeeded()
        viewer.windowDidUpdate(Notification(name: NSWindow.didUpdateNotification, object: viewer.window))
        check(!viewer.topChrome.isHidden && viewer.bottomChrome.isHidden && viewer.progress.isHidden, "empty window shows its aligned titlebar without inactive transport or spinner space")
        let size = NSSize(width: 641, height: 641)
        let image = NSImage(size: size)
        viewer.asset = ImageAsset(url: URL(fileURLWithPath: "/tmp/viaview-check.png"), image: image, cgImage: nil, properties: [:])
        viewer.scroll.isHidden = false
        viewer.canvas.image = image
        viewer.canvas.frame = NSRect(origin: .zero, size: size)
        viewer.root.layoutSubtreeIfNeeded()
        viewer.prepareImageWindow()
        var maximumOffset: CGFloat = 0
        for step in 0..<180 {
            let scale = step < 90 ? 0.5 + Double(step) / 60 : 2 - Double(step - 90) / 60
            viewer.applyZoom(scale)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.001))
            let frame = viewer.canvas.convert(viewer.canvas.bounds, to: viewer.stage)
            maximumOffset = max(maximumOffset, abs(frame.midX - viewer.stage.bounds.midX), abs(frame.midY - viewer.stage.bounds.midY))
        }
        check(maximumOffset < 0.6, "continuous zoom across window limits stays centered (\(maximumOffset) pt)")
        viewer.applyZoom(3, centerImage: true)
        let clip = viewer.scroll.contentView
        clip.scroll(to: NSPoint(x: 100, y: 150))
        let before = viewer.canvas.convert(clip.bounds, from: clip)
        viewer.applyZoom(3.2)
        let after = viewer.canvas.convert(clip.bounds, from: clip)
        check(abs(before.midX - after.midX) < 0.6 && abs(before.midY - after.midY) < 0.6, "zoom preserves a panned detail while larger than viewport")
        viewer.applyZoom(0.25)
        let small = viewer.canvas.convert(viewer.canvas.bounds, to: viewer.stage)
        check(abs(small.midX - viewer.stage.bounds.midX) < 0.6 && abs(small.midY - viewer.stage.bounds.midY) < 0.6, "zooming below fit recenters a panned image")
        let isolated = CenteredClipView(frame: NSRect(x: 0, y: 0, width: 400, height: 400))
        let document = NSView(frame: NSRect(x: 20, y: 80, width: 200, height: 200))
        isolated.documentView = document
        document.frame.origin = NSPoint(x: 20, y: 80)
        let constrained = isolated.constrainBoundsRect(NSRect(x: 900, y: 900, width: 400, height: 400))
        check(abs(constrained.midX - document.frame.midX) < 0.01 && abs(constrained.midY - document.frame.midY) < 0.01, "centering honors actual document origin")
        for code: UInt16 in [53, 51, 117] {
            let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: code)!
            check(isFullScreenExitKey(event), "fullscreen exit recognizes key \(code)")
            check(!viewer.handleFullScreenExit(event), "ordinary window does not consume key \(code)")
        }
        let modifiedDelete = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .command, timestamp: 0, windowNumber: 0, context: nil, characters: "", charactersIgnoringModifiers: "", isARepeat: false, keyCode: 51)!
        check(!isFullScreenExitKey(modifiedDelete), "modified Delete retains its existing shortcut")
        for (width, compact, full) in [(360.0, false, false), (440, true, false), (600, false, true)] {
            viewer.stage.frame.size.width = width
            viewer.layoutChrome()
            check(viewer.compactTools?.isHidden == !compact && viewer.toolGroups[0].isHidden == !full, "toolbar groups at \(Int(width)) pt")
        }
        let fullScreenNotification = Notification(name: NSWindow.willEnterFullScreenNotification, object: viewer.window)
        viewer.windowWillEnterFullScreen(fullScreenNotification)
        check(viewer.window!.contentAspectRatio == .zero && viewer.window!.contentMaxSize.width > viewer.screenArea.width && viewer.window!.contentMaxSize.height > viewer.screenArea.height, "fullscreen releases image-shaped window constraints")
        viewer.windowDidFailToEnterFullScreen(viewer.window!)
        check(!viewer.transitioningFullScreen && viewer.window!.contentAspectRatio == size && viewer.window!.toolbar!.isVisible, "cancelled fullscreen restores window constraints and toolbar")
        viewer.refreshAppearance(fullScreen: true)
        check(viewer.window!.backgroundColor == .black && viewer.stage.layer!.backgroundColor == NSColor.black.cgColor, "fullscreen background is pure black")
        viewer.refreshAppearance(fullScreen: false)
        check(viewer.window!.backgroundColor != .black, "leaving fullscreen restores the windowed canvas")
        for width in [360.0, 440, 860] {
            viewer.window!.setContentSize(NSSize(width: width, height: width))
            viewer.window!.contentView!.superview!.layoutSubtreeIfNeeded()
            viewer.windowDidUpdate(Notification(name: NSWindow.didUpdateNotification, object: viewer.window))
            viewer.root.layoutSubtreeIfNeeded()
            let native = viewer.windowButtons[0]
            let nativeCenter = viewer.stage.convert(NSPoint(x: native.bounds.midX, y: native.bounds.midY), from: native).y
            let actionCenter = viewer.moreButton.convert(viewer.moreButton.bounds, to: viewer.stage).midY
            let titleCenter = viewer.nameLabel.convert(viewer.nameLabel.alignmentRect(forFrame: viewer.nameLabel.bounds), to: viewer.stage).midY
            check(abs(nativeCenter - actionCenter) < 0.6 && abs(titleCenter - actionCenter) < 0.6, "title, toolbar and native controls share a center at \(Int(width)) pt (\(nativeCenter), \(actionCenter), \(titleCenter))")
        }
        let panel = NSPanel(contentRect: NSRect(x: viewer.screenArea.minX, y: viewer.screenArea.minY, width: 320, height: 220), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.contentView = viewer.inspector
        viewer.inspectorPanel = panel
        viewer.inspector.clear()
        for index in 0..<30 { viewer.inspector.add(inspectorRow("字段", value: "Long camera metadata row \(index)")) }
        viewer.layoutInspector()
        let area = panel.screen?.visibleFrame ?? viewer.screenArea
        check(area.contains(panel.frame), "growing inspector stays within screen with footer reachable")
        check(viewer.inspector.preferredHeight > panel.contentView!.bounds.height, "long inspector content scrolls inside the capped window")
        let tags = TagsPanelController()
        tags.view.frame = NSRect(x: 0, y: 0, width: 280, height: 400)
        let tagsScroll = tags.view.subviews.compactMap { $0 as? NSScrollView }.first!
        tagsScroll.scrollerStyle = .legacy
        tagsScroll.autohidesScrollers = false
        tags.view.layoutSubtreeIfNeeded()
        let tagsDocument = tagsScroll.documentView!
        let tagsStack = tagsDocument.subviews.compactMap { $0 as? NSStackView }.first!
        check(abs(tagsDocument.bounds.width - tagsScroll.contentView.bounds.width) < 0.1 && abs(tagsStack.frame.minX - 16) < 0.1 && abs(tagsDocument.bounds.width - tagsStack.frame.maxX - 16) < 0.1, "tags keep equal 16 pt insets with an occupied scrollbar")
        panel.close()
        viewer.window?.close()
        runLoadingChecks(check)
        runAsyncLoadingChecks(check)
        runFileTypeSettingsChecks(check)
        runThemeSettingsChecks(check)
        print("AppKit: \(checks - failures) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
