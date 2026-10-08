import AppKit
import SwiftUI

final class SettingsWindowController: NSWindowController {
    private let tabs: NSTabViewController
    init() {
        let tabs = NSTabViewController(); self.tabs = tabs
        tabs.tabStyle = .toolbar
        func add<V: View>(_ title: String, _ symbol: String, _ view: V) {
            let host = NSHostingController(rootView: view); host.title = title
            let item = NSTabViewItem(viewController: host)
            item.label = title; item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: title)
            tabs.addTabViewItem(item)
        }
        add("通用", "gearshape", GeneralSettings())
        add("浏览", "folder", BrowsingSettings())
        add("文件类型", "doc.badge.gearshape", FileTypeSettings())
        add("快捷键", "keyboard", ShortcutSettings())
        let window = NSWindow(contentViewController: tabs)
        window.title = "ViaView 设置"; window.setContentSize(NSSize(width: 580, height: 590))
        window.styleMask = [.titled, .closable]; window.isReleasedWhenClosed = false
        window.center()
        super.init(window: window)
    }
    required init?(coder: NSCoder) { fatalError() }
    func showShortcuts() { tabs.selectedTabViewItemIndex = 3 }
}
