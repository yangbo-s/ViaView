import AppKit
import SwiftUI
import Sparkle

final class SettingsWindowController: NSWindowController {
    private let tabs: SettingsTabViewController
    init(updater: SPUUpdater) {
        let tabs = SettingsTabViewController(); self.tabs = tabs
        tabs.tabStyle = .toolbar
        func add<V: View>(_ title: String, _ symbol: String, height: CGFloat = 590, _ view: V) {
            let host = NSHostingController(rootView: view); host.title = title
            host.preferredContentSize = NSSize(width: 580, height: height)
            let item = NSTabViewItem(viewController: host)
            item.label = title; item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        add("通用", "gearshape", GeneralSettings())
        add("浏览", "folder", height: 400, BrowsingSettings())
        add("文件类型", "doc.badge.gearshape", FileTypeSettings())
        add("快捷键", "keyboard", ShortcutSettings())
        add("更新", "arrow.triangle.2.circlepath", height: 330, UpdateSettings(updater: updater))
        let window = NSWindow(contentViewController: tabs)
        window.title = "ViaView 设置"; window.setContentSize(NSSize(width: 580, height: 590))
        window.styleMask = [.titled, .closable]; window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
        tabs.sizeWindowToSelectedTab()
    }
    required init?(coder: NSCoder) { fatalError() }
    func showShortcuts() { tabs.selectedTabViewItemIndex = 3 }
}

// Grouped Forms already scroll. Give short pages a compact viewport while
// preserving the tab bar's position and keeping long pages within the screen.
final class SettingsTabViewController: NSTabViewController {
    override func tabView(_ tabView: NSTabView, didSelect tabViewItem: NSTabViewItem?) {
        super.tabView(tabView, didSelect: tabViewItem)
        sizeWindowToSelectedTab()
        view.window?.makeFirstResponder(nil)
    }

    func sizeWindowToSelectedTab() {
        guard let window = view.window,
              tabViewItems.indices.contains(selectedTabViewItemIndex),
              let page = tabViewItems[selectedTabViewItemIndex].viewController,
              let screen = window.screen ?? NSScreen.main else { return }
        window.contentView?.layoutSubtreeIfNeeded()
        let area = screen.visibleFrame.insetBy(dx: 12, dy: 12)
        let titlebarHeight = window.frame.height - window.contentLayoutRect.height
        let height = min(page.preferredContentSize.height + titlebarHeight, area.height)
        let width = min(580, area.width)
        let frame = NSRect(x: max(area.minX, min(window.frame.minX, area.maxX - width)),
                           y: max(area.minY, min(window.frame.maxY - height, area.maxY - height)),
                           width: width, height: height)
        window.setFrame(frame, display: true)
    }
}
