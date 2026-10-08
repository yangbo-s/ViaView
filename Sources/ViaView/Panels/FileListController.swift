import AppKit
import ViewerCore

private final class FileGridItem: NSCollectionViewItem {
    var representedURL: URL?
    override func loadView() {
        view = NSView(); view.wantsLayer = true; view.layer?.cornerRadius = 8
        let image = NSImageView(); image.imageScaling = .scaleProportionallyUpOrDown
        let name = label("", size: 11); name.alignment = .center
        imageView = image; textField = name
        for v in [image, name] { v.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(v) }
        NSLayoutConstraint.activate([image.topAnchor.constraint(equalTo: view.topAnchor, constant: 6), image.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6), image.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6), image.heightAnchor.constraint(equalToConstant: 66), name.topAnchor.constraint(equalTo: image.bottomAnchor, constant: 6), name.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 4), name.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -4)])
    }
    override var isSelected: Bool { didSet { view.layer?.backgroundColor = (isSelected ? NSColor.selectedContentBackgroundColor.withAlphaComponent(0.30) : .clear).cgColor } }
}

private struct ThumbnailVersion: Equatable {
    let modified: Date?
    let size: Int?

    init(_ url: URL) {
        // Scan URLs can carry cached resource values; inspect a fresh URL each time.
        let values = try? URL(fileURLWithPath: url.path).resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
        modified = values?.contentModificationDate
        size = values?.fileSize
    }
}

private final class CachedThumbnail {
    let image: NSImage
    let version: ThumbnailVersion
    init(image: NSImage, version: ThumbnailVersion) { self.image = image; self.version = version }
}

private final class ThumbnailRequest {
    let version: ThumbnailVersion
    let operation = BlockOperation()
    var completions: [(NSImage?) -> Void]
    init(version: ThumbnailVersion, completion: @escaping (NSImage?) -> Void) {
        self.version = version; completions = [completion]
    }
}

final class FileListController: NSViewController, NSTableViewDataSource, NSTableViewDelegate, NSCollectionViewDataSource, NSCollectionViewDelegate {
    var onSelect: ((URL) -> Void)?
    var onSort: ((GallerySort, Bool) -> Void)?
    private var urls: [URL] = []
    private var selected: URL?
    private var syncing = false
    private let table = NSTableView()
    private let grid = NSCollectionView()
    private let listScroll = NSScrollView()
    private let gridScroll = NSScrollView()
    private let count = label("0 张图片", size: 12, color: .secondaryLabelColor)
    private let empty = label("打开文件夹以浏览图片", size: 12, color: .secondaryLabelColor)
    private let mode = NSSegmentedControl(images: [NSImage(systemSymbolName: "list.bullet", accessibilityDescription: "列表")!, NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "网格")!], trackingMode: .selectOne, target: nil, action: nil)
    private let sort = NSPopUpButton()
    private var descending = false
    private let cache = NSCache<NSURL, CachedThumbnail>()
    private var versions: [URL: ThumbnailVersion] = [:]
    private var requests: [URL: ThumbnailRequest] = [:]
    private let queue: OperationQueue = { let q = OperationQueue(); q.maxConcurrentOperationCount = 2; q.qualityOfService = .utility; return q }()

    override func loadView() {
        let background = NSVisualEffectView(); background.material = .sidebar; background.blendingMode = .behindWindow; background.state = .active; view = background
        cache.countLimit = 240; cache.totalCostLimit = 16 * 1024 * 1024
        mode.selectedSegment = UserDefaults.standard.bool(forKey: "fileListGrid") ? 1 : 0
        mode.target = self; mode.action = #selector(changeListMode); mode.segmentStyle = .separated
        mode.setToolTip("列表", forSegment: 0); mode.setToolTip("网格", forSegment: 1); mode.setAccessibilityLabel("文件列表显示方式")
        let spacer = NSView(); spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [count, spacer, mode]); header.spacing = 8; header.alignment = .centerY
        table.addTableColumn(NSTableColumn(identifier: .init("file"))); table.headerView = nil; table.rowHeight = 30; table.intercellSpacing = .zero
        table.style = .sourceList; table.backgroundColor = .clear; table.dataSource = self; table.delegate = self; table.setAccessibilityLabel("文件列表")
        listScroll.documentView = table
        let layout = NSCollectionViewFlowLayout(); layout.itemSize = NSSize(width: 84, height: 100); layout.minimumInteritemSpacing = 4; layout.minimumLineSpacing = 8; layout.sectionInset = NSEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        grid.collectionViewLayout = layout; grid.isSelectable = true; grid.allowsMultipleSelection = false; grid.backgroundColors = [.clear]
        grid.register(FileGridItem.self, forItemWithIdentifier: .init("file")); grid.dataSource = self; grid.delegate = self; grid.setAccessibilityLabel("缩略图网格")
        gridScroll.documentView = grid
        for scroll in [listScroll, gridScroll] { scroll.hasVerticalScroller = true; scroll.drawsBackground = false; scroll.borderType = .noBorder; scroll.autohidesScrollers = true }
        sort.addItems(withTitles: GallerySort.allCases.map(\.rawValue)); sort.target = self; sort.action = #selector(changeSort); sort.controlSize = .small; sort.setAccessibilityLabel("文件排序")
        let reverse = symbolButton("arrow.up.arrow.down", "切换升序 / 降序", target: self, action: #selector(reverseSort), size: 24)
        let footer = NSStackView(views: [sort, NSView(), reverse]); footer.spacing = 8
        for v in [header, listScroll, gridScroll, footer, empty] { v.translatesAutoresizingMaskIntoConstraints = false; view.addSubview(v) }
        NSLayoutConstraint.activate([header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 14), header.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -14), header.topAnchor.constraint(equalTo: view.topAnchor, constant: 10), header.heightAnchor.constraint(equalToConstant: 28), footer.leadingAnchor.constraint(equalTo: header.leadingAnchor), footer.trailingAnchor.constraint(equalTo: header.trailingAnchor), footer.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -8), footer.heightAnchor.constraint(equalToConstant: 24), empty.centerXAnchor.constraint(equalTo: view.centerXAnchor), empty.centerYAnchor.constraint(equalTo: view.centerYAnchor)])
        for scroll in [listScroll, gridScroll] { NSLayoutConstraint.activate([scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8), scroll.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 6), scroll.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -6), scroll.bottomAnchor.constraint(equalTo: footer.topAnchor, constant: -8)]) }
        applyMode()
    }
    deinit { queue.cancelAllOperations() }

    func update(urls: [URL], selected: URL?, sort: GallerySort, descending: Bool) {
        loadViewIfNeeded()
        let changed = self.urls != urls, selectionChanged = self.selected != selected
        self.urls = urls; self.selected = selected; self.descending = descending
        self.sort.selectItem(withTitle: sort.rawValue)
        count.stringValue = "\(urls.count) 张图片"; empty.isHidden = !urls.isEmpty
        if changed {
            let retained = Set(urls)
            for url in Array(requests.keys) where !retained.contains(url) { cancelThumbnailRequest(url) }
            versions = versions.filter { retained.contains($0.key) }
            withSelectionSync { table.reloadData(); grid.reloadData() }
        } else {
            var changedRows = IndexSet()
            for index in visibleRows() {
                let url = urls[index], version = ThumbnailVersion(url)
                if let previous = versions[url], previous != version {
                    invalidate(url); changedRows.insert(index)
                }
                versions[url] = version
            }
            reloadThumbnails(at: changedRows)
        }
        if changed || selectionChanged { synchronizeSelection(scrollToSelected: true) }
    }

    func invalidate(_ url: URL) {
        cache.removeObject(forKey: url as NSURL); versions.removeValue(forKey: url)
        cancelThumbnailRequest(url)
    }

    func clearThumbnails() {
        cache.removeAllObjects(); versions.removeAll()
        queue.cancelAllOperations(); requests.removeAll()
        guard isViewLoaded else { return }
        withSelectionSync { table.reloadData(); grid.reloadData() }
        synchronizeSelection(scrollToSelected: false)
    }

    private func cancelThumbnailRequest(_ url: URL) { requests.removeValue(forKey: url)?.operation.cancel() }

    private func visibleRows() -> IndexSet {
        if !gridScroll.isHidden {
            return IndexSet(grid.indexPathsForVisibleItems().map(\.item).filter { urls.indices.contains($0) })
        }
        let range = table.rows(in: table.visibleRect)
        guard range.location != NSNotFound, range.location < urls.count else { return [] }
        return IndexSet(integersIn: range.location..<min(urls.count, NSMaxRange(range)))
    }

    private func reloadThumbnails(at rows: IndexSet) {
        guard !rows.isEmpty else { return }
        withSelectionSync {
            table.reloadData(forRowIndexes: rows, columnIndexes: IndexSet(integer: 0))
            grid.reloadItems(at: Set(rows.map { IndexPath(item: $0, section: 0) }))
        }
        synchronizeSelection(scrollToSelected: false)
    }

    private func withSelectionSync(_ body: () -> Void) {
        let previous = syncing; syncing = true
        defer { syncing = previous }
        body()
    }

    private func synchronizeSelection(scrollToSelected: Bool) {
        withSelectionSync {
            if let selected, let index = urls.firstIndex(of: selected) {
                table.selectRowIndexes(IndexSet(integer: index), byExtendingSelection: false)
                let path = IndexPath(item: index, section: 0); grid.selectionIndexPaths = [path]
                if scrollToSelected {
                    table.scrollRowToVisible(index)
                    if !gridScroll.isHidden { grid.scrollToItems(at: [path], scrollPosition: .nearestVerticalEdge) }
                }
            } else { table.deselectAll(nil); grid.selectionIndexPaths = [] }
        }
    }

    @objc private func changeListMode() {
        UserDefaults.standard.set(mode.selectedSegment == 1, forKey: "fileListGrid")
        applyMode()
        let currentSort = GallerySort.allCases[sort.indexOfSelectedItem]
        update(urls: urls, selected: selected, sort: currentSort, descending: descending)
        synchronizeSelection(scrollToSelected: true)
    }
    private func applyMode() { listScroll.isHidden = mode.selectedSegment == 1; gridScroll.isHidden = !listScroll.isHidden }
    @objc private func changeSort() { onSort?(GallerySort.allCases[sort.indexOfSelectedItem], descending) }
    @objc private func reverseSort() { descending.toggle(); changeSort() }
    func numberOfRows(in tableView: NSTableView) -> Int { urls.count }
    func tableViewSelectionDidChange(_ notification: Notification) { guard !syncing, urls.indices.contains(table.selectedRow) else { return }; onSelect?(urls[table.selectedRow]) }
    func tableView(_ tableView: NSTableView, viewFor tableColumn: NSTableColumn?, row: Int) -> NSView? {
        guard urls.indices.contains(row) else { return nil }; let url = urls[row]
        let cell = NSTableCellView(); let image = NSImageView(); image.imageScaling = .scaleProportionallyUpOrDown; let text = label(url.lastPathComponent, size: 13)
        cell.imageView = image; cell.textField = text; cell.setAccessibilityLabel(url.lastPathComponent); cell.toolTip = url.lastPathComponent
        for v in [image, text] { v.translatesAutoresizingMaskIntoConstraints = false; cell.addSubview(v) }
        NSLayoutConstraint.activate([image.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 8), image.centerYAnchor.constraint(equalTo: cell.centerYAnchor), image.widthAnchor.constraint(equalToConstant: 24), image.heightAnchor.constraint(equalToConstant: 24), text.leadingAnchor.constraint(equalTo: image.trailingAnchor, constant: 8), text.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -8), text.centerYAnchor.constraint(equalTo: cell.centerYAnchor)])
        thumbnail(url) { [weak image] in image?.image = $0 }; return cell
    }
    func collectionView(_ collectionView: NSCollectionView, numberOfItemsInSection section: Int) -> Int { urls.count }
    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: .init("file"), for: indexPath) as! FileGridItem
        let url = urls[indexPath.item]; item.representedURL = url; item.textField?.stringValue = url.lastPathComponent; item.view.toolTip = url.lastPathComponent
        item.view.setAccessibilityLabel(url.lastPathComponent); item.imageView?.image = nil
        thumbnail(url) { [weak item] image in if item?.representedURL == url { item?.imageView?.image = image } }
        return item
    }
    func collectionView(_ collectionView: NSCollectionView, didSelectItemsAt indexPaths: Set<IndexPath>) {
        guard !syncing, let index = indexPaths.first?.item, urls.indices.contains(index) else { return }; onSelect?(urls[index])
    }
    private func thumbnail(_ url: URL, completion: @escaping (NSImage?) -> Void) {
        let version = ThumbnailVersion(url)
        if let previous = versions[url], previous != version { invalidate(url) }
        versions[url] = version
        if let cached = cache.object(forKey: url as NSURL), cached.version == version {
            completion(cached.image); return
        }
        let fallback = NSWorkspace.shared.icon(forFile: url.path)
        completion(fallback)
        if let request = requests[url], request.version == version {
            request.completions.append(completion); return
        }
        cancelThumbnailRequest(url)
        let request = ThumbnailRequest(version: version, completion: completion)
        requests[url] = request
        request.operation.addExecutionBlock { [weak self, weak request] in
            guard let request, !request.operation.isCancelled else { return }
            let image = ImagePipeline.thumbnail(url)
            DispatchQueue.main.async { [weak self, weak request] in
                guard let self, let request, self.requests[url] === request, !request.operation.isCancelled else { return }
                self.requests.removeValue(forKey: url)
                guard ThumbnailVersion(url) == request.version else {
                    self.invalidate(url)
                    if let index = self.urls.firstIndex(of: url) { self.reloadThumbnails(at: IndexSet(integer: index)) }
                    return
                }
                let result = image ?? fallback
                self.cache.setObject(CachedThumbnail(image: result, version: request.version), forKey: url as NSURL, cost: 112 * 112 * 4)
                request.completions.forEach { $0(result) }
            }
        }
        queue.addOperation(request.operation)
    }
}
