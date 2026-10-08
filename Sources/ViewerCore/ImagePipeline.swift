import AppKit
import ImageIO

public final class ImagePipeline {
    public static let shared = ImagePipeline()
    private let cache = NSCache<NSURL, ImageAsset>()
    private let queue: OperationQueue

    public convenience init() {
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 2
        queue.qualityOfService = .userInitiated
        self.init(queue: queue)
    }

    /// Lets the check executable deterministically exercise queued requests.
    @_spi(Testing) public init(queue: OperationQueue) {
        self.queue = queue
        cache.totalCostLimit = 256 * 1024 * 1024
        cache.countLimit = 12
    }

    public func setCacheLimit(megabytes: Int) { cache.totalCostLimit = min(2048, max(64, megabytes)) * 1024 * 1024 }
    public func clear() { cache.removeAllObjects() }

    private func cachedAsset(for url: URL) -> ImageAsset? {
        guard let asset = cache.object(forKey: url as NSURL), asset.fileSignature == FileSignature(url) else { return nil }
        return asset
    }

    @discardableResult public func load(_ url: URL, priority: Operation.QueuePriority = .veryHigh, completion: @escaping (Result<ImageAsset, Error>) -> Void) -> Operation? {
        let operation = BlockOperation()
        operation.queuePriority = priority
        if let asset = cachedAsset(for: url) {
            operation.addExecutionBlock { [weak operation] in
                guard operation?.isCancelled == false else { return }
                completion(.success(asset))
            }
            OperationQueue.main.addOperation(operation)
            return operation
        }
        operation.addExecutionBlock { [weak self, weak operation] in
            guard let operation, !operation.isCancelled else { return }
            // A previous request may have populated the cache while this one was queued.
            let result = Result { try self?.cachedAsset(for: url) ?? Self.decode(url) }
            guard !operation.isCancelled else { return }
            if case .success(let asset) = result { self?.cache.setObject(asset, forKey: url as NSURL, cost: asset.cost) }
            DispatchQueue.main.async { if !operation.isCancelled { completion(result) } }
        }
        queue.addOperation(operation)
        return operation
    }
    public func prefetch(_ urls: [URL]) {
        for operation in queue.operations where operation.queuePriority == .low && !operation.isExecuting { operation.cancel() }
        for url in urls { load(url, priority: .low) { _ in } }
    }
    public static func decode(_ url: URL) throws -> ImageAsset {
        if url.pathExtension.lowercased() == "svg" {
            let size = try SVGDocument.size(at: url)
            // WebKit renders the original vector inside the same zooming document.
            return ImageAsset(url: url, image: NSImage(size: size), cgImage: nil, properties: [:])
        }
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else {
            if url.pathExtension.lowercased() == "pdf", let image = NSImage(contentsOf: url), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
                return ImageAsset(url: url, image: image, cgImage: cg, properties: [:])
            }
            throw ViewerError.decode(url.lastPathComponent)
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [String: Any] ?? [:]
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 8192,
            kCGImageSourceShouldCacheImmediately: true]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { throw ViewerError.decode(url.lastPathComponent) }
        let count = CGImageSourceGetCount(source)
        let animated = ["gif", "apng", "png"].contains(url.pathExtension.lowercased()) && count > 1
        let animationLimited = animated && (Double(cg.bytesPerRow) * Double(cg.height) * Double(count) > 256 * 1024 * 1024 || (properties[kCGImagePropertyPixelWidth as String] as? Int ?? 0) > 8192 || (properties[kCGImagePropertyPixelHeight as String] as? Int ?? 0) > 8192)
        let image = animated && !animationLimited ? NSImage(contentsOf: url) ?? NSImage(cgImage: cg, size: .zero) : NSImage(cgImage: cg, size: .zero)
        image.size = NSSize(width: cg.width, height: cg.height)
        return ImageAsset(url: url, image: image, cgImage: cg, properties: properties, frameCount: animated ? count : 1, animationLimited: animationLimited)
    }
    public static func thumbnail(_ url: URL, size: Int = 112) -> NSImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: size] as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: .zero)
    }
}
