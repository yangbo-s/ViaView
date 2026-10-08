import AppKit
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
let sizes = [(16,"icon_16x16.png"),(32,"icon_16x16@2x.png"),(32,"icon_32x32.png"),(64,"icon_32x32@2x.png"),(128,"icon_128x128.png"),(256,"icon_128x128@2x.png"),(256,"icon_256x256.png"),(512,"icon_256x256@2x.png"),(512,"icon_512x512.png"),(1024,"icon_512x512@2x.png")]
for (size,name) in sizes {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let transform = NSAffineTransform(); transform.scale(by: CGFloat(size)/1024); transform.concat()
    let outer = NSBezierPath(roundedRect: NSRect(x: 40,y: 40,width: 944,height: 944), xRadius: 210,yRadius: 210)
    NSColor(calibratedRed: 0.12,green: 0.28,blue: 0.36,alpha: 1).setFill(); outer.fill()
    NSColor(calibratedRed: 0.89,green: 0.96,blue: 0.96,alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 185,y: 225,width: 654,height: 574),xRadius: 80,yRadius: 80).fill()
    NSColor(calibratedRed: 0.36,green: 0.66,blue: 0.70,alpha: 1).setFill()
    let mountain = NSBezierPath(); mountain.move(to: NSPoint(x: 230,y: 290)); mountain.line(to: NSPoint(x: 450,y: 580)); mountain.line(to: NSPoint(x: 605,y: 400)); mountain.line(to: NSPoint(x: 710,y: 520)); mountain.line(to: NSPoint(x: 794,y: 290)); mountain.close(); mountain.fill()
    NSColor(calibratedRed: 0.95,green: 0.72,blue: 0.36,alpha: 1).setFill(); NSBezierPath(ovalIn: NSRect(x: 630,y: 615,width: 100,height: 100)).fill()
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png,properties: [:])!.write(to: folder.appendingPathComponent(name))
}
