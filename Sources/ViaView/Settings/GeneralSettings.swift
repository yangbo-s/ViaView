import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct GeneralSettings: View {
    @AppStorage("selectOnDrag") private var selectOnDrag = false
    @AppStorage("openInNewWindow") private var newWindow = false
    @AppStorage("restoreWindows") private var restore = false
    @AppStorage("quitLastWindow") private var quitLast = false
    @AppStorage("doubleClickZoom") private var doubleClick = true
    @AppStorage("smoothRendering") private var smooth = true
    @AppStorage("swipeNavigate") private var swipe = true
    @AppStorage("zoomSensitivity") private var sensitivity = 1.0
    @AppStorage("darkCanvas") private var dark = false
    @AppStorage("checkerboard") private var checkerboard = true
    @AppStorage("preloadImages") private var preload = true
    @AppStorage("cacheMB") private var cacheMB = 256
    @AppStorage("editorBundleID") private var editor = "com.apple.Preview"
    @State private var editors: [(id: String, name: String)] = []
    @State private var cacheCleared = false
    var body: some View {
        Form {
            Section("窗口") {
                Picker("拖动图片", selection: $selectOnDrag) {
                    Text("平移；⌘ 拖动框选").tag(false)
                    Text("框选；⌘ 拖动平移").tag(true)
                }
                Toggle("新打开的图片使用新窗口", isOn: $newWindow)
                Toggle("启动时恢复上次打开的图片", isOn: $restore)
                Toggle("关闭最后一个窗口时退出", isOn: $quitLast)
            }
            Section {
                Toggle("双击切换实际大小与适应屏幕", isOn: $doubleClick)
                Toggle("平滑显示缩放后的图像", isOn: $smooth)
                HStack {
                    Text("滚轮缩放速度")
                    Spacer()
                    Text("慢").foregroundStyle(.secondary)
                    Slider(value: $sensitivity, in: 0.3...2).labelsHidden().frame(width: 160).accessibilityLabel("滚轮缩放速度")
                    Text("快").foregroundStyle(.secondary)
                }
                Toggle("触控板左右轻扫切换图片", isOn: $swipe)
            } header: { Text("缩放与手势") } footer: {
                Text("关闭平滑显示可查看像素边缘。Shift + 滚轮平移；缩放动画始终连续。")
            }
            Section("背景") {
                Picker("图片周围", selection: $dark) { Text("浅色").tag(false); Text("深色").tag(true) }
                Toggle("透明区域显示棋盘格", isOn: $checkerboard)
            }
            Section {
                Toggle("预载相邻图片", isOn: $preload)
                Picker("图像缓存上限", selection: $cacheMB) {
                    ForEach([64, 128, 256, 512, 1024, 2048], id: \.self) { Text("\($0) MB").tag($0) }
                }
                HStack {
                    Button("清空图像缓存") { (NSApp.delegate as? AppDelegate)?.clearImageCaches(); cacheCleared = true }
                    if cacheCleared { Text("缓存已清空").foregroundStyle(.secondary) }
                }
            } header: { Text("性能") } footer: {
                Text("这是缓存预算，当前图片与解码中的图像还会占用内存。RAW 由 macOS 图像框架解码。")
            }
            Section("外部编辑器") {
                Picker("打开原文件", selection: $editor) {
                    ForEach(editors, id: \.id) { app in Text(app.name).tag(app.id) }
                    if !editors.contains(where: { $0.id == editor }) { Text("已选应用不可用").tag(editor) }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            var seen = Set<String>()
            let workspace = NSWorkspace.shared
            let candidates = [UTType.image, .jpeg, .png, .tiff].flatMap { workspace.urlsForApplications(toOpen: $0) }
                + [workspace.urlForApplication(withBundleIdentifier: "com.apple.Preview"), AppSettings.editorURL].compactMap { $0 }
            editors = candidates.compactMap { url in
                guard let id = Bundle(url: url)?.bundleIdentifier, id != Bundle.main.bundleIdentifier, seen.insert(id).inserted else { return nil }
                return (id, (FileManager.default.displayName(atPath: url.path) as NSString).deletingPathExtension)
            }.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        }
    }
}
