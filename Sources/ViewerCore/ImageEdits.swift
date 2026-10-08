import CoreGraphics
import CoreImage
import ImageIO
import UniformTypeIdentifiers

public struct ImageEdits: Equatable {
    public var turns = 0
    public var flipped = false
    public var brightness: Double = 0
    public var contrast: Double = 1
    public var saturation: Double = 1
    public var exposure: Double = 0
    public var filter = ""
    public init() {}
    public var isIdentity: Bool { self == ImageEdits() }
    public static let filters = [("原图", ""), ("黑白", "CIPhotoEffectNoir"), ("单色", "CIPhotoEffectMono"), ("铬黄", "CIPhotoEffectChrome"), ("即时", "CIPhotoEffectInstant"), ("褪色", "CIPhotoEffectFade"), ("冲印", "CIPhotoEffectProcess"), ("色调", "CIPhotoEffectTonal"), ("岁月", "CIPhotoEffectTransfer")]
    private static let context = CIContext(options: [.cacheIntermediates: false])
    public func render(_ original: CGImage) throws -> CGImage {
        var image = CIImage(cgImage: original)
        if flipped { image = image.oriented(.upMirrored) }
        let rotations: [CGImagePropertyOrientation] = [.up, .right, .down, .left]
        image = image.oriented(rotations[((turns % 4) + 4) % 4])
        image = image.applyingFilter("CIColorControls", parameters: [kCIInputBrightnessKey: brightness, kCIInputContrastKey: contrast, kCIInputSaturationKey: saturation])
        image = image.applyingFilter("CIExposureAdjust", parameters: [kCIInputEVKey: exposure])
        if !filter.isEmpty { image = image.applyingFilter(filter) }
        guard let result = Self.context.createCGImage(image, from: image.extent) else { throw ViewerError.export }
        return result
    }
    public static func export(_ image: CGImage, to url: URL, type: UTType) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, 1, nil) else { throw ViewerError.export }
        var output = image
        if type == .jpeg, let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) {
            let rect = CGRect(x: 0, y: 0, width: image.width, height: image.height)
            context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(rect); context.draw(image, in: rect)
            if let flattened = context.makeImage() { output = flattened }
        }
        CGImageDestinationAddImage(destination, output, [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw ViewerError.export }
    }
}
