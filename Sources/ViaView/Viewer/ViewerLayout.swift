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
        pin(liveText.host, to: stage); configureLiveText()
        pin(glassLayer, to: stage)
        topChrome.translatesAutoresizingMaskIntoConstraints = false
        glassLayer.content.addSubview(topChrome)
        bottomChrome.translatesAutoresizingMaskIntoConstraints = false
        glassLayer.content.addSubview(bottomChrome)
        buildTopChrome()
        func action(_ icon: ToolbarIcon, _ title: String, _ key: String, _ selector: Selector) -> NSButton {
            let button = toolbarButton(icon, title, target: self, action: selector)
            buttons[key] = button; return button
        }
        let navigation = NSStackView(views: [
            action(.previous, "上一张", "previous", #selector(previous(_:))), countLabel,
            action(.next, "下一张", "next", #selector(next(_:)))
        ])
        navigation.spacing = ChromeMetrics.spacing
        navigation.alignment = .centerY
        countLabel.font = .monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        countLabel.alignment = .center
        countLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        countLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 32).isActive = true
        pin(navigation, to: bottomSurface.content, inset: ChromeMetrics.inset)
        pin(bottomSurface, to: bottomChrome)
        NSLayoutConstraint.activate([
            bottomChrome.centerXAnchor.constraint(equalTo: glassLayer.content.centerXAnchor),
            bottomChrome.bottomAnchor.constraint(equalTo: glassLayer.content.bottomAnchor, constant: -ChromeMetrics.edgeInset),
            bottomChrome.leadingAnchor.constraint(greaterThanOrEqualTo: glassLayer.content.leadingAnchor, constant: ChromeMetrics.edgeInset),
            bottomChrome.trailingAnchor.constraint(lessThanOrEqualTo: glassLayer.content.trailingAnchor, constant: -ChromeMetrics.edgeInset),
            bottomChrome.heightAnchor.constraint(equalToConstant: ChromeMetrics.height)
        ])
        colorFeedback.isHidden = true; colorFeedback.drawsBackground = true; colorFeedback.backgroundColor = .windowBackgroundColor
        colorFeedback.alignment = .center; colorFeedback.wantsLayer = true; colorFeedback.layer?.cornerRadius = 8; colorFeedback.layer?.masksToBounds = true
        colorFeedback.translatesAutoresizingMaskIntoConstraints = false; stage.addSubview(colorFeedback)
        NSLayoutConstraint.activate([colorFeedback.centerXAnchor.constraint(equalTo: stage.centerXAnchor), colorFeedback.bottomAnchor.constraint(equalTo: stage.bottomAnchor, constant: -88), colorFeedback.widthAnchor.constraint(equalToConstant: 164), colorFeedback.heightAnchor.constraint(equalToConstant: 30)])
    }
    func refreshAppearance(fullScreen override: Bool? = nil) {
        usesFullScreenAppearance = override ?? (window?.styleMask.contains(.fullScreen) == true)
        let appearance = usesFullScreenAppearance ? NSAppearance(named: .darkAqua) : nil
        window?.appearance = appearance
        stage.appearance = appearance
        updateCanvasAppearance()
    }
    var usesDarkAppearance: Bool { stage.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
    func updateCanvasAppearance() {
        let background = usesFullScreenAppearance ? NSColor.black : NSColor(white: usesDarkAppearance ? 0.10 : 0.93, alpha: 1)
        stage.wantsLayer = true; stage.layer?.backgroundColor = background.cgColor
        window?.backgroundColor = background
        canvas.needsDisplay = true
        if windowControlsVisible { updateTitleContrast() }
        else { updateCommandControls() }
    }
}
