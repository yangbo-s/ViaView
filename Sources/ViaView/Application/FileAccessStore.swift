import Foundation

final class FileAccessStore {
    static let shared = FileAccessStore()
    private var scopes: [URL] = []
    var authorizedFolders: [URL] {
        scopes.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }.sorted { $0.path < $1.path }
    }
    func remove(_ url: URL) {
        scopes.filter { $0 == url }.forEach { $0.stopAccessingSecurityScopedResource() }
        scopes.removeAll { $0 == url }
        let saved = UserDefaults.standard.array(forKey: "bookmarks") as? [Data] ?? []
        UserDefaults.standard.set(saved.filter { data in
            var stale = false
            return (try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], bookmarkDataIsStale: &stale)) != url
        }, forKey: "bookmarks")
    }
    init() {
        for data in UserDefaults.standard.array(forKey: "bookmarks") as? [Data] ?? [] {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope], bookmarkDataIsStale: &stale) { retain(url, save: false) }
        }
    }
    func retain(_ url: URL, save: Bool = true) {
        guard !scopes.contains(url) else { return }
        if url.startAccessingSecurityScopedResource() { scopes.append(url) }
        if save, let data = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) {
            var bookmarks = UserDefaults.standard.array(forKey: "bookmarks") as? [Data] ?? []
            if !bookmarks.contains(data) { bookmarks.append(data); UserDefaults.standard.set(Array(bookmarks.suffix(60)), forKey: "bookmarks") }
        }
    }
}
