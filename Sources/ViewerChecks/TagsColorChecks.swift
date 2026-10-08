import AppKit
import Darwin
@_spi(Testing) import ViewerCore

func runTagsColorChecks(_ runner: CheckRunner, fixtures: CheckFixtures) {
    let check = runner.check
    let folder = fixtures.folder
    let source = fixtures.source
    let sourceBytes = fixtures.sourceBytes

    check("Finder 多色标签保存为系统可读名称且不改图像内容") {
        let url = try fixtures.taggedImage("multicolor-tags")
        try FinderTags.add(FinderTag(name: "Red", color: 6), to: url)
        try FinderTags.add(FinderTag(name: "Blue", color: 4), to: url)
        let tags = try FinderTags.read(url)
        let names = try URL(fileURLWithPath: url.path).resourceValues(forKeys: [.tagNamesKey]).tagNames ?? []
        let bytes = try Data(contentsOf: url)
        return tags == [FinderTag(name: "Red", color: 6), FinderTag(name: "Blue", color: 4)] && Set(names) == ["Red", "Blue"] && bytes == sourceBytes
    }
    check("Finder 自定义标签增删保留其他标签颜色，重复不新增") {
        let url = try fixtures.taggedImage("custom-tags", tags: [FinderTag(name: "Red", color: 6), FinderTag(name: "Blue", color: 4)])
        try FinderTags.add(FinderTag(name: "自定义"), to: url)
        try FinderTags.add(FinderTag(name: "自定义"), to: url)
        try FinderTags.remove("Red", from: url)
        let tags = try FinderTags.read(url)
        return tags == [FinderTag(name: "Blue", color: 4), FinderTag(name: "自定义")]
    }
    check("Finder 颜色再次点击移除，未知标签删除不影响文件") {
        let url = try fixtures.taggedImage("toggle-tags", tags: [FinderTag(name: "Blue", color: 4), FinderTag(name: "自定义")])
        try FinderTags.toggle(FinderTag(name: "Blue", color: 4), on: url)
        try FinderTags.remove("不存在", from: url)
        return try FinderTags.read(url) == [FinderTag(name: "自定义")]
    }
    check("Finder 非法标签与缺失文件失败而非假成功") {
        let url = try fixtures.taggedImage("invalid-tags", tags: [FinderTag(name: "自定义")])
        for name in ["", "a\nb", String(repeating: "x", count: 256)] {
            do { try FinderTags.add(FinderTag(name: name), to: url); return false } catch {}
        }
        do { try FinderTags.add(FinderTag(name: "x"), to: folder.appendingPathComponent("missing")); return false } catch {}
        return try FinderTags.read(url) == [FinderTag(name: "自定义")]
    }
    check("Finder 损坏元数据拒绝覆盖") {
        let url = folder.appendingPathComponent("corrupt-tags.png"); try sourceBytes.write(to: url)
        let invalid = Data("invalid".utf8)
        let result = invalid.withUnsafeBytes { setxattr(url.path, "com.apple.metadata:_kMDItemUserTags", $0.baseAddress, invalid.count, 0, 0) }
        guard result == 0 else { return false }
        do { try FinderTags.add(FinderTag(name: "x"), to: url); return false } catch {}
        var bytes = [UInt8](repeating: 0, count: invalid.count)
        let count = getxattr(url.path, "com.apple.metadata:_kMDItemUserTags", &bytes, bytes.count, 0, 0)
        return count == invalid.count && Data(bytes) == invalid
    }
    check("取色输出标准大写 sRGB HEX，包含黑白边界") {
        ColorHex.string(from: NSColor(srgbRed: 0.2, green: 0.4, blue: 0.6, alpha: 1)) == "#336699" && ColorHex.string(from: .black) == "#000000" && ColorHex.string(from: .white) == "#FFFFFF"
    }
    check("取色确认复制到剪贴板，取消保留原内容") {
        let board = NSPasteboard.withUniqueName(); defer { board.releaseGlobally() }
        board.setString("keep", forType: .string)
        guard ColorHex.copy(nil, to: board) == nil, board.string(forType: .string) == "keep" else { return false }
        return ColorHex.copy(NSColor(srgbRed: 1, green: 0, blue: 0.5, alpha: 1), to: board) == "#FF0080" && board.string(forType: .string) == "#FF0080"
    }
    check("Finder 跨语言彩色标签不会合成额外默认名称") {
        let url = folder.appendingPathComponent("localized-tags.png"); try sourceBytes.write(to: url)
        try FinderTags.add(FinderTag(name: "红色", color: 6), to: url)
        try FinderTags.add(FinderTag(name: "蓝色", color: 4), to: url)
        let values = try URL(fileURLWithPath: url.path).resourceValues(forKeys: [.tagNamesKey, .labelNumberKey])
        let tags = try FinderTags.read(url)
        return Set(values.tagNames ?? []) == ["红色", "蓝色"] && values.labelNumber == 0 && tags.count == 2
    }
    check("Finder 旧式标签迁移后保留颜色且可删除") {
        let url = folder.appendingPathComponent("legacy-label.png"); try sourceBytes.write(to: url)
        try NSURL(fileURLWithPath: url.path).setResourceValue(6, forKey: .labelNumberKey)
        let old = try FinderTags.read(url)
        guard let red = old.first(where: { $0.color == 6 }) else { return false }
        try FinderTags.add(FinderTag(name: "Keep"), to: url)
        let migrated = try FinderTags.read(url)
        guard migrated.contains(red), migrated.contains(FinderTag(name: "Keep")) else { return false }
        try FinderTags.remove(red.name, from: url)
        let remaining = try FinderTags.read(url)
        let values = try URL(fileURLWithPath: url.path).resourceValues(forKeys: [.labelNumberKey])
        return remaining == [FinderTag(name: "Keep")] && values.labelNumber == 0
    }
    check("Finder 写入成功不回滚旧标签") {
        var phases: [String] = []
        try FinderTagWriteTransaction.perform(
            clearLegacyLabel: { phases.append("clear") },
            writeTags: { phases.append("write") },
            restoreLegacyLabel: { phases.append("restore") })
        return phases == ["clear", "write"]
    }
    check("Finder 清除旧标签失败时不继续写入或回滚") {
        let expected = NSError(domain: NSPOSIXErrorDomain, code: Int(EACCES))
        var phases: [String] = []
        do {
            try FinderTagWriteTransaction.perform(
                clearLegacyLabel: { phases.append("clear"); throw expected },
                writeTags: { phases.append("write") },
                restoreLegacyLabel: { phases.append("restore") })
            return false
        } catch {
            return (error as NSError) === expected && phases == ["clear"]
        }
    }
    check("Finder 写入失败且回滚成功仍返回最初写入错误") {
        let expected = NSError(domain: NSPOSIXErrorDomain, code: Int(EIO))
        var phases: [String] = []
        do {
            try FinderTagWriteTransaction.perform(
                clearLegacyLabel: { phases.append("clear") },
                writeTags: { phases.append("write"); throw expected },
                restoreLegacyLabel: { phases.append("restore") })
            return false
        } catch {
            return (error as NSError) === expected && phases == ["clear", "write", "restore"]
        }
    }
    check("Finder 写入与回滚均失败保留主错误并附带恢复错误") {
        let primary = NSError(domain: NSPOSIXErrorDomain, code: Int(EIO), userInfo: [NSFilePathErrorKey: source.path])
        let restore = NSError(domain: NSPOSIXErrorDomain, code: Int(EPERM))
        var phases: [String] = []
        do {
            try FinderTagWriteTransaction.perform(
                clearLegacyLabel: { phases.append("clear") },
                writeTags: { phases.append("write"); throw primary },
                restoreLegacyLabel: { phases.append("restore"); throw restore })
            return false
        } catch {
            let result = error as NSError
            return result.domain == primary.domain && result.code == primary.code
                && result.userInfo[NSFilePathErrorKey] as? String == source.path
                && (result.userInfo[NSUnderlyingErrorKey] as? NSError) === primary
                && (result.userInfo[FinderTagWriteTransaction.restorationErrorKey] as? NSError) === restore
                && result.localizedRecoverySuggestion?.contains("恢复失败") == true
                && phases == ["clear", "write", "restore"]
        }
    }
}
