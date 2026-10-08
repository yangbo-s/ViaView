import Foundation

public enum GallerySort: String, CaseIterable {
    case name = "名称", modified = "修改时间", created = "创建时间", size = "文件大小"
}

public struct Gallery {
    public static let supportedExtensions: Set<String> = ["jpg", "jpeg", "png", "gif", "apng", "tif", "tiff", "bmp", "webp", "heic", "heif", "avif", "ico", "icns", "psd", "tga", "svg", "pdf", "dng", "cr2", "cr3", "nef", "arw", "raf", "orf", "rw2", "pef", "srw"]
    public private(set) var urls: [URL]
    public private(set) var index: Int
    public var current: URL? { urls.indices.contains(index) ? urls[index] : nil }
    public init(urls: [URL] = [], selected: URL? = nil) {
        var seen = Set<URL>()
        let unique = urls.map { $0.standardizedFileURL }.filter { seen.insert($0).inserted }
        self.urls = unique
        self.index = selected.flatMap { unique.firstIndex(of: $0.standardizedFileURL) } ?? 0
    }
    public mutating func select(_ index: Int) {
        if urls.indices.contains(index) { self.index = index }
    }
    public mutating func remove(_ url: URL) {
        let selected = current
        guard let removed = urls.firstIndex(of: url.standardizedFileURL) else { return }
        urls.remove(at: removed)
        if let selected, let retained = urls.firstIndex(of: selected) { index = retained }
        else { index = min(removed, max(0, urls.count - 1)) }
    }
    @discardableResult public mutating func move(_ delta: Int, wrap: Bool) -> URL? {
        guard !urls.isEmpty else { return nil }
        let target = index + delta
        index = wrap ? ((target % urls.count) + urls.count) % urls.count : min(max(target, 0), urls.count - 1)
        return current
    }
    public static func accepts(_ url: URL) -> Bool { supportedExtensions.contains(url.pathExtension.lowercased()) }
    public static func scan(_ folder: URL, sort: GallerySort = .name, descending: Bool = false) throws -> [URL] {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .contentModificationDateKey, .creationDateKey, .fileSizeKey]
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: Array(keys), options: [.skipsHiddenFiles])
        let items = files.compactMap { url -> (URL, URLResourceValues)? in
            guard accepts(url), let values = try? url.resourceValues(forKeys: keys), values.isRegularFile == true else { return nil }
            return (url, values)
        }
        return ordered(items.map(\.0), by: sort, descending: descending)
    }

    /// Sort an existing selection without expanding it to a directory or writing files.
    public static func ordered(_ urls: [URL], by sort: GallerySort, descending: Bool = false) -> [URL] {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .creationDateKey, .fileSizeKey]
        let items = urls.map { ($0, (try? URL(fileURLWithPath: $0.path).resourceValues(forKeys: keys)) ?? URLResourceValues()) }
        return items.sorted { a, b in
            let comparison: ComparisonResult
            switch sort {
            case .name: comparison = a.0.lastPathComponent.localizedStandardCompare(b.0.lastPathComponent)
            case .modified: comparison = (a.1.contentModificationDate ?? .distantPast).compare(b.1.contentModificationDate ?? .distantPast)
            case .created: comparison = (a.1.creationDate ?? .distantPast).compare(b.1.creationDate ?? .distantPast)
            case .size:
                let x = a.1.fileSize ?? 0, y = b.1.fileSize ?? 0
                comparison = x == y ? .orderedSame : (x < y ? .orderedAscending : .orderedDescending)
            }
            var result = comparison == .orderedSame ? a.0.lastPathComponent.localizedStandardCompare(b.0.lastPathComponent) : comparison
            if result == .orderedSame { result = a.0.path.localizedStandardCompare(b.0.path) }
            return descending ? result == .orderedDescending : result == .orderedAscending
        }.map(\.0)
    }
}
