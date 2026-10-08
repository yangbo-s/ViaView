import AppKit
import ViewerCore

final class TagsPanelController: NSViewController {
    static let didChangeNotification = Notification.Name("ViaViewFinderTagsDidChange")
    static let changedURLKey = "url"

    var onError: ((Error) -> Void)?
    private var url: URL?
    private var tags: [FinderTag] = []
    private let stack = NSStackView()
    private let entry = NSTextField()
    private let document = FlippedDocument()
    private var activation: NSObjectProtocol?
    private var tagChanges: NSObjectProtocol?
    private let order = [6, 7, 5, 2, 4, 3, 1]

    override func loadView() {
        let background = NSVisualEffectView(); background.material = .sidebar; background.blendingMode = .behindWindow; background.state = .active; view = background
        let scroll = NSScrollView(); scroll.drawsBackground = false; scroll.hasVerticalScroller = true; scroll.autohidesScrollers = true; scroll.documentView = document
        scroll.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(scroll)
        NSLayoutConstraint.activate([scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor), scroll.topAnchor.constraint(equalTo: view.topAnchor), scroll.bottomAnchor.constraint(equalTo: view.bottomAnchor)])
        stack.orientation = .vertical; stack.alignment = .leading; stack.spacing = 10; document.addSubview(stack)
        document.translatesAutoresizingMaskIntoConstraints = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            document.widthAnchor.constraint(equalTo: scroll.contentView.widthAnchor),
            stack.leadingAnchor.constraint(equalTo: document.leadingAnchor, constant: 16),
            stack.trailingAnchor.constraint(equalTo: document.trailingAnchor, constant: -16),
            stack.topAnchor.constraint(equalTo: document.topAnchor, constant: 16),
            stack.bottomAnchor.constraint(equalTo: document.bottomAnchor, constant: -16)
        ])
        entry.placeholderString = "添加标签…"; entry.bezelStyle = .roundedBezel; entry.target = self; entry.action = #selector(addTag); entry.setAccessibilityLabel("新标签名称")
        activation = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { [weak self] _ in
            if self?.view.window?.isVisible == true { self?.refresh() }
        }
        tagChanges = NotificationCenter.default.addObserver(forName: Self.didChangeNotification, object: nil, queue: .main) { [weak self] notification in
            guard let self, (notification.object as? TagsPanelController) !== self,
                  let changedURL = notification.userInfo?[Self.changedURLKey] as? URL,
                  self.url == changedURL.standardizedFileURL else { return }
            self.refresh()
        }
        refresh()
    }
    deinit {
        if let activation { NotificationCenter.default.removeObserver(activation) }
        if let tagChanges { NotificationCenter.default.removeObserver(tagChanges) }
    }
    func setURL(_ url: URL?) {
        let url = url?.standardizedFileURL
        let changed = self.url != url; self.url = url
        if changed { entry.stringValue = ""; if isViewLoaded { refresh() } }
    }
    func refresh() {
        guard isViewLoaded else { return }
        for view in stack.arrangedSubviews { stack.removeArrangedSubview(view); view.removeFromSuperview() }
        func add(_ view: NSView) {
            stack.addArrangedSubview(view)
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        }
        let name = label(url?.lastPathComponent ?? "尚未打开图片", size: 12, weight: .semibold); name.toolTip = url?.lastPathComponent; add(name)
        guard let url else { add(label("打开图片后可编辑 Finder 标签。", size: 12, color: .secondaryLabelColor)); layoutContent(); return }
        do { tags = try FinderTags.read(url) }
        catch {
            tags = []
            let message = label("无法读取此文件的标签。", size: 12, color: .secondaryLabelColor)
            message.toolTip = error.localizedDescription; add(message); layoutContent(); return
        }
        if tags.isEmpty { add(label("无标签", size: 12, color: .secondaryLabelColor)) }
        for tag in tags {
            let dot = NSImageView(image: colorIcon(tag.color)); dot.contentTintColor = color(tag.color)
            let remove = symbolButton("xmark", "移除标签：\(tag.name)", target: self, action: #selector(removeTag(_:)), size: 22); remove.identifier = .init(tag.name)
            let title = label(tag.name, size: 13); title.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let row = NSStackView(views: [dot, title, NSView(), remove]); row.spacing = 8; row.alignment = .centerY
            dot.widthAnchor.constraint(equalToConstant: 12).isActive = true; dot.heightAnchor.constraint(equalToConstant: 12).isActive = true; add(row)
        }
        let addButton = NSButton(title: "添加", target: self, action: #selector(addTag)); addButton.bezelStyle = .rounded
        let input = NSStackView(views: [entry, addButton]); input.spacing = 8; add(input)
        add(NSBox.separator())
        for index in order {
            let name = NSWorkspace.shared.fileLabels[index]
            let selected = tags.contains(FinderTag(name: name, color: index))
            let button = NSButton(checkboxWithTitle: name, target: self, action: #selector(toggleColor(_:))); button.tag = index; button.state = selected ? .on : .off
            let dot = NSImageView(image: colorIcon(index)); dot.contentTintColor = color(index)
            dot.widthAnchor.constraint(equalToConstant: 12).isActive = true; dot.heightAnchor.constraint(equalToConstant: 12).isActive = true
            let row = NSStackView(views: [dot, button, NSView()]); row.spacing = 10; row.alignment = .centerY; row.heightAnchor.constraint(equalToConstant: 24).isActive = true; add(row)
        }
        layoutContent()
    }
    private func layoutContent() { view.layoutSubtreeIfNeeded() }
    @objc private func addTag() {
        guard let url else { return }
        do {
            let name = entry.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return }
            // Existing colored tags keep their color when their name is entered again.
            let existing = try FinderTags.read(url).first { $0.name == name }
            try FinderTags.add(existing ?? FinderTag(name: name), to: url)
            entry.stringValue = ""; tagsDidChange(at: url)
        } catch { mutationFailed(error) }
    }
    @objc private func removeTag(_ sender: NSButton) {
        guard let url, let name = sender.identifier?.rawValue else { return }
        do { try FinderTags.remove(name, from: url); tagsDidChange(at: url) }
        catch { mutationFailed(error) }
    }
    @objc private func toggleColor(_ sender: NSButton) {
        sender.enclosingMenuItem?.menu?.cancelTracking()
        guard let url else { return }
        do {
            try FinderTags.toggle(FinderTag(name: NSWorkspace.shared.fileLabels[sender.tag], color: sender.tag), on: url)
            tagsDidChange(at: url)
        } catch { mutationFailed(error) }
    }
    private func tagsDidChange(at url: URL) {
        refresh()
        NotificationCenter.default.post(name: Self.didChangeNotification, object: self, userInfo: [Self.changedURLKey: url.standardizedFileURL])
    }
    private func mutationFailed(_ error: Error) {
        // Native checkboxes toggle before their action. Restore disk state before reporting failure.
        refresh(); onError?(error)
    }
    func menuColorRow() -> NSMenuItem {
        let current: [FinderTag]
        do {
            guard let url else { return unavailableColorRow("尚未打开图片") }
            current = try FinderTags.read(url)
        } catch { return unavailableColorRow("无法读取标签", detail: error.localizedDescription) }
        let item = NSMenuItem(); let row = NSStackView(); row.spacing = 2; row.edgeInsets = NSEdgeInsets(top: 4, left: 12, bottom: 4, right: 12)
        for index in order {
            let name = NSWorkspace.shared.fileLabels[index]; let selected = current.contains(FinderTag(name: name, color: index))
            let button = NSButton(image: NSImage(systemSymbolName: selected ? "checkmark.circle.fill" : "circle.fill", accessibilityDescription: name)!, target: self, action: #selector(toggleColor(_:)))
            button.tag = index; button.isBordered = false; button.contentTintColor = color(index); button.toolTip = (selected ? "移除" : "添加") + " \(name)"; button.setAccessibilityLabel(button.toolTip)
            button.widthAnchor.constraint(equalToConstant: 28).isActive = true; button.heightAnchor.constraint(equalToConstant: 28).isActive = true; row.addArrangedSubview(button)
        }
        row.frame = NSRect(origin: .zero, size: row.fittingSize); item.view = row; return item
    }
    private func unavailableColorRow(_ title: String, detail: String? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false; item.toolTip = detail; return item
    }
    private func color(_ index: Int) -> NSColor { NSWorkspace.shared.fileLabelColors.indices.contains(index) && index > 0 ? NSWorkspace.shared.fileLabelColors[index] : .secondaryLabelColor }
    private func colorIcon(_ index: Int) -> NSImage { NSImage(systemSymbolName: index == 0 ? "tag" : "circle.fill", accessibilityDescription: nil)! }
}

private extension NSBox {
    static func separator() -> NSBox { let box = NSBox(); box.boxType = .separator; return box }
}
