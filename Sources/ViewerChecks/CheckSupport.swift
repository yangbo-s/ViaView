import AppKit
import Foundation
import UniformTypeIdentifiers
import ViewerCore

final class CheckRunner {
    private(set) var passed = 0
    private(set) var failed = 0

    func check(_ name: String, _ body: () throws -> Bool) {
        do {
            if try body() { passed += 1; print("PASS \(name)") }
            else { failed += 1; print("FAIL \(name)") }
        } catch {
            recordFailure(name, error: error)
        }
    }

    func recordFailure(_ name: String, error: Error) {
        failed += 1
        print("FAIL \(name): \(error)")
    }

    func printSummary() { print("\n\(passed) passed, \(failed) failed") }
}

/// One owned temporary directory. Every file created by a suite stays beneath it.
struct CheckFixtures {
    let folder: URL
    let original: CGImage
    let source: URL
    let sourceBytes: Data

    init() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("ViaViewChecks-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        do {
            let context = CGContext(data: nil, width: 40, height: 20, bitsPerComponent: 8, bytesPerRow: 160,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            context.setFillColor(CGColor(red: 0.2, green: 0.3, blue: 0.4, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: 40, height: 20))
            let original = context.makeImage()!
            for name in ["image10.png", "image2.png", "image1.png", ".hidden.png"] {
                try ImageEdits.export(original, to: folder.appendingPathComponent(name), type: .png)
            }
            try Data("not an image".utf8).write(to: folder.appendingPathComponent("notes.txt"))
            try FileManager.default.createDirectory(at: folder.appendingPathComponent("folder.jpg"), withIntermediateDirectories: false)
            let source = folder.appendingPathComponent("image1.png")
            self.folder = folder
            self.original = original
            self.source = source
            self.sourceBytes = try Data(contentsOf: source)
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    func taggedImage(_ name: String, tags: [FinderTag] = []) throws -> URL {
        let url = folder.appendingPathComponent(name + ".png")
        try sourceBytes.write(to: url)
        for tag in tags { try FinderTags.add(tag, to: url) }
        return url
    }

    func remove() throws { try FileManager.default.removeItem(at: folder) }
}

func waitForCheck(timeout: TimeInterval = 10, _ predicate: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while !predicate() && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.01)) }
    return predicate()
}
