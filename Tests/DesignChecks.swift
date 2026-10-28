import AppKit
import Sparkle
import ViewerCore

func runDesignChecks(_ check: (Bool, String) -> Void) {
    let defaults = UserDefaults.standard
    let savedWrap = defaults.object(forKey: "wrap")
    defer {
        if let savedWrap { defaults.set(savedWrap, forKey: "wrap") }
        else { defaults.removeObject(forKey: "wrap") }
    }
    let viewer = ViewerController()
    defer { viewer.close() }
    let urls = (1...3).map { URL(fileURLWithPath: "/tmp/viaview-design-\($0).png") }
    func validated(_ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: "", action: action, keyEquivalent: "")
        item.isEnabled = viewer.validateMenuItem(item)
        return item
    }
    defaults.set(false, forKey: "wrap")
    check(!viewer.canNavigate(-1) && !viewer.canNavigate(1), "empty gallery has no navigation")
    viewer.gallery = Gallery(urls: [urls[0]])
    check(!viewer.canNavigate(-1) && !viewer.canNavigate(1), "single image has no navigation")
    viewer.gallery = Gallery(urls: urls)
    for index in urls.indices {
        viewer.gallery.select(index)
        viewer.updateUI()
        check(viewer.buttons["previous"]?.isEnabled == (index > 0)
              && viewer.buttons["next"]?.isEnabled == (index < 2),
              "shared navigation matches non-looping boundary at \(index)")
        check(validated(#selector(ViewerController.previous(_:))).isEnabled == (index > 0)
              && validated(#selector(ViewerController.next(_:))).isEnabled == (index < 2),
              "menu navigation matches non-looping boundary at \(index)")
    }
    viewer.isLoading = true
    check(!validated(#selector(ViewerController.next(_:))).isEnabled && validated(#selector(ViewerController.previous(_:))).isEnabled,
          "navigation respects boundaries while the next image loads")
    viewer.isLoading = false
    defaults.set(true, forKey: "wrap")
    viewer.updateUI()
    check(viewer.buttons["next"]?.isEnabled == true
          && validated(#selector(ViewerController.next(_:))).isEnabled, "looping restores forward navigation at the end")

    let listAction = #selector(ViewerController.toggleFileList(_:))
    check(validated(listAction).title == "显示文件列表", "closed list offers Show")
    viewer.toggleFileList(nil)
    check(validated(listAction).title == "隐藏文件列表", "open list updates its command state")
    viewer.fileListPanel?.close()
    viewer.updateCommandControls()
    check(validated(listAction).title == "显示文件列表", "native panel close restores Show")
    viewer.toggleInspector(.information)
    check(validated(#selector(ViewerController.toggleInfo(_:))).title == "隐藏图片信息"
          && validated(#selector(ViewerController.toggleAdjustments(_:))).title == "显示图像调整", "inspector menus distinguish the active mode")
    viewer.toggleInspector(.adjustments)
    check(validated(#selector(ViewerController.toggleInfo(_:))).title == "显示图片信息"
          && validated(#selector(ViewerController.toggleAdjustments(_:))).title == "隐藏图像调整", "switching inspector mode refreshes both actions")
    viewer.slideshow(nil)
    check(validated(#selector(ViewerController.slideshow(_:))).title == "暂停幻灯片", "running slideshow offers Pause")
    viewer.slideshow(nil)
    check(validated(#selector(ViewerController.slideshow(_:))).title == "开始幻灯片", "paused slideshow offers Start")
    viewer.alwaysOnTop(nil)
    check(validated(#selector(ViewerController.alwaysOnTop(_:))).state == .on
          && validated(#selector(ViewerController.alwaysOnTop(_:))).title == "取消窗口置顶", "pin state and action agree")
    viewer.alwaysOnTop(nil)

    func descendants(_ view: NSView) -> [NSView] { [view] + view.subviews.flatMap(descendants) }
    let list = FileListController()
    list.update(urls: urls, selected: urls[1], sort: .name, descending: false)
    let direction = descendants(list.view).first { $0.identifier?.rawValue == "sortDirection" } as! NSButton
    let table = descendants(list.view).compactMap { $0 as? NSTableView }.first!
    check(direction.accessibilityValue() as? String == "升序" && direction.accessibilityLabel() == "切换为降序",
          "sort direction announces current order and next action")
    var requestedDescending: Bool?
    list.onSort = { _, descending in requestedDescending = descending }
    direction.performClick(nil)
    check(requestedDescending == true && direction.accessibilityValue() as? String == "降序"
          && direction.accessibilityLabel() == "切换为升序" && table.selectedRow == 1,
          "reversing order updates feedback immediately without changing selection")
    for files in [[], [urls[0]]] {
        list.update(urls: files, selected: files.first, sort: .name, descending: false)
        check(!direction.isEnabled && descendants(list.view).compactMap { $0 as? NSPopUpButton }.allSatisfy { !$0.isEnabled },
              "sorting is disabled for \(files.count) image(s)")
    }

    let updater = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
    let settings = SettingsWindowController(updater: updater.updater)
    defer { settings.close() }
    let window = settings.window!
    let tabs = window.contentViewController as! SettingsTabViewController
    let original = window.frame
    tabs.selectedTabViewItemIndex = 4
    let compact = window.frame
    check(compact.height < original.height - 200 && abs(compact.maxY - original.maxY) < 1 && compact.width == original.width,
          "update settings shrink while preserving the tab bar and width")
    check(window.firstResponder === window, "switching settings does not preselect an editable control")
    tabs.selectedTabViewItemIndex = 0
    check(abs(window.frame.height - original.height) < 1 && abs(window.frame.maxY - original.maxY) < 1,
          "returning to a long settings page restores its viewport")
    let area = window.screen!.visibleFrame
    window.setFrameOrigin(NSPoint(x: area.maxX - 100, y: area.minY - 100))
    tabs.selectedTabViewItemIndex = 4
    check(NSScreen.screens.contains { $0.visibleFrame.contains(window.frame) }, "settings page changes keep an offscreen window reachable on its destination display")

    let driver = ZoomDriver()
    defer { driver.stop() }
    var applied: [CGFloat] = []
    var reduceMotion = true
    driver.shouldReduceMotion = { reduceMotion }
    driver.apply = { applied.append($0) }
    driver.reset(1)
    driver.aim(2, in: viewer.canvas)
    check(applied == [2] && driver.target == 2, "Reduce Motion applies zoom immediately")
    driver.aim(100, in: viewer.canvas)
    driver.aim(0, in: viewer.canvas)
    check(applied.suffix(2) == [32, 0.001], "Reduce Motion preserves zoom limits")
    reduceMotion = false
    let count = applied.count
    driver.aim(3, in: viewer.canvas)
    check(applied.count == count && abs(driver.target - 3) < 0.000001, "normal zoom retains asynchronous interpolation (calls=\(applied.count)/\(count), target=\(driver.target))")
    reduceMotion = true
    driver.aim(1.5, in: viewer.canvas)
    RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    check(applied.last == 1.5 && driver.target == 1.5, "enabling Reduce Motion cancels in-flight interpolation")
}
