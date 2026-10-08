import AppKit

public enum ColorHex {
    public static func string(from color: NSColor?) -> String? {
        guard let color = color?.usingColorSpace(.sRGB) else { return nil }
        let components = [color.redComponent, color.greenComponent, color.blueComponent].map { Int((min(1, max(0, $0)) * 255).rounded()) }
        return String(format: "#%02X%02X%02X", components[0], components[1], components[2])
    }
    @discardableResult public static func copy(_ color: NSColor?, to pasteboard: NSPasteboard = .general) -> String? {
        guard let hex = string(from: color) else { return nil }
        pasteboard.clearContents(); pasteboard.setString(hex, forType: .string)
        return hex
    }
}
