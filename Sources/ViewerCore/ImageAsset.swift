import AppKit
import ImageIO

public final class ImageAsset {
    public let url: URL
    public let image: NSImage
    public let cgImage: CGImage?
    public let properties: [String: Any]
    public let frameCount: Int
    public let animationLimited: Bool
    public var canAnimate: Bool { frameCount > 1 && !animationLimited }
    let fileSignature: FileSignature
    public let pixelWidth: Int
    public let pixelHeight: Int
    public let decodedWidth: Int
    public let decodedHeight: Int
    public var isPreview: Bool { decodedWidth < pixelWidth || decodedHeight < pixelHeight }
    public var isSVG: Bool { url.pathExtension.lowercased() == "svg" }
    /// Conservative cache accounting, not a measurement of resident memory.
    /// A limited animation retains only its first frame; playable animations budget every frame.
    public var cost: Int {
        let frameBytes: Int
        if let cgImage {
            frameBytes = Self.boundedProduct(cgImage.bytesPerRow, cgImage.height)
        } else {
            frameBytes = Self.boundedProduct(Self.boundedProduct(decodedWidth, decodedHeight), 4)
        }
        return max(1, Self.boundedProduct(frameBytes, canAnimate ? frameCount : 1))
    }
    private static func boundedProduct(_ lhs: Int, _ rhs: Int) -> Int {
        let result = max(0, lhs).multipliedReportingOverflow(by: max(0, rhs))
        return result.overflow ? Int.max : result.partialValue
    }
    public init(url: URL, image: NSImage, cgImage: CGImage?, properties: [String: Any], frameCount: Int = 1, animationLimited: Bool = false) {
        self.url = url; self.image = image; self.cgImage = cgImage; self.properties = properties; self.frameCount = frameCount
        self.animationLimited = animationLimited; fileSignature = FileSignature(url)
        decodedWidth = cgImage?.width ?? Int(image.size.width)
        decodedHeight = cgImage?.height ?? Int(image.size.height)
        let orientation = properties[kCGImagePropertyOrientation as String] as? Int ?? 1
        let w = properties[kCGImagePropertyPixelWidth as String] as? Int ?? decodedWidth
        let h = properties[kCGImagePropertyPixelHeight as String] as? Int ?? decodedHeight
        pixelWidth = orientation >= 5 ? h : w; pixelHeight = orientation >= 5 ? w : h
    }
    public var metadata: [(String, String)] {
        var result = [("文件", url.lastPathComponent), ("尺寸", "\(pixelWidth) × \(pixelHeight) px"), ("格式", url.pathExtension.uppercased())]
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            result.append(("文件大小", ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)))
        }
        if frameCount > 1 { result.append(("帧数", "\(frameCount)")) }
        if animationLimited { result.append(("动画预览", "仅显示首帧：动画尺寸或预计解码内存超限")) }
        if isPreview { result.append(("显示模式", "大图预览 · 最长边 8192 px")) }
        let tiff = properties[kCGImagePropertyTIFFDictionary as String] as? [String: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary as String] as? [String: Any] ?? [:]
        let fields: [(String, String, [String: Any])] = [("相机", "Model", tiff), ("厂商", "Make", tiff), ("拍摄时间", "DateTimeOriginal", exif), ("镜头", "LensModel", exif), ("光圈", "FNumber", exif), ("曝光时间（秒）", "ExposureTime", exif), ("ISO", "ISOSpeedRatings", exif), ("焦距（mm）", "FocalLength", exif), ("色彩空间", "ProfileName", properties)]
        for (label, key, source) in fields { if let value = source[key] { result.append((label, String(describing: value))) } }
        return result
    }
}

struct FileSignature: Equatable {
    let date: Date?
    let size: Int?
    init(_ url: URL) {
        let values = try? FileManager.default.attributesOfItem(atPath: url.path)
        date = values?[.modificationDate] as? Date; size = values?[.size] as? Int
    }
}
