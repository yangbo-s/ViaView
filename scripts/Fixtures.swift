import AppKit
import ImageIO
import UniformTypeIdentifiers

let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
func frame(_ index: Int) -> CGImage {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 960, pixelsHigh: 640, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 3840, bitsPerPixel: 32)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSColor(calibratedRed: 0.12, green: 0.25, blue: 0.30, alpha: 1).setFill(); NSRect(x: 0, y: 0, width: 960, height: 640).fill()
    NSColor(calibratedRed: 0.80, green: 0.60, blue: 0.30, alpha: 1).setFill()
    NSBezierPath(ovalIn: NSRect(x: 150 + index * 240, y: 280, width: 180, height: 180)).fill()
    ("LOCAL IMAGE VIEWER" as NSString).draw(at: NSPoint(x: 80, y: 170), withAttributes: [.font: NSFont.systemFont(ofSize: 48, weight: .semibold), .foregroundColor: NSColor.white])
    ("ViaView 2026 • Frame \(index + 1)" as NSString).draw(at: NSPoint(x: 80, y: 110), withAttributes: [.font: NSFont.systemFont(ofSize: 28), .foregroundColor: NSColor.white])
    NSGraphicsContext.restoreGraphicsState(); return rep.cgImage!
}
let image = frame(0)
for (name, type) in [("01-ocr.png", UTType.png), ("02-photo.jpg", .jpeg), ("03-photo.tiff", .tiff)] {
    let dst = CGImageDestinationCreateWithURL(folder.appendingPathComponent(name) as CFURL, type.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(dst, image, nil); precondition(CGImageDestinationFinalize(dst))
}
let animation = CGImageDestinationCreateWithURL(folder.appendingPathComponent("04-animation.gif") as CFURL, UTType.gif.identifier as CFString, 3, nil)!
CGImageDestinationSetProperties(animation, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
for i in 0..<3 { CGImageDestinationAddImage(animation, frame(i), [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.4]] as CFDictionary) }
precondition(CGImageDestinationFinalize(animation))
try "<svg xmlns='http://www.w3.org/2000/svg' width='960' height='640' viewBox='0 0 960 640'><rect width='960' height='640' fill='#20424a'/><circle cx='480' cy='260' r='150' fill='#ddb35c'/><text x='480' y='520' text-anchor='middle' font-family='sans-serif' font-size='48' fill='white'>OFFLINE SVG</text></svg>".write(to: folder.appendingPathComponent("05-vector.svg"), atomically: true, encoding: .utf8)
try Data("invalid image".utf8).write(to: folder.appendingPathComponent("06-broken.png"))
print(folder.path)
