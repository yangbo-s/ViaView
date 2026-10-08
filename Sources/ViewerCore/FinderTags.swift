import AppKit
import Darwin

public struct FinderTag: Equatable {
    public let name: String
    public let color: Int
    public init(name: String, color: Int = 0) { self.name = name; self.color = color }
}

public enum FinderTags {
    // Finder persists multiple independent tag colors here; tagNamesKey alone drops colors.
    private static let attribute = "com.apple.metadata:_kMDItemUserTags"
    public static func read(_ url: URL) throws -> [FinderTag] {
        let count = getxattr(url.path, attribute, nil, 0, 0, 0)
        if count < 0 {
            guard errno == ENOATTR else { throw posixError(url) }
            let values = try URL(fileURLWithPath: url.path).resourceValues(forKeys: [.tagNamesKey, .labelNumberKey])
            return includingLegacyLabel((values.tagNames ?? []).map { FinderTag(name: $0) }, number: values.labelNumber)
        }
        var data = Data(count: count)
        let actual = data.withUnsafeMutableBytes { getxattr(url.path, attribute, $0.baseAddress, count, 0, 0) }
        guard actual >= 0 else { throw posixError(url) }
        data.count = actual
        guard let entries = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String] else { throw CocoaError(.fileReadCorruptFile) }
        let tags = try entries.map { entry in
            guard let separator = entry.lastIndex(of: "\n") else { return FinderTag(name: entry) }
            guard let color = Int(entry[entry.index(after: separator)...]), (0...7).contains(color) else { throw CocoaError(.fileReadCorruptFile) }
            return FinderTag(name: String(entry[..<separator]), color: color)
        }
        let number = try URL(fileURLWithPath: url.path).resourceValues(forKeys: [.labelNumberKey]).labelNumber
        return includingLegacyLabel(tags, number: number)
    }
    private static func includingLegacyLabel(_ tags: [FinderTag], number: Int?) -> [FinderTag] {
        guard let number, (1...7).contains(number), !tags.contains(where: { $0.color == number }) else { return tags }
        var result = tags
        let name = NSWorkspace.shared.fileLabels[number]
        if let index = result.firstIndex(where: { $0.name == name }) { result[index] = FinderTag(name: name, color: number) }
        else { result.append(FinderTag(name: name, color: number)) }
        return result
    }
    public static func add(_ tag: FinderTag, to url: URL) throws {
        let clean = try validated(tag)
        var tags = try read(url)
        if let index = tags.firstIndex(where: { $0.name == clean.name }) { tags[index] = clean }
        else { tags.append(clean) }
        try write(tags, to: url)
    }
    public static func remove(_ name: String, from url: URL) throws {
        try write(read(url).filter { $0.name != name }, to: url)
    }
    public static func toggle(_ tag: FinderTag, on url: URL) throws {
        let tags = try read(url)
        if tags.contains(where: { $0 == tag }) { try remove(tag.name, from: url) }
        else { try add(tag, to: url) }
    }
    private static func validated(_ tag: FinderTag) throws -> FinderTag {
        let name = tag.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.utf8.count <= 255, !name.contains(where: { $0.isNewline || $0 == "\0" }), (0...7).contains(tag.color) else {
            throw NSError(domain: "ViaView.Tags", code: 1, userInfo: [NSLocalizedDescriptionKey: "标签名称不能为空、换行或超过 255 字节。"])
        }
        return FinderTag(name: name, color: tag.color)
    }
    private static func write(_ tags: [FinderTag], to url: URL) throws {
        let entries = try tags.map { tag -> String in let t = try validated(tag); return "\(t.name)\n\(t.color)" }
        let data = try PropertyListSerialization.data(fromPropertyList: entries, format: .binary, options: 0)
        let file = NSURL(fileURLWithPath: url.path)
        let previousLabel = try URL(fileURLWithPath: url.path).resourceValues(forKeys: [.labelNumberKey]).labelNumber ?? 0
        // Modern tags carry their own colors. A parallel legacy label makes Finder
        // synthesize another localized name (e.g. Red beside 红色). Preserve any old
        // label in read(), then clear only that field before writing the full tag set.
        try FinderTagWriteTransaction.perform(
            clearLegacyLabel: { try file.setResourceValue(0, forKey: .labelNumberKey) },
            writeTags: {
                let result = data.withUnsafeBytes { setxattr(url.path, attribute, $0.baseAddress, data.count, 0, 0) }
                guard result == 0 else { throw posixError(url) }
            },
            restoreLegacyLabel: { try file.setResourceValue(previousLabel, forKey: .labelNumberKey) }
        )
    }
    private static func posixError(_ url: URL) -> Error {
        NSError(domain: NSPOSIXErrorDomain, code: Int(errno), userInfo: [NSFilePathErrorKey: url.path])
    }
}

// SPI keeps filesystem failure injection out of the application's ordinary API.
@_spi(Testing) public enum FinderTagWriteTransaction {
    public static let restorationErrorKey = "ViaView.Tags.RestorationError"

    public static func perform(clearLegacyLabel: () throws -> Void, writeTags: () throws -> Void, restoreLegacyLabel: () throws -> Void) throws {
        try clearLegacyLabel()
        do {
            try writeTags()
        } catch {
            let writeError = error
            do {
                try restoreLegacyLabel()
            } catch {
                let original = writeError as NSError
                var details = original.userInfo
                details[NSUnderlyingErrorKey] = writeError
                details[restorationErrorKey] = error
                details[NSLocalizedRecoverySuggestionErrorKey] = "旧标签颜色也未能恢复，请重新读取并检查 Finder 标签。恢复失败：\(error.localizedDescription)"
                throw NSError(domain: original.domain, code: original.code, userInfo: details)
            }
            throw writeError
        }
    }
}
