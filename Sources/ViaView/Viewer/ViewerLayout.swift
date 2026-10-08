import AppKit
import ViewerCore

extension ViewerController {
    func pin(_ child: NSView, to parent: NSView, inset: CGFloat = 0) {
        child.translatesAutoresizingMaskIntoConstraints = false; parent.addSubview(child)
        NSLayoutConstraint.activate([child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: inset), child.trailingAnchor.constraint(equalTo: parent.trailingAnchor, constant: -inset), child.topAnchor.constraint(equalTo: parent.topAnchor, constant: inset), child.bottomAnchor.constraint(equalTo: parent.bottomAnchor, constant: -inset)])
    }
    func buildLayout() {
        pin(stage, to: root)
        buildInspector()
        fileList.onSelect = { [weak self] url in
            guard let self, let index = self.gallery.urls.firstIndex(of: url), index != self.gallery.index else { return }
            self.gallery.select(index); self.loadCurrent()
        }
        fileList.onSort = { [weak self] sort, descending in self?.sort = sort; self?.descending = descending; self?.reorderGallery() }
        tagsController.onError = { [weak self] in self?.showError($0) }
        scroll.contentView = CenteredClipView()
        scroll.contentView.automaticallyAdjustsContentInsets = false
        scroll.contentView.contentInsets = .init()
        scroll.horizontalScrollElasticity = .none; scroll.verticalScrollElasticity = .none
        scroll.hasVerticalScroller = false; scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true; scroll.drawsBackground = false; scroll.allowsMagnification = true
        scroll.automaticallyAdjustsContentInsets = false; scroll.contentInsets = .init(); scroll.scrollerStyle = .overlay
        scroll.minMagnification = 0.001; scroll.maxMagnification = 32
        canvas.imageScaling = .scaleAxesIndependently; canvas.animates = true; canvas.clipsToBounds = true; canvas.setAccessibilityLabel("图片画布")
        scroll.documentView = canvas; pin(scroll, to: stage)
        empty.orientation = .vertical; empty.spacing = 14; empty.alignment = .centerX; empty.detachesHiddenViews = true
        let icon = NSImageView(image: NSImage(systemSymbolName: "photo.on.rectangle", accessibilityDescription: nil) ?? NSImage())
        icon.contentTintColor = .secondaryLabelColor; icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([icon.widthAnchor.constraint(equalToConstant: 48), icon.heightAnchor.constraint(equalToConstant: 42)])
        let openButton = NSButton(title: "打开图片或文件夹…", target: NSApp.delegate, action: #selector(AppDelegate.open(_:))); openButton.bezelStyle = .rounded
        [icon, emptyTitle, emptyDetail, openButton].forEach { empty.addArrangedSubview($0) }
        emptyDetail.maximumNumberOfLines = 3; emptyDetail.lineBreakMode = .byWordWrapping; emptyDetail.alignment = .center
        empty.translatesAutoresizingMaskIntoConstraints = false; stage.addSubview(empty)
        NSLayoutConstraint.activate([empty.centerXAnchor.constraint(equalTo: stage.centerXAnchor), empty.centerYAnchor.constraint(equalTo: stage.centerYAnchor), empty.widthAnchor.constraint(lessThanOrEqualTo: stage.widthAnchor, constant: -64)])
        progress.style = .spinning; progress.controlSize = .small; progress.isDisplayedWhenStopped = false; progress.isHidden = true
        empty.addArrangedSubview(progress)
        pin(glassLayer, to: stage)
        for chrome in [topChrome, bottomChrome] { chrome.translatesAutoresizingMaskIntoConstraints = false; glassLayer.content.addSubview(chrome) }
        buildTopChrome()
        let bottomStack = NSStackView(); bottomStack.spacing = 4; bottomStack.detachesHiddenViews = true
        let specs: [(ToolbarIcon, String, String, Selector)] = [
            (.zoomOut, "缩小 · ⌘－", "out", #selector(zoomOut(_:))),
            (.zoomIn, "放大 · ⌘＋", "in", #selector(zoomIn(_:))),
            (.fit, "适应窗口 · ⌘0", "fit", #selector(fit(_:))),
            (.previous, "上一张", "previous", #selector(previous(_:))),
            (.next, "下一张", "next", #selector(next(_:))),
            (.play, "幻灯片 · 空格", "play", #selector(slideshow(_:))),
            (.rotateRight, "向右旋转 · ⌘R", "rotate", #selector(rotateRight(_:))),
            (.maximize, "全屏", "fullscreen", #selector(fullscreen(_:))) ]
        for (icon, title, key, action) in specs {
            let button = toolbarButton(icon, title, target: self, action: action); buttons[key] = button; bottomStack.addArrangedSubview(button)
            if key == "fit" { bottomStack.addArrangedSubview(zoomLabel) }
            if key == "previous" { bottomStack.addArrangedSubview(countLabel) }
        }
        countLabel.alignment = .center; countLabel.setContentHuggingPriority(.required, for: .horizontal)
        countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 42).isActive = true
        pin(bottomStack, to: bottomFullChrome.content, inset: 10)
        bottomCompactChrome.spacing = 56
        for (icon, title, key, action) in [
            (ToolbarIcon.previous, "上一张", "compactPrevious", #selector(previous(_:))),
            (ToolbarIcon.next, "下一张", "compactNext", #selector(next(_:)))
        ] {
            let glass = GlassChrome(radius: 20)
            let button = toolbarButton(icon, title, target: self, action: action, size: 32)
            buttons[key] = button; pin(button, to: glass.content, inset: 4)
            bottomCompactChrome.addArrangedSubview(glass)
        }
        let bottomLayouts = NSStackView(views: [bottomFullChrome, bottomCompactChrome])
        bottomLayouts.detachesHiddenViews = true; bottomLayouts.spacing = 0
        pin(bottomLayouts, to: bottomChrome)
        NSLayoutConstraint.activate([bottomChrome.centerXAnchor.constraint(equalTo: glassLayer.content.centerXAnchor), bottomChrome.bottomAnchor.constraint(equalTo: glassLayer.content.bottomAnchor, constant: -12)])
        colorFeedback.isHidden = true; colorFeedback.drawsBackground = true; colorFeedback.backgroundColor = .windowBackgroundColor
        colorFeedback.alignment = .center; colorFeedback.wantsLayer = true; colorFeedback.layer?.cornerRadius = 8; colorFeedback.layer?.masksToBounds = true
        colorFeedback.translatesAutoresizingMaskIntoConstraints = false; stage.addSubview(colorFeedback)
        NSLayoutConstraint.activate([colorFeedback.centerXAnchor.constraint(equalTo: stage.centerXAnchor), colorFeedback.bottomAnchor.constraint(equalTo: stage.bottomAnchor, constant: -88), colorFeedback.widthAnchor.constraint(equalToConstant: 164), colorFeedback.heightAnchor.constraint(equalToConstant: 30)])
    }
    func refreshAppearance(fullScreen override: Bool? = nil) {
        let fullScreen = override ?? (window?.styleMask.contains(.fullScreen) == true)
        let dark = fullScreen || UserDefaults.standard.bool(forKey: "darkCanvas")
        let background = fullScreen ? NSColor.black : NSColor(white: dark ? 0.10 : 0.93, alpha: 1)
        stage.wantsLayer = true; stage.layer?.backgroundColor = background.cgColor
        window?.backgroundColor = background
        stage.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        window?.appearance = stage.appearance
    }
}
