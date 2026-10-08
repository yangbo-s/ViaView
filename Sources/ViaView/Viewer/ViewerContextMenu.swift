import AppKit
import ViewerCore

extension ViewerController {
    func showImageContextMenu(with event: NSEvent) {
        guard let url = gallery.current else { return }
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, _ key: String = "", modifiers: NSEvent.ModifierFlags = .command) {
            menu.addItem(menuItem(title, action, key, modifiers: modifiers, target: self))
        }
        let selected = canvas.selection.width > 1 && canvas.selection.height > 1
        add(selected ? "复制选区" : "复制图片", #selector(copyImage(_:)), "c")
        add("复制文件路径", #selector(copyPath(_:)), "c", modifiers: [.command, .option])
        menu.addItem(.separator())
        add("在 Finder 中显示", #selector(reveal(_:)), "r", modifiers: [.command, .shift])
        if AppSettings.editorURL != nil {
            add("用\(AppSettings.editorName)打开", #selector(openEditor(_:)))
        }
        let openWith = NSMenuItem(title: "打开方式", action: nil, keyEquivalent: "")
        openWith.submenu = applicationsMenu(for: url); menu.addItem(openWith)
        menu.addItem(.separator())
        add("向右旋转", #selector(rotateRight(_:)), "r")
        add("向左旋转", #selector(rotateLeft(_:)), "l")
        menu.addItem(.separator())
        add("适应屏幕", #selector(fit(_:)), "0")
        add("实际大小", #selector(actualSize(_:)), "1")
        menu.addItem(.separator())
        tagsController.setURL(url)
        menu.addItem(tagsController.menuColorRow())
        add("标签…", #selector(editTags(_:)))
        add("取色并复制色号", #selector(pickColor(_:)))
        menu.addItem(.separator())
        add("移到废纸篓", #selector(moveToTrash(_:)), String(UnicodeScalar(NSBackspaceCharacter)!))
        NSMenu.popUpContextMenu(menu, with: event, for: stage)
        refreshChrome()
    }

    private func applicationsMenu(for url: URL) -> NSMenu {
        let menu = NSMenu(title: "打开方式")
        let workspace = NSWorkspace.shared
        let defaultApp = workspace.urlForApplication(toOpen: url)?.standardizedFileURL
        let apps = Set(workspace.urlsForApplications(toOpen: url).map(\.standardizedFileURL)).filter {
            Bundle(url: $0)?.bundleIdentifier != Bundle.main.bundleIdentifier
        }.sorted { left, right in
            if left == defaultApp { return true }
            if right == defaultApp { return false }
            return FileManager.default.displayName(atPath: left.path).localizedStandardCompare(FileManager.default.displayName(atPath: right.path)) == .orderedAscending
        }
        var seen = Set<String>()
        for app in apps {
            let identity = Bundle(url: app)?.bundleIdentifier ?? app.path
            guard seen.insert(identity).inserted else { continue }
            let name = (FileManager.default.displayName(atPath: app.path) as NSString).deletingPathExtension
            let item = menuItem(name + (app == defaultApp ? "（默认）" : ""), #selector(openWithApplication(_:)), target: self)
            item.representedObject = app
            let icon = workspace.icon(forFile: app.path); icon.size = NSSize(width: 16, height: 16); item.image = icon
            menu.addItem(item)
        }
        if apps.isEmpty { menu.addItem(menuItem("没有可用的应用", nil)) }
        return menu
    }

    @objc func openWithApplication(_ sender: NSMenuItem) {
        guard let url = gallery.current, let app = sender.representedObject as? URL else { return }
        NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            if let error { DispatchQueue.main.async { self?.showError(error) } }
        }
    }

    @objc func openEditor(_ sender: Any?) {
        guard let app = AppSettings.editorURL else { return }
        let item = NSMenuItem(); item.representedObject = app
        openWithApplication(item)
    }

    @objc func moveToTrash(_ sender: Any?) {
        guard let url = gallery.current, !trashInProgress, !exportInProgress else { return }
        if !edits.isIdentity {
            let alert = NSAlert()
            alert.messageText = "将“\(url.lastPathComponent)”移到废纸篓？"
            alert.informativeText = "这张图片有尚未导出的调整。移走后，当前调整将丢失；原文件可从废纸篓恢复。"
            alert.addButton(withTitle: "取消"); alert.addButton(withTitle: "移到废纸篓")
            guard alert.runModal() == .alertSecondButtonReturn else { return }
        }
        trashInProgress = true
        timer?.invalidate(); timer = nil; updateSlideshowButton()
        NSWorkspace.shared.recycle([url]) { [weak self] moved, error in
            DispatchQueue.main.async {
                guard let self else { return }
                self.trashInProgress = false
                guard moved.keys.contains(where: { $0.standardizedFileURL == url.standardizedFileURL }) else {
                    self.showError(error ?? CocoaError(.fileWriteUnknown)); return
                }
                let viewers = (NSApp.delegate as? AppDelegate)?.viewers ?? [self]
                viewers.forEach { $0.imageWasRecycled(url) }
            }
        }
    }

    func excludingRecycledFiles(_ urls: [URL]) -> [URL] {
        urls.filter { !recycledURLs.contains($0.standardizedFileURL) || FileManager.default.fileExists(atPath: $0.path) }
    }

    func imageWasRecycled(_ url: URL) {
        // Record before inspecting the gallery: an in-flight scan may not have applied yet.
        recycledURLs.insert(url.standardizedFileURL)
        guard gallery.urls.contains(url) else { return }
        let wasCurrent = gallery.current == url
        gallery.remove(url); fileList.invalidate(url)
        if wasCurrent {
            if gallery.current != nil { loadCurrent() }
            else {
                loadSerial += 1; resetImageState()
                showMessage("没有可浏览的图片", detail: "图片已移到废纸篓，可以从 Finder 恢复或打开其他图片。", loading: false)
                updateUI()
            }
        } else { updateUI() }
    }
}
