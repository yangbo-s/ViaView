import Foundation
import ViewerCore

func runGalleryChecks(_ runner: CheckRunner, fixtures: CheckFixtures) {
    let check = runner.check
    let folder = fixtures.folder
    let source = fixtures.source

    check("自然排序、隐藏文件和伪装为图片的目录") { try Gallery.scan(folder).map(\.lastPathComponent) == ["image1.png", "image2.png", "image10.png"] }
    check("倒序") { try Gallery.scan(folder, descending: true).map(\.lastPathComponent) == ["image10.png", "image2.png", "image1.png"] }
    check("空目录") { let p = folder.appendingPathComponent("empty"); try FileManager.default.createDirectory(at: p, withIntermediateDirectories: false); return try Gallery.scan(p).isEmpty }
    check("缺失目录报告错误") { do { _ = try Gallery.scan(folder.appendingPathComponent("missing")); return false } catch { return true } }
    check("空列表安全导航") { var g = Gallery(); return g.move(1, wrap: true) == nil && g.move(-1, wrap: false) == nil }
    check("循环与非循环边界") { var g = Gallery(urls: try Gallery.scan(folder)); g.move(-1, wrap: true); guard g.index == 2 else { return false }; g.move(1, wrap: false); guard g.index == 2 else { return false }; g.move(1, wrap: true); return g.index == 0 }
    check("重复 URL 去重并保留选择") { let other = folder.appendingPathComponent("image2.png"); let g = Gallery(urls: [source, source, other], selected: other); return g.urls.count == 2 && g.index == 1 }
    check("移走当前图选择下一张、末尾回退、最后一张清空") {
        let urls = ["a.png", "b.png", "c.png"].map { folder.appendingPathComponent($0) }
        var g = Gallery(urls: urls, selected: urls[1])
        g.remove(urls[1]); guard g.current == urls[2] else { return false }
        g.remove(urls[2]); guard g.current == urls[0] else { return false }
        g.remove(urls[0]); return g.current == nil && g.urls.isEmpty && g.move(1, wrap: true) == nil
    }
    check("异步移走其他图保持当前选择，未知路径不改变列表") {
        let urls = ["a.png", "b.png", "c.png"].map { folder.appendingPathComponent($0) }
        var g = Gallery(urls: urls, selected: urls[2])
        g.remove(urls[0]); guard g.current == urls[2] && g.index == 1 else { return false }
        g.remove(folder.appendingPathComponent("missing.png")); return g.current == urls[2] && g.urls.count == 2
    }
    check("跨文件夹选择按自然名称排序且不扩展相邻图片") {
        let files = try selectionFixture(in: folder)
        let input = [files.image10, files.image1, files.image2]
        let sorted = Gallery.ordered(input, by: .name)
        return sorted == [files.image1, files.image2, files.image10]
            && Set(sorted) == Set(input)
            && !sorted.contains(files.neighborA) && !sorted.contains(files.neighborB)
    }
    check("排序重建图库时保留用户选中的跨文件夹 URL") {
        let files = try selectionFixture(in: folder)
        var gallery = Gallery(urls: [files.image10, files.image1, files.image2], selected: files.image10)
        let selected = gallery.current
        gallery = Gallery(urls: Gallery.ordered(gallery.urls, by: .name), selected: selected)
        guard gallery.current == files.image10, gallery.index == 2 else { return false }
        gallery = Gallery(urls: Gallery.ordered(gallery.urls, by: .name, descending: true), selected: gallery.current)
        return gallery.current == files.image10 && gallery.index == 0 && gallery.urls.count == 3
    }
    check("选择集合支持真实文件大小排序与名称及大小降序") {
        let files = try selectionFixture(in: folder)
        let input = [files.image1, files.image10, files.image2]
        return Gallery.ordered(input, by: .size) == [files.image2, files.image1, files.image10]
            && Gallery.ordered(input, by: .size, descending: true) == [files.image10, files.image1, files.image2]
            && Gallery.ordered(input, by: .name, descending: true) == [files.image10, files.image2, files.image1]
    }
    check("跨文件夹同名同大小文件使用路径稳定排序") {
        let root = folder.appendingPathComponent("ties-" + UUID().uuidString)
        let folder2 = root.appendingPathComponent("folder2"), folder10 = root.appendingPathComponent("folder10")
        try FileManager.default.createDirectory(at: folder2, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: folder10, withIntermediateDirectories: true)
        let first = folder2.appendingPathComponent("same.png"), last = folder10.appendingPathComponent("same.png")
        try Data(repeating: 0, count: 16).write(to: first)
        try Data(repeating: 0, count: 16).write(to: last)
        for input in [[last, first], [first, last]] {
            for sort in [GallerySort.name, .size] {
                guard Gallery.ordered(input, by: sort) == [first, last],
                    Gallery.ordered(input, by: sort, descending: true) == [last, first] else { return false }
            }
        }
        return true
    }
    check("选择中的文件元数据不可读时所有排序仍保留成员") {
        let files = try selectionFixture(in: folder)
        let missing = files.image1.deletingLastPathComponent().appendingPathComponent("missing.png")
        do { _ = try missing.resourceValues(forKeys: [.fileSizeKey]); return false } catch {}
        let input = [files.image10, missing, files.image2]
        for sort in GallerySort.allCases {
            for descending in [false, true] {
                let ordered = Gallery.ordered(input, by: sort, descending: descending)
                guard ordered.count == input.count, Set(ordered) == Set(input),
                    ordered.filter({ $0 == missing }).count == 1 else { return false }
            }
        }
        return true
    }
}

private struct SelectionFixture {
    let image1: URL
    let image2: URL
    let image10: URL
    let neighborA: URL
    let neighborB: URL
}

private func selectionFixture(in folder: URL) throws -> SelectionFixture {
    let root = folder.appendingPathComponent("selection-" + UUID().uuidString)
    let folderA = root.appendingPathComponent("A"), folderB = root.appendingPathComponent("B")
    try FileManager.default.createDirectory(at: folderA, withIntermediateDirectories: true)
    try FileManager.default.createDirectory(at: folderB, withIntermediateDirectories: true)
    let result = SelectionFixture(
        image1: folderA.appendingPathComponent("image1.png"),
        image2: folderB.appendingPathComponent("image2.png"),
        image10: folderA.appendingPathComponent("image10.png"),
        neighborA: folderA.appendingPathComponent("image0.png"),
        neighborB: folderB.appendingPathComponent("image100.png"))
    // These checks exercise filesystem selection and metadata, not image decoding.
    for (url, size) in [(result.image1, 30), (result.image2, 20), (result.image10, 40), (result.neighborA, 10), (result.neighborB, 50)] {
        try Data(repeating: 0, count: size).write(to: url)
    }
    return result
}
