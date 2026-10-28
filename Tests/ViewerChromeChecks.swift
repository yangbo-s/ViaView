import AppKit
import ViewerCore

func runViewerChromeChecks(_ check: (Bool, String) -> Void) {
    let viewer = ViewerController()
    defer { viewer.close() }
    let window = viewer.window!
    window.contentView!.superview!.layoutSubtreeIfNeeded()
    check(ToolbarIcon.allCases.allSatisfy { $0.image.isValid && $0.image.size == NSSize(width: 20, height: 20) },
          "restored Lucide assets retain the original artwork and size")
    check(window.toolbar?.items.isEmpty == true && window.titleVisibility == .hidden && window.titlebarAppearsTransparent,
          "system toolbar contains no image actions and its title stays hidden")
    let image = NSImage(size: NSSize(width: 960, height: 640))
    let urls = [URL(fileURLWithPath: "/tmp/native-chrome-1.png"), URL(fileURLWithPath: "/tmp/native-chrome-2.png")]
    viewer.asset = ImageAsset(url: urls[0], image: image, cgImage: nil, properties: [:])
    viewer.gallery = Gallery(urls: urls)
    viewer.updateUI()
    let previous = viewer.buttons["previous"]!
    let next = viewer.buttons["next"]!
    func labels(in view: NSView) -> [NSTextField] {
        (view as? NSTextField).map { [$0] } ?? view.subviews.flatMap { labels(in: $0) }
    }
    for width: CGFloat in [200, 360, 419, 420, 619, 620, 900] {
        window.setContentSize(NSSize(width: width, height: 420))
        window.contentView!.superview!.layoutSubtreeIfNeeded()
        viewer.layoutChrome(); viewer.setChrome(true)
        viewer.root.layoutSubtreeIfNeeded()
        let navigationRect = viewer.countLabel.convert(viewer.countLabel.bounds, to: viewer.stage)
        let previousRect = previous.convert(previous.bounds, to: viewer.stage)
        let nextRect = next.convert(next.bounds, to: viewer.stage)
        check(viewer.buttons["previous"] === previous && viewer.buttons["next"] === next
              && !viewer.countLabel.isHiddenOrHasHiddenAncestor
              && previousRect.maxX <= navigationRect.minX && navigationRect.maxX <= nextRect.minX,
              "navigation identity, order and page count survive \(Int(width)) pt")
        check(abs(viewer.bottomSurface.bounds.height - ChromeMetrics.height) < 0.1
              && [previous, next].allSatisfy {
                  $0.bounds.size == NSSize(width: ChromeMetrics.buttonSize, height: ChromeMetrics.buttonSize)
                      && $0.image?.size == NSSize(width: ChromeMetrics.iconSize, height: ChromeMetrics.iconSize)
              }
              && viewer.bottomChrome.frame.minX >= ChromeMetrics.edgeInset - 0.1
              && viewer.bottomChrome.frame.maxX <= viewer.stage.bounds.maxX - ChromeMetrics.edgeInset + 0.1
              && Set(viewer.buttons.keys) == ["previous", "next"]
              && labels(in: viewer.bottomChrome) == [viewer.countLabel]
             ,
              "transport keeps one height and only navigation plus page count at \(Int(width)) pt")
    }
    window.setContentSize(NSSize(width: 200, height: 420))
    viewer.countLabel.stringValue = "1234567 / 7654321"
    window.contentView!.superview!.layoutSubtreeIfNeeded(); viewer.layoutChrome(); viewer.root.layoutSubtreeIfNeeded()
    check(viewer.bottomChrome.frame.width <= 176.1 && previous.bounds.width == ChromeMetrics.buttonSize
          && next.bounds.width == ChromeMetrics.buttonSize,
          "a long page count compresses before navigation hit areas")


    let menu = viewer.makeImageContextMenu(for: urls[0])
    let info = menu.items.first { $0.action == #selector(ViewerController.toggleInfo(_:)) }!
    check(info.target === viewer && NSApp.sendAction(info.action!, to: info.target, from: info)
          && viewer.inspectorPanel?.isVisible == true,
          "context menu retains a working image-information action")
    check(viewer.validateMenuItem(info) && info.title == "隐藏图片信息",
          "context menu reflects the open panel state")
    viewer.inspectorPanel?.close()
    check(viewer.validateMenuItem(info) && info.title == "显示图片信息",
          "closing a panel restores its Show action")
    let share = menu.items.first { $0.action == #selector(ViewerController.share(_:)) }!
    viewer.gallery = Gallery()
    check(!viewer.validateMenuItem(share), "share remains disabled without a file")
    viewer.gallery = Gallery(urls: urls)
    check(viewer.validateMenuItem(share), "share becomes available with a file")
    let expectedActions: [Selector] = [#selector(ViewerController.toggleFileList(_:)), #selector(ViewerController.toggleAdjustments(_:)),
        #selector(ViewerController.slideshow(_:)), #selector(ViewerController.fullscreen(_:)), #selector(ViewerController.rotateRight(_:))]
    func commands(in menu: NSMenu) -> [Selector] {
        menu.items.flatMap { item in item.submenu.map(commands(in:)) ?? item.action.map { [$0] } ?? [] }
    }
    check(expectedActions.allSatisfy { commands(in: menu).contains($0) }
          && commands(in: menu).contains(#selector(ViewerController.fit(_:)))
          && commands(in: menu).contains(#selector(ViewerController.zoomIn(_:)))
          && commands(in: menu).contains(#selector(ViewerController.zoomOut(_:))),
          "removed toolbar actions remain available in the context menu")

    let frame = window.frame
    viewer.pointer(NSPoint(x: viewer.stage.bounds.midX, y: viewer.stage.bounds.midY))
    viewer.pointer(NSPoint(x: viewer.stage.bounds.midX, y: viewer.stage.bounds.midY))
    check(!viewer.chromeVisible && viewer.topChrome.isHidden && viewer.bottomChrome.isHidden && viewer.windowButtons.allSatisfy(\.isHidden)
          && window.titleVisibility == .hidden && window.frame == frame,
          "viewing the image hides every overlay and window control without resizing")
    viewer.pointer(NSPoint(x: viewer.stage.bounds.midX, y: 16))
    check(viewer.chromeVisible && !viewer.bottomChrome.isHidden && viewer.topChrome.isHidden && viewer.windowButtons.allSatisfy(\.isHidden),
          "bottom hover restores only the transport")
    viewer.pointer(NSPoint(x: viewer.stage.bounds.midX, y: viewer.stage.bounds.maxY - 10))
    viewer.pointer(NSPoint(x: viewer.stage.bounds.midX, y: viewer.stage.bounds.maxY - 10))
    check(viewer.bottomChrome.isHidden && !viewer.topChrome.isHidden && viewer.windowButtons.allSatisfy { !$0.isHidden },
          "top hover restores the original floating tools and window controls without the bottom bar")
    viewer.pointer(nil); viewer.pointer(nil)
    check(viewer.bottomChrome.isHidden && viewer.topChrome.isHidden && viewer.windowButtons.allSatisfy(\.isHidden),
          "leaving the window removes all viewing overlays")
    viewer.setWindowControls(true)
    if let close = window.standardWindowButton(.closeButton) {
        let location = close.convert(NSPoint(x: close.bounds.midX, y: close.bounds.midY), to: nil)
        let click = NSEvent.mouseEvent(with: .leftMouseDown, location: location, modifierFlags: [], timestamp: 0,
                                      windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)!
        check(viewer.routeViewerEvent(click) === click, "revealed window controls keep AppKit event ownership")
    }
    for width: CGFloat in [399, 400, 479, 480, 579, 580, 749, 750, 809, 810, 900] {
        window.setContentSize(NSSize(width: width, height: 420))
        window.contentView!.superview!.layoutSubtreeIfNeeded(); viewer.layoutChrome()
        viewer.pointer(NSPoint(x: width / 2, y: viewer.stage.bounds.maxY - 30))
        viewer.root.layoutSubtreeIfNeeded()
        let groupsMatch = zip(viewer.toolGroups, [480.0, 580, 750, 810]).allSatisfy { group, threshold in
            group.isHidden == (width < threshold)
        }
        let visibleButtons = viewer.topActions.filter { !$0.isHiddenOrHasHiddenAncestor }
        let buttonsFit = visibleButtons.allSatisfy { button in
            let rect = button.convert(button.bounds, to: viewer.stage)
            return rect.minX >= 0 && rect.maxX <= width + 0.1 && rect.minY >= 0 && rect.maxY <= viewer.stage.bounds.height + 0.1
                && button.bounds.height == ChromeMetrics.buttonSize
                && (button.action == #selector(ViewerController.openEditor(_:)) || button.bounds.width == ChromeMetrics.buttonSize)
                && button.image?.size == NSSize(width: ChromeMetrics.iconSize, height: ChromeMetrics.iconSize)
        }
        let visibleGroups = (viewer.toolGroups + [viewer.compactTools!]).filter { !$0.isHiddenOrHasHiddenAncestor }
        check(groupsMatch && viewer.compactTools?.isHidden == (width < 400 || width >= 480)
              && visibleGroups.allSatisfy { abs($0.bounds.height - ChromeMetrics.height) < 0.1 }
              && buttonsFit && !viewer.topChrome.isHidden,
              "restored top groups fit and fold correctly at \(Int(width)) pt")
    }
    viewer.toggleFileList(nil)
    let listButtons = viewer.topActions.filter { $0.action == #selector(ViewerController.toggleFileList(_:)) }
    check(listButtons.count == 2 && listButtons.allSatisfy { $0.toolTip == "隐藏文件列表 · ⌘B" },
          "both restored list controls share the live panel action")
    viewer.fileListPanel?.close(); viewer.updateCommandControls()
    check(listButtons.allSatisfy { $0.toolTip == "显示文件列表 · ⌘B" },
          "closing the list updates restored top tooltips")
    check(viewer.nameLabel.stringValue == urls[0].lastPathComponent && viewer.nameLabel.toolTip?.contains(urls[0].lastPathComponent) == true,
          "hover filename and tooltip identify the current image")
    // Real Space transitions and Escape are covered by GUI QA.
}
