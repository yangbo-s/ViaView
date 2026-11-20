import Foundation

final class FileAccessStore {
    static let shared = FileAccessStore()
    private enum BookmarkKey: String, CaseIterable {
        case folders = "folderBookmarks"
        case files = "recentFileBookmarks"
        case legacy = "bookmarks"
    }
    private var scopes: [URL] = []
    var authorizedFolders: [URL] {
        scopes.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }.sorted { $0.path < $1.path }
    }
    func remove(_ url: URL) {
        scopes.filter { $0 == url }.forEach { $0.stopAccessingSecurityScopedResource() }
        scopes.removeAll { $0 == url }
        for key in BookmarkKey.allCases {
            let saved = bookmarks(for: key)
            let remaining = saved.filter { resolve($0)?.standardizedFileURL.path != url.standardizedFileURL.path }
            if remaining.count != saved.count { UserDefaults.standard.set(remaining, forKey: key.rawValue) }
        }
    }
    init() {
        for key in BookmarkKey.allCases {
            bookmarks(for: key).compactMap(resolve).forEach { retain($0, save: false) }
        }
    }
    func retain(_ url: URL, save: Bool = true) {
        guard !scopes.contains(url) else { return }
        if url.startAccessingSecurityScopedResource() { scopes.append(url) }
        guard save, let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) else { return }
        let isFolder = (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? url.hasDirectoryPath
        // Keep explicit directory grants and older bookmarks outside the recent-file limit.
        let key: BookmarkKey = isFolder ? .folders : .files
        var saved = bookmarks(for: key)
        guard !saved.contains(data) else { return }
        saved.append(data)
        UserDefaults.standard.set(key == .files ? Array(saved.suffix(60)) : saved, forKey: key.rawValue)
    }

    private func bookmarks(for key: BookmarkKey) -> [Data] {
        UserDefaults.standard.array(forKey: key.rawValue) as? [Data] ?? []
    }

    private func resolve(_ data: Data) -> URL? {
        var stale = false
        return try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], bookmarkDataIsStale: &stale)
    }
}
