import Foundation

public enum ViewerError: LocalizedError {
    case decode(String), export
    public var errorDescription: String? {
        switch self {
        case .decode(let name): return "无法解码 \(name)。文件可能损坏，或当前 macOS 不支持此格式。"
        case .export: return "无法写入图片，请检查目标文件夹的访问权限。"
        }
    }
}
