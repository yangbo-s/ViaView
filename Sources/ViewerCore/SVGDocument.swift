import Foundation
import CoreGraphics

enum SVGDocument {
    static func size(at url: URL) throws -> CGSize {
        guard let size = FileSignature(url).size, size < 32 * 1024 * 1024 else { throw ViewerError.decode(url.lastPathComponent) }
        let data = try Data(contentsOf: url)
        guard data.count < 32 * 1024 * 1024 else { throw ViewerError.decode(url.lastPathComponent) }
        let validation = SVGValidation()
        let parser = XMLParser(data: data)
        parser.delegate = validation
        parser.shouldResolveExternalEntities = false
        guard parser.parse(), validation.hasSVGRoot else { throw ViewerError.decode(url.lastPathComponent) }
        return validation.size
    }
}

private final class SVGValidation: NSObject, XMLParserDelegate {
    var hasSVGRoot = false
    var size = CGSize(width: 640, height: 480)
    private var seenRoot = false
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if !seenRoot {
            hasSVGRoot = elementName.lowercased() == "svg"; seenRoot = true
            let box = (attributeDict["viewBox"] ?? "").split { $0 == " " || $0 == "," || $0 == "\n" }.compactMap { Double($0) }
            func length(_ key: String) -> Double? {
                guard let value = attributeDict[key], !value.contains("%") else { return nil }
                return Double(value.replacingOccurrences(of: "px", with: ""))
            }
            let width = length("width") ?? (box.count == 4 ? box[2] : 640)
            let height = length("height") ?? (box.count == 4 ? box[3] : 480)
            if width.isFinite, height.isFinite, width > 0, height > 0 {
                let limit = min(1, 16384 / max(width, height))
                size = CGSize(width: width * limit, height: height * limit)
            }
        }
    }
}
