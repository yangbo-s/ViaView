import Foundation
import CoreGraphics

/// All sizes are points in the image document's coordinate system.
public struct ImageWindowGeometry {
    public let image: CGSize
    public let minimumScale: CGFloat
    public let maximumScale: CGFloat
    public init(image: CGSize, available: CGSize, minimum: CGSize = CGSize(width: 320, height: 240)) {
        self.image = CGSize(width: max(1, image.width), height: max(1, image.height))
        maximumScale = max(0.00001, min(max(1, available.width) / self.image.width, max(1, available.height) / self.image.height))
        minimumScale = min(maximumScale, max(minimum.width / self.image.width, minimum.height / self.image.height))
    }
    public func windowSize(at scale: CGFloat) -> CGSize {
        let bounded = min(maximumScale, max(minimumScale, scale))
        return CGSize(width: image.width * bounded, height: image.height * bounded)
    }
}

/// Log-space filtering makes a wheel unit feel the same at every zoom level.
/// The exponential step is independent of display refresh rate and never overshoots.
public struct SmoothZoom {
    public private(set) var value: Double = 0
    public private(set) var target: Double = 0
    public init() {}
    public mutating func reset(_ scale: CGFloat) { value = log(Double(max(0.00001, scale))); target = value }
    public mutating func aim(_ scale: CGFloat) { target = log(Double(max(0.00001, scale))) }
    public var targetScale: CGFloat { CGFloat(exp(target)) }
    public var isSettled: Bool { abs(target - value) < 0.0001 }
    public mutating func advance(seconds: Double, response: Double = 0.045) -> CGFloat {
        value += (target - value) * -expm1(-max(0, seconds) / response)
        if isSettled { value = target }
        return CGFloat(exp(value))
    }
}
