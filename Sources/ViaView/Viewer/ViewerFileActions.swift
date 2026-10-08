import AppKit
import UniformTypeIdentifiers
import Vision
import ViewerCore

extension ViewerController {
    @objc func exportImage(_ sender: Any?) {
        guard !exportInProgress, let asset, let original = asset.cgImage else { return }
        let exportEdits = edits
        let width = exportEdits.turns % 2 == 0 ? original.width : original.height
        let height = exportEdits.turns % 2 == 0 ? original.height : original.width
        let panel = NSSavePanel(); exportPanel = panel
        panel.title = "导出图片"; panel.nameFieldStringValue = (gallery.current?.deletingPathExtension().lastPathComponent ?? "图片") + "-edited.png"
        panel.allowedContentTypes = [.png]; panel.canCreateDirectories = true
        panel.message = asset.isPreview ? "当前预览为 \(width) × \(height) px，将按此尺寸导出。原文件不变。" : "导出当前调整后的静态图片，原文件保持不变。"
        let formats = NSPopUpButton(); formats.addItems(withTitles: ["PNG · 无损，保留透明度", "JPEG · 照片", "TIFF · 无损"]); formats.target = self; formats.action = #selector(exportFormatChanged(_:)); panel.accessoryView = formats
        if panel.runModal() == .OK, let url = panel.url {
            let type: UTType = [.png, .jpeg, .tiff][formats.indexOfSelectedItem]
            let serial = loadSerial
            exportInProgress = true
            DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                let result = Result { let cg = exportEdits.isIdentity ? original : try exportEdits.render(original); try ImageEdits.export(cg, to: url, type: type) }
                DispatchQueue.main.async {
                    guard let self else { return }; self.exportInProgress = false
                    if serial == self.loadSerial { self.updateUI() }
                    if case .failure(let error) = result { self.showError(error) }
                }
            }
        }
        exportPanel = nil
    }
    @objc func exportFormatChanged(_ sender: NSPopUpButton) {
        let type: UTType = [.png, .jpeg, .tiff][sender.indexOfSelectedItem]
        exportPanel?.allowedContentTypes = [type]
        if let name = exportPanel?.nameFieldStringValue { exportPanel?.nameFieldStringValue = (name as NSString).deletingPathExtension + "." + (type.preferredFilenameExtension ?? "png") }
    }
    @objc func copyImage(_ sender: Any?) {
        guard let cg = displayedCG else { return }
        let crop = canvas.selection.integral
        let output = crop.width > 1 && crop.height > 1 ? cg.cropping(to: crop) ?? cg : cg
        NSPasteboard.general.clearContents(); NSPasteboard.general.writeObjects([NSImage(cgImage: output, size: .zero)])
    }
    @objc func copyPath(_ sender: Any?) {
        guard let url = gallery.current else { return }; NSPasteboard.general.clearContents(); NSPasteboard.general.setString(url.path, forType: .string)
    }
    @objc func reveal(_ sender: Any?) { if let url = gallery.current { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
    @objc func share(_ sender: Any?) {
        guard let url = gallery.current else { return }
        let items: [Any] = edits.isIdentity ? [url] : (canvas.image.map { [$0] } ?? [url])
        let picker = NSSharingServicePicker(items: items)
        let view = sender as? NSView ?? topChrome; picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
    @objc func printImage(_ sender: Any?) {
        guard let image = canvas.image else { return }
        let view = NSImageView(frame: NSRect(origin: .zero, size: image.size)); view.image = image; view.imageScaling = .scaleProportionallyUpOrDown
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo; info.horizontalPagination = .fit; info.verticalPagination = .fit; info.isHorizontallyCentered = true; info.isVerticallyCentered = true
        NSPrintOperation(view: view, printInfo: info).run()
    }
    @objc func recognizeText(_ sender: Any?) {
        guard let cg = displayedCG else { return }
        let serial = loadSerial
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let result = Result { () -> String in
                let request = VNRecognizeTextRequest(); request.recognitionLevel = .accurate; request.usesLanguageCorrection = true; request.automaticallyDetectsLanguage = true
                try VNImageRequestHandler(cgImage: cg).perform([request])
                return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
            }
            DispatchQueue.main.async {
                guard let self, self.loadSerial == serial else { return }; self.updateUI()
                switch result {
                case .failure(let error): self.showError(error)
                case .success(let text):
                    let alert = NSAlert(); alert.messageText = text.isEmpty ? "未识别到文字" : "识别结果"
                    if text.isEmpty { alert.informativeText = "试试文字更清晰、分辨率更高的图片。"; alert.runModal(); return }
                    let view = NSTextView(frame: NSRect(x: 0, y: 0, width: 500, height: 260)); view.string = text; view.isEditable = false; view.isSelectable = true; view.font = .systemFont(ofSize: 13)
                    let scroll = NSScrollView(frame: view.frame); scroll.hasVerticalScroller = true; scroll.documentView = view; alert.accessoryView = scroll
                    alert.addButton(withTitle: "复制文本"); alert.addButton(withTitle: "关闭")
                    if alert.runModal() == .alertFirstButtonReturn { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
                }
            }
        }
    }}
