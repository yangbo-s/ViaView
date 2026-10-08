import AppKit
import ImageIO
import UniformTypeIdentifiers
@_spi(Testing) import ViewerCore

func runImagingChecks(_ runner: CheckRunner, fixtures: CheckFixtures) {
    let check = runner.check
    let folder = fixtures.folder
    let source = fixtures.source
    let sourceBytes = fixtures.sourceBytes
    let original = fixtures.original

    check("PNG 解码及元数据") { let a = try ImagePipeline.decode(source); return a.pixelWidth == 40 && a.pixelHeight == 20 && a.cgImage?.width == 40 }
    check("损坏文件可恢复错误") { let broken = folder.appendingPathComponent("bad.png"); try Data("broken".utf8).write(to: broken); do { _ = try ImagePipeline.decode(broken); return false } catch { return true } }
    check("旋转改变尺寸且四次旋转复原") { var e = ImageEdits(); e.turns = 1; let a = try e.render(original); e.turns = 4; let b = try e.render(original); return a.width == 20 && a.height == 40 && b.width == 40 && b.height == 20 }
    check("镜像及照片滤镜可渲染") { var e = ImageEdits(); e.flipped = true; e.filter = "CIPhotoEffectNoir"; let a = try e.render(original); return a.width == 40 && a.height == 20 }
    check("所有照片滤镜可渲染") { for (_, filter) in ImageEdits.filters { var e = ImageEdits(); e.filter = filter; _ = try e.render(original) }; return true }
    check("PNG、JPEG、TIFF 导出后可重新解码") { for (ext, type) in [("png", UTType.png), ("jpg", .jpeg), ("tiff", .tiff)] { let p = folder.appendingPathComponent("export.\(ext)"); try ImageEdits.export(original, to: p, type: type); let a = try ImagePipeline.decode(p); if a.pixelWidth != 40 || a.pixelHeight != 20 { return false } }; return true }
    check("无效导出目录不误报成功") { do { try ImageEdits.export(original, to: folder.appendingPathComponent("missing/out.png"), type: .png); return false } catch { return true } }
    check("EXIF 方向得到纠正") {
        let p = folder.appendingPathComponent("orientation.jpg")
        let destination = CGImageDestinationCreateWithURL(p as CFURL, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, original, [kCGImagePropertyOrientation: 6] as CFDictionary); guard CGImageDestinationFinalize(destination) else { return false }
        let a = try ImagePipeline.decode(p); return a.pixelWidth == 20 && a.pixelHeight == 40 && a.cgImage?.width == 20
    }
    check("异步解码在主线程回调") {
        var result: Bool?
        ImagePipeline.shared.load(source) { value in if case .success = value { result = Thread.isMainThread } else { result = false } }
        let deadline = Date().addingTimeInterval(10)
        while result == nil && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
        return result == true
    }
    check("调整和导出不修改输入文件") { try Data(contentsOf: source) == sourceBytes }
    check("GIF 多帧识别") {
        let p = folder.appendingPathComponent("animated.gif")
        let destination = CGImageDestinationCreateWithURL(p as CFURL, UTType.gif.identifier as CFString, 3, nil)!
        for _ in 0..<3 { CGImageDestinationAddImage(destination, original, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.2]] as CFDictionary) }
        guard CGImageDestinationFinalize(destination) else { return false }
        return try ImagePipeline.decode(p).frameCount == 3
    }
    check("大图预览最长边限制") {
        let context = CGContext(data: nil, width: 10000, height: 20, bitsPerComponent: 8, bytesPerRow: 40000, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let p = folder.appendingPathComponent("large.png")
        try ImageEdits.export(context.makeImage()!, to: p, type: .png)
        let asset = try ImagePipeline.decode(p)
        return asset.pixelWidth == 10000 && asset.decodedWidth == 8192 && asset.isPreview
    }
    check("透明图导出 JPEG 使用白色背景") {
        let context = CGContext(data: nil, width: 10, height: 10, bitsPerComponent: 8, bytesPerRow: 40, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let p = folder.appendingPathComponent("alpha.jpg")
        try ImageEdits.export(context.makeImage()!, to: p, type: .jpeg)
        let cg = try ImagePipeline.decode(p).cgImage!
        var bytes = [UInt8](repeating: 0, count: 4)
        bytes.withUnsafeMutableBytes { ptr in
            let output = CGContext(data: ptr.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            output.draw(cg, in: CGRect(x: 0, y: 0, width: 1, height: 1))
        }
        return bytes[0] > 250 && bytes[1] > 250 && bytes[2] > 250
    }
    check("外部替换文件后缓存失效") {
        let p = folder.appendingPathComponent("replace.png"); try ImageEdits.export(original, to: p, type: .png)
        let pipeline = ImagePipeline()
        func load() -> ImageAsset? {
            var asset: ImageAsset?; var done = false
            pipeline.load(p) { result in if case .success(let value) = result { asset = value }; done = true }
            let deadline = Date().addingTimeInterval(10)
            while !done && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
            return asset
        }
        guard load()?.pixelWidth == 40 else { return false }
        var edit = ImageEdits(); edit.turns = 1
        try ImageEdits.export(edit.render(original), to: p, type: .png)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(2)], ofItemAtPath: p.path)
        return load()?.pixelWidth == 20
    }
    check("取消解码请求不回调过时图片") {
        let pipeline = ImagePipeline(); var callbackRan = false
        let operation = pipeline.load(source) { _ in callbackRan = true }
        operation?.cancel()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        return operation?.isCancelled == true && !callbackRan
    }
    check("旋转和镜像按正确方向移动非对称四角像素") {
        let context = CGContext(data: nil, width: 4, height: 2, bitsPerComponent: 8, bytesPerRow: 16,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
        let colors: [[CGFloat]] = [[1, 0, 0, 1], [0, 1, 0, 1], [0, 0, 1, 1], [1, 1, 0, 1]]
        for (index, color) in colors.enumerated() {
            context.setFillColor(CGColor(colorSpace: CGColorSpace(name: CGColorSpace.sRGB)!, components: color)!)
            context.fill(CGRect(x: (index % 2) * 2, y: index / 2, width: 2, height: 1))
        }
        let image = context.makeImage()!
        let corners = cornerPixels(image)
        let expectedOriginal: [[UInt8]] = [[255, 0, 0, 255], [0, 255, 0, 255], [0, 0, 255, 255], [255, 255, 0, 255]]
        guard zip(corners, expectedOriginal).allSatisfy({ pixelsMatch($0, $1) }) else { return false }
        var right = ImageEdits(); right.turns = 1
        var left = ImageEdits(); left.turns = -1
        var mirrored = ImageEdits(); mirrored.flipped = true
        for (edits, indices) in [(right, [1, 3, 0, 2]), (left, [2, 0, 3, 1]), (mirrored, [1, 0, 3, 2])] {
            let result = try edits.render(image)
            let expected = indices.map { corners[$0] }
            guard zip(cornerPixels(result), expected).allSatisfy({ pixelsMatch($0, $1) }) else { return false }
        }
        var fullTurn = ImageEdits(); fullTurn.turns = 4
        let restored = try fullTurn.render(image)
        guard restored.width == image.width, restored.height == image.height else { return false }
        for y in 0..<image.height {
            for x in 0..<image.width {
                guard pixelsMatch(pixel(restored, x: x, y: y), pixel(image, x: x, y: y)) else { return false }
            }
        }
        return true
    }
    check("缓存预算估算包含位图行填充，受限动画只计首帧") {
        let context = CGContext(data: nil, width: 3, height: 2, bitsPerComponent: 8, bytesPerRow: 64,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let cg = context.makeImage()!
        let image = NSImage(cgImage: cg, size: .zero)
        let still = ImageAsset(url: source, image: image, cgImage: cg, properties: [:])
        let limited = ImageAsset(url: source, image: image, cgImage: cg, properties: [:], frameCount: 60, animationLimited: true)
        let oneFrame = cg.bytesPerRow * cg.height
        return cg.bytesPerRow > cg.width * 4 && still.cost == oneFrame && limited.cost == oneFrame && !limited.canAnimate
    }
    check("可播放动画按全部帧保守估算缓存预算并防止整数溢出") {
        let image = NSImage(cgImage: original, size: .zero)
        let animated = ImageAsset(url: source, image: image, cgImage: original, properties: [:], frameCount: 60)
        let huge = ImageAsset(url: source, image: image, cgImage: original, properties: [:], frameCount: Int.max)
        return animated.canAnimate && animated.cost == original.bytesPerRow * original.height * 60 && huge.cost == Int.max
    }
    check("排队中的相同文件请求复用先完成请求的有效缓存") {
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1; queue.isSuspended = true
        let pipeline = ImagePipeline(queue: queue)
        var assets: [ImageAsset] = []; var callbacks = 0; var allOnMain = true
        for _ in 0..<2 {
            pipeline.load(source) { result in
                callbacks += 1; allOnMain = allOnMain && Thread.isMainThread
                if case .success(let asset) = result { assets.append(asset) }
            }
        }
        queue.isSuspended = false
        guard waitForCheck({ callbacks == 2 }), assets.count == 2 else { return false }
        return allOnMain && assets[0] === assets[1]
    }
    check("缓存命中返回可取消请求且不回调已取消结果") {
        let pipeline = ImagePipeline(); var warm: ImageAsset?
        pipeline.load(source) { result in if case .success(let asset) = result { warm = asset } }
        guard waitForCheck({ warm != nil }) else { return false }
        var callbackRan = false
        let operation = pipeline.load(source) { _ in callbackRan = true }
        operation?.cancel()
        RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        return operation != nil && operation?.isCancelled == true && !callbackRan
    }
    check("未取消的缓存命中异步且只在主线程返回同一资产") {
        let pipeline = ImagePipeline(); var warm: ImageAsset?
        pipeline.load(source) { result in if case .success(let asset) = result { warm = asset } }
        guard waitForCheck({ warm != nil }) else { return false }
        var callbacks = 0; var cached: ImageAsset?; var onMain = false
        let operation = pipeline.load(source) { result in
            callbacks += 1; onMain = Thread.isMainThread
            if case .success(let asset) = result { cached = asset }
        }
        guard callbacks == 0, operation != nil, waitForCheck({ callbacks > 0 }) else { return false }
        return callbacks == 1 && onMain && cached === warm
    }
}

// Sample in the image's bottom-left coordinate system, independently of its bitmap layout.
private func pixel(_ image: CGImage, x: Int, y: Int) -> [UInt8] {
    var bytes = [UInt8](repeating: 0, count: 4)
    bytes.withUnsafeMutableBytes { buffer in
        let context = CGContext(data: buffer.baseAddress, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: -x, y: -y, width: image.width, height: image.height))
    }
    return bytes
}

private func pixelsMatch(_ actual: [UInt8], _ expected: [UInt8]) -> Bool {
    actual.count == expected.count && zip(actual, expected).allSatisfy { abs(Int($0) - Int($1)) <= 2 }
}

private func cornerPixels(_ image: CGImage) -> [[UInt8]] {
    [(0, 0), (image.width - 1, 0), (0, image.height - 1), (image.width - 1, image.height - 1)].map {
        pixel(image, x: $0.0, y: $0.1)
    }
}
