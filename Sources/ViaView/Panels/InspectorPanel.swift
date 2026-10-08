import AppKit
import ViewerCore

extension ViewerController {
    func buildInspector() {
        inspector.hasVerticalScroller = true; inspector.drawsBackground = true; inspector.borderType = .noBorder
        inspector.documentView = FlippedDocument(frame: NSRect(x: 0, y: 0, width: 280, height: 600))
        inspectorStack.orientation = .vertical; inspectorStack.alignment = .leading; inspectorStack.spacing = 14
        inspector.documentView?.addSubview(inspectorStack)
        rebuildInspector()
    }
    func rebuildInspector() {
        for view in inspectorStack.arrangedSubviews { inspectorStack.removeArrangedSubview(view); view.removeFromSuperview() }
        sliderLabels.removeAll()
        func add(_ view: NSView, height: CGFloat? = nil) {
            view.translatesAutoresizingMaskIntoConstraints = false
            view.widthAnchor.constraint(equalToConstant: 248).isActive = true
            if let height { view.heightAnchor.constraint(equalToConstant: height).isActive = true }
            inspectorStack.addArrangedSubview(view)
        }
        let header = NSStackView(views: [label(inspectorMode.title, size: 17, weight: .semibold), symbolButton("xmark", "收起面板", target: self, action: #selector(closeInspector(_:)), size: 24)])
        header.distribution = .equalSpacing; add(header)
        guard let asset else {
            add(label("打开图片后在这里查看详情。", color: .secondaryLabelColor)); layoutInspector(); return
        }
        if inspectorMode == .information {
            if !asset.isSVG { let histogram = HistogramView(); histogram.update(displayedCG); add(histogram, height: 90) }
            var metadata = asset.isSVG ? [("文件", asset.url.lastPathComponent), ("格式", "SVG · 矢量图像")] : asset.metadata.map { ($0.0 == "尺寸" ? "原始尺寸" : $0.0, $0.1) }
            if !edits.isIdentity, let cg = displayedCG { metadata.insert(("当前预览", "\(cg.width) × \(cg.height) px"), at: min(2, metadata.count)) }
            for (title, value) in metadata {
                let valueField = label(value, size: 12); valueField.isSelectable = true; valueField.maximumNumberOfLines = 4; valueField.lineBreakMode = .byWordWrapping
                let pair = NSStackView(views: [label(title, size: 11, color: .secondaryLabelColor), valueField]); pair.orientation = .vertical; pair.alignment = .leading; pair.spacing = 4
                add(pair)
            }
            let path = label(asset.url.deletingLastPathComponent().path, size: 11, color: .secondaryLabelColor)
            path.isSelectable = true; path.maximumNumberOfLines = 3; path.lineBreakMode = .byTruncatingMiddle; add(path)
            let reveal = NSButton(title: "在 Finder 中显示", target: self, action: #selector(reveal(_:))); reveal.bezelStyle = .rounded; add(reveal)
            let ocr = NSButton(title: "识别图片文字…", target: self, action: #selector(recognizeText(_:))); ocr.bezelStyle = .rounded; ocr.isEnabled = displayedCG != nil; add(ocr)
            let inspect = NSButton(title: "取色并复制色号", target: self, action: #selector(pickColor(_:))); inspect.bezelStyle = .rounded; inspect.isEnabled = gallery.current != nil && !samplingColor; add(inspect)
        } else if asset.isSVG {
            add(label("SVG 保持矢量显示。\n像素调整用于位图图像。", color: .secondaryLabelColor))
        } else {
            let note = label("调整只影响预览，导出另存为。", size: 11, color: .secondaryLabelColor); add(note)
            let rotations = NSStackView(views: [symbolButton("rotate.left", "向左旋转", target: self, action: #selector(rotateLeft(_:))), symbolButton("rotate.right", "向右旋转", target: self, action: #selector(rotateRight(_:))), symbolButton("arrow.left.and.right.righttriangle.left.righttriangle.right", "水平镜像", target: self, action: #selector(flip(_:)))])
            rotations.distribution = .equalSpacing; add(rotations)
            let popup = NSPopUpButton(); popup.addItems(withTitles: ImageEdits.filters.map(\.0)); popup.selectItem(at: ImageEdits.filters.firstIndex { $0.1 == edits.filter } ?? 0); popup.target = self; popup.action = #selector(filterChanged(_:)); popup.setAccessibilityLabel("照片滤镜"); add(popup)
            let values: [(String, String, Double, Double, Double)] = [("brightness", "亮度", edits.brightness, -1, 1), ("contrast", "对比度", edits.contrast, 0, 2), ("saturation", "饱和度", edits.saturation, 0, 2), ("exposure", "曝光", edits.exposure, -2, 2)]
            for (key, title, value, minimum, maximum) in values {
                let caption = label(String(format: "%@    %.2f", title, value), size: 12); sliderLabels[key] = caption; add(caption)
                let slider = NSSlider(value: value, minValue: minimum, maxValue: maximum, target: self, action: #selector(sliderChanged(_:)))
                slider.identifier = NSUserInterfaceItemIdentifier(key); slider.isContinuous = true; slider.setAccessibilityLabel(title); add(slider)
            }
            let reset = NSButton(title: "重置所有调整", target: self, action: #selector(resetEdits(_:))); reset.bezelStyle = .rounded; add(reset)
            let export = NSButton(title: "导出图片…", target: self, action: #selector(exportImage(_:))); export.bezelStyle = .rounded; add(export)
            if asset.frameCount > 1 { let note = label("调整和导出使用动画首帧；重置后恢复播放。", size: 11, color: .secondaryLabelColor); note.maximumNumberOfLines = 3; note.lineBreakMode = .byWordWrapping; add(note) }
        }
        layoutInspector()
    }
    func layoutInspector() {
        let height = inspectorStack.fittingSize.height
        inspectorStack.frame = NSRect(x: 16, y: 44, width: 248, height: height)
        inspector.documentView?.frame = NSRect(x: 0, y: 0, width: 280, height: max(200, height + 64))
    }
    @objc func closeInspector(_ sender: Any?) { inspectorPanel?.orderOut(nil) }
}
