import AppKit

struct IconError: Error, CustomStringConvertible {
    let description: String
}

func loadPage(_ url: URL) throws -> CGPDFPage {
    guard let document = CGPDFDocument(url as CFURL), let page = document.page(at: 1) else {
        throw IconError(description: "无法读取图标矢量资源：\(url.path)")
    }
    return page
}

func generateIconset(at folder: URL) throws {
    // PDF copies of the approved SVG masters keep ordinary builds dependency-free.
    let resources = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/AppIcon")
    let standard = try loadPage(resources.appendingPathComponent("lighthouse.pdf"))
    let small = try loadPage(resources.appendingPathComponent("lighthouse-small.pdf"))
    let sizes = [
        (points: 16, scale: 1, name: "icon_16x16.png"),
        (points: 16, scale: 2, name: "icon_16x16@2x.png"),
        (points: 32, scale: 1, name: "icon_32x32.png"),
        (points: 32, scale: 2, name: "icon_32x32@2x.png"),
        (points: 128, scale: 1, name: "icon_128x128.png"),
        (points: 128, scale: 2, name: "icon_128x128@2x.png"),
        (points: 256, scale: 1, name: "icon_256x256.png"),
        (points: 256, scale: 2, name: "icon_256x256@2x.png"),
        (points: 512, scale: 1, name: "icon_512x512.png"),
        (points: 512, scale: 2, name: "icon_512x512@2x.png")
    ]
    guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
        throw IconError(description: "无法创建图标 sRGB 色彩空间")
    }
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for size in sizes {
        let pixels = size.points * size.scale
        guard let context = CGContext(data: nil, width: pixels, height: pixels,
                                      bitsPerComponent: 8, bytesPerRow: 0, space: colorSpace,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw IconError(description: "无法创建图标画布：\(size.name)")
        }
        // Choose by logical size so the 16-point Retina icon keeps the same silhouette.
        let page = size.points == 16 ? small : standard
        let bounds = CGRect(x: 0, y: 0, width: pixels, height: pixels)
        context.concatenate(page.getDrawingTransform(.mediaBox, rect: bounds,
                                                     rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        guard let image = context.makeImage(),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            throw IconError(description: "无法编码图标：\(size.name)")
        }
        try png.write(to: folder.appendingPathComponent(size.name), options: .atomic)
    }
}

do {
    guard CommandLine.arguments.count == 2 else {
        throw IconError(description: "用法：swift scripts/Icon.swift <输出目录.iconset>")
    }
    try generateIconset(at: URL(fileURLWithPath: CommandLine.arguments[1]))
} catch {
    FileHandle.standardError.write(Data("图标生成失败：\(error)\n".utf8))
    exit(1)
}
