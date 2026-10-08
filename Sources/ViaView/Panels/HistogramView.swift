import AppKit

final class HistogramView: NSView {
    var channels = [[Int]]()
    func update(_ image: CGImage?) {
        guard let image else { channels = []; needsDisplay = true; return }
        var data = [UInt8](repeating: 0, count: 128 * 128 * 4)
        data.withUnsafeMutableBytes { pointer in
            let context = CGContext(data: pointer.baseAddress, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 512, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            context?.draw(image, in: CGRect(x: 0, y: 0, width: 128, height: 128))
        }
        channels = Array(repeating: Array(repeating: 0, count: 256), count: 3)
        for i in stride(from: 0, to: data.count, by: 4) { for c in 0..<3 { channels[c][Int(data[i+c])] += 1 } }
        needsDisplay = true
    }
    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill(); bounds.fill()
        for (c, values) in channels.enumerated() {
            let maximum = Double(values.max() ?? 1); let path = NSBezierPath()
            for (index, value) in values.enumerated() {
                let point = NSPoint(x: CGFloat(index) / 255 * bounds.width, y: CGFloat(log1p(Double(value)) / log1p(maximum)) * (bounds.height - 4))
                if index == 0 { path.move(to: point) } else { path.line(to: point) }
            }
            [NSColor.systemRed, .systemGreen, .systemBlue][c].withAlphaComponent(0.8).setStroke(); path.lineWidth = 1; path.stroke()
        }
    }
}
