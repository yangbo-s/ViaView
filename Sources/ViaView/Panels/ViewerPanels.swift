import AppKit

enum InspectorMode {
    case information, adjustments
    var title: String { self == .information ? "图片信息" : "图像调整" }
}

/// Keeps commands attached to the image that opened the tool panel, while
/// allowing its text fields to handle editing commands through their responder chain.
final class ViewerToolPanel: NSPanel {
    weak var owner: ViewerController?
    override func supplementalTarget(forAction action: Selector, sender: Any?) -> Any? {
        if let owner, owner.responds(to: action) { return owner }
        return super.supplementalTarget(forAction: action, sender: sender)
    }
}


extension ViewerController {
    @objc func toggleFileList(_ sender: Any?) {
        fileList.update(urls: gallery.urls, selected: gallery.current, sort: sort, descending: descending)
        toggleUtilityPanel(fileList.view, title: "文件列表", panel: &fileListPanel, size: NSSize(width: 300, height: 460))
    }
    @objc func toggleInfo(_ sender: Any?) { toggleInspector(.information) }
    @objc func toggleAdjustments(_ sender: Any?) { toggleInspector(.adjustments) }
    func toggleInspector(_ mode: InspectorMode) {
        let wasSame = inspectorMode == mode
        inspectorMode = mode; rebuildInspector()
        if !wasSame, let panel = inspectorPanel, panel.isVisible { panel.title = mode.title; return }
        toggleUtilityPanel(inspector, title: mode.title, panel: &inspectorPanel, size: NSSize(width: 280, height: 600))
    }
    func toggleUtilityPanel(_ view: NSView, title: String, panel: inout NSPanel?, size: NSSize) {
        if let existing = panel, existing.isVisible { existing.orderOut(nil); return }
        if panel == nil {
            let utility = ViewerToolPanel(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
            utility.isReleasedWhenClosed = false; utility.hidesOnDeactivate = true
            utility.isFloatingPanel = true; utility.level = .floating
            utility.owner = self
            utility.contentView = view
            utility.collectionBehavior = [.fullScreenAuxiliary]
            panel = utility
        }
        guard let panel else { return }
        panel.title = title
        let area = screenArea, frame = window?.frame ?? area
        let x = frame.maxX + 8 + size.width <= area.maxX ? frame.maxX + 8 : max(area.minX, frame.minX - size.width - 8)
        panel.setFrameOrigin(NSPoint(x: x, y: min(area.maxY - panel.frame.height, max(area.minY, frame.maxY - panel.frame.height))))
        panel.makeKeyAndOrderFront(nil)
    }
    @objc func editTags(_ sender: Any?) {
        guard gallery.current != nil else { return }
        tagsController.setURL(gallery.current)
        toggleUtilityPanel(tagsController.view, title: "标签", panel: &tagsPanel, size: NSSize(width: 280, height: 400))
        if tagsPanel?.isVisible == true { tagsController.refresh() }
    }
}
