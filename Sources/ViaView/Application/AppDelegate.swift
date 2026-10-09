import AppKit
import ViewerCore

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate, NSMenuItemValidation {
    var viewers: [ViewerController] = []
    weak var lastActiveViewer: ViewerController?
    var recentMenu: NSMenu!
    var openPanel: NSOpenPanel?
    var settingsController: SettingsWindowController?
    var settingsObserver: NSObjectProtocol?
    private var settingsRefreshScheduled = false
    func applicationDidFinishLaunching(_ notification: Notification) {
        _ = FileAccessStore.shared
        configureMenus()
        applySettings()
        settingsObserver = NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: UserDefaults.standard, queue: .main) { [weak self] _ in self?.scheduleSettingsRefresh() }
        if viewers.isEmpty, UserDefaults.standard.bool(forKey: "restoreWindows") {
            let paths = UserDefaults.standard.stringArray(forKey: "openImagePaths") ?? []
            for path in paths.prefix(20) where FileManager.default.isReadableFile(atPath: path) {
                let viewer = newViewer(); viewer.openURLs([URL(fileURLWithPath: path)]); viewer.showWindow(nil)
            }
        }
        if viewers.isEmpty { newViewer().showWindow(nil) }
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationDidBecomeActive(_ notification: Notification) {
        for viewer in viewers where viewer.fileListPanel?.isVisible == true {
            viewer.fileList.update(urls: viewer.gallery.urls, selected: viewer.gallery.current, sort: viewer.sort, descending: viewer.descending)
        }
    }
    private func scheduleSettingsRefresh() {
        guard !settingsRefreshScheduled else { return }
        settingsRefreshScheduled = true
        // AppKit can register defaults while laying out native controls. Never
        // synchronously re-enter their (SwiftUI-backed) layout from that notification.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.settingsRefreshScheduled = false
            self.applySettings()
        }
    }
    @discardableResult func newViewer() -> ViewerController {
        let viewer = ViewerController()
        viewer.onClose = { [weak self, weak viewer] in self?.viewers.removeAll { $0 === viewer }; self?.saveSession() }
        viewers.append(viewer); return viewer
    }
    var activeViewer: ViewerController? {
        if let panel = NSApp.keyWindow as? ViewerToolPanel, let owner = panel.owner { return owner }
        if let viewer = NSApp.keyWindow?.windowController as? ViewerController { return viewer }
        if let viewer = NSApp.mainWindow?.windowController as? ViewerController { return viewer }
        if let lastActiveViewer, viewers.contains(where: { $0 === lastActiveViewer }) { return lastActiveViewer }
        return viewers.last
    }
    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let viewer = viewerForOpening()
        viewer.openURLs(filenames.map { URL(fileURLWithPath: $0) }); viewer.showWindow(nil)
        sender.reply(toOpenOrPrint: .success)
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { (viewers.last ?? newViewer()).showWindow(nil) }; return true
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { UserDefaults.standard.bool(forKey: "quitLastWindow") }
    func applicationWillTerminate(_ notification: Notification) { saveSession() }
    @objc func open(_ sender: Any?) {
        guard openPanel == nil else { openPanel?.makeKeyAndOrderFront(nil); return }
        let viewer = viewerForOpening(); viewer.showWindow(nil)
        guard let window = viewer.window else { return }
        let panel = NSOpenPanel(); panel.canChooseDirectories = true; panel.canChooseFiles = true
        panel.allowsMultipleSelection = true; panel.prompt = "打开"; panel.message = "选择图片或文件夹"
        openPanel = panel
        panel.beginSheetModal(for: window) { [weak self, weak viewer] response in
            self?.openPanel = nil
            if response == .OK { viewer?.openURLs(panel.urls) }
        }
    }
    @objc func newWindow(_ sender: Any?) { newViewer().showWindow(nil) }
    @objc func openRecent(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        let viewer = viewerForOpening(); viewer.openURLs([url]); viewer.showWindow(nil)
    }
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard menu === recentMenu else { return }
        menu.removeAllItems()
        for url in NSDocumentController.shared.recentDocumentURLs.prefix(12) {
            let item = menuItem(url.lastPathComponent, #selector(openRecent(_:)), target: self)
            item.representedObject = url; menu.addItem(item)
        }
        if menu.items.isEmpty { menu.addItem(withTitle: "尚无最近项目", action: nil, keyEquivalent: "") }
    }
    @objc func about(_ sender: Any?) {
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "ViaView", .applicationVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "", .credits: NSAttributedString(string: "原生看图，自由扩展。\nSwift · AppKit · 本地图像处理")])
    }
    @objc func clearCache(_ sender: Any?) { clearImageCaches() }
    func clearImageCaches() {
        ImagePipeline.shared.clear()
        viewers.forEach { $0.fileList.clearThumbnails() }
    }
    @objc func copyContent(_ sender: Any?) {
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView { text.copy(sender) }
        else { activeViewer?.copyImage(sender) }
    }
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        guard item.action == #selector(copyContent(_:)) else { return true }
        if let text = NSApp.keyWindow?.firstResponder as? NSTextView {
            item.title = "复制"; return text.selectedRange().length > 0
        }
        item.title = "复制图片 / 选区"
        return activeViewer?.displayedCG != nil && activeViewer?.editPending == false
    }
    @objc func shortcuts(_ sender: Any?) {
        preferences(sender); settingsController?.showShortcuts()
    }
    @objc func preferences(_ sender: Any?) {
        if settingsController == nil { settingsController = SettingsWindowController() }
        settingsController?.showWindow(nil); settingsController?.window?.makeKeyAndOrderFront(nil)
    }

}
