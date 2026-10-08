import AppKit
import ViewerCore

extension ViewerController {
    func buildInspector() { rebuildInspector() }

    func rebuildInspector() {
        inspector.clear()
        sliderLabels.removeAll()
        guard let asset else {
            inspector.add(label("打开图片后查看详情与调整。", color: .secondaryLabelColor))
            layoutInspector()
            return
        }
        let thumbnail = NSImageView(image: asset.image)
        thumbnail.imageScaling = .scaleProportionallyUpOrDown
        thumbnail.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([thumbnail.widthAnchor.constraint(equalToConstant: 52), thumbnail.heightAnchor.constraint(equalToConstant: 52)])
        let filename = label(asset.url.lastPathComponent, size: 13, weight: .semibold)
        filename.toolTip = asset.url.lastPathComponent
        filename.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        let summary = label(asset.isSVG ? "SVG · 矢量图像" : "\(asset.pixelWidth) × \(asset.pixelHeight) px · \(asset.url.pathExtension.uppercased())", size: 11, color: .secondaryLabelColor)
        let details = NSStackView(views: [filename, summary])
        details.orientation = .vertical; details.alignment = .leading; details.spacing = 5
        let identity = NSStackView(views: [thumbnail, details])
        identity.spacing = 12; identity.alignment = .centerY
        inspector.add(identity)
        inspector.add(inspectorSeparator())
        if inspectorMode == .information { buildImageInformation(asset) }
        else if asset.cgImage == nil {
            inspector.add(label("矢量图像保持原始显示，无需像素调整。", color: .secondaryLabelColor))
        } else { buildImageAdjustments(asset) }
        layoutInspector()
    }

    private func buildImageInformation(_ asset: ImageAsset) {
        if !asset.isSVG {
            let histogram = HistogramView()
            histogram.update(displayedCG)
            histogram.heightAnchor.constraint(equalToConstant: 88).isActive = true
            histogram.setAccessibilityLabel("红、绿、蓝通道直方图")
            inspector.add(inspectorSection("直方图", views: [histogram]))
        }
        var metadata = asset.metadata.filter { $0.0 != "文件" }
        if !edits.isIdentity, let cg = displayedCG { metadata.insert(("当前预览", "\(cg.width) × \(cg.height) px"), at: 1) }
        let captureFields: Set<String> = ["相机", "厂商", "拍摄时间", "镜头", "光圈", "曝光时间（秒）", "ISO", "焦距（mm）"]
        let fileRows = metadata.filter { !captureFields.contains($0.0) }
        let captureRows = metadata.filter { captureFields.contains($0.0) }
        inspector.add(inspectorSection("图像", views: fileRows.map { inspectorRow($0.0 == "尺寸" ? "原始尺寸" : $0.0, value: $0.1) }))
        if !captureRows.isEmpty {
            inspector.add(inspectorSeparator())
            inspector.add(inspectorSection("拍摄信息", views: captureRows.map { inspectorRow($0.0, value: $0.1) }))
        }
        let path = label(asset.url.deletingLastPathComponent().path, size: 11, color: .secondaryLabelColor)
        path.isSelectable = true; path.toolTip = path.stringValue
        inspector.add(path)
        for (title, help, action, enabled) in [
            ("Finder", "在 Finder 中显示原文件", #selector(reveal(_:)), true),
            ("识别文字", "识别图片中的文字", #selector(recognizeText(_:)), displayedCG != nil),
            ("取色", "取色并复制 HEX 色号", #selector(pickColor(_:)), !samplingColor)
        ] {
            let button = NSButton(title: title, target: self, action: action)
            button.bezelStyle = .rounded; button.toolTip = help; button.setAccessibilityLabel(help); button.isEnabled = enabled
            inspector.footer.addArrangedSubview(button)
        }
        inspector.footer.distribution = .fillEqually
    }

    private func buildImageAdjustments(_ asset: ImageAsset) {
        let transforms = NSSegmentedControl(labels: ["左转", "右转", "镜像"], trackingMode: .momentary, target: self, action: #selector(transformImage(_:)))
        transforms.segmentStyle = .rounded
        for (index, symbol) in ["rotate.left", "rotate.right", "arrow.left.and.right.righttriangle.left.righttriangle.right"].enumerated() {
            transforms.setImage(NSImage(systemSymbolName: symbol, accessibilityDescription: nil), forSegment: index)
            transforms.setToolTip(["向左旋转 90°", "向右旋转 90°", "水平镜像"][index], forSegment: index)
        }
        inspector.add(transforms)
        let popup = NSPopUpButton()
        popup.addItems(withTitles: ImageEdits.filters.map(\.0))
        popup.selectItem(at: ImageEdits.filters.firstIndex { $0.1 == edits.filter } ?? 0)
        popup.target = self; popup.action = #selector(filterChanged(_:)); popup.setAccessibilityLabel("照片滤镜")
        inspector.add(inspectorSection("滤镜", views: [popup]))
        let values: [(String, String, Double, Double, Double)] = [
            ("brightness", "亮度", edits.brightness, -1, 1), ("contrast", "对比度", edits.contrast, 0, 2),
            ("saturation", "饱和度", edits.saturation, 0, 2), ("exposure", "曝光", edits.exposure, -2, 2)
        ]
        var rows: [NSView] = []
        for (key, title, value, minimum, maximum) in values {
            let number = label(String(format: "%.2f", value), size: 11, color: .secondaryLabelColor)
            number.font = .monospacedDigitSystemFont(ofSize: 11, weight: .regular)
            number.alignment = .right; number.widthAnchor.constraint(equalToConstant: 42).isActive = true
            sliderLabels[key] = number
            let slider = NSSlider(value: value, minValue: minimum, maxValue: maximum, target: self, action: #selector(sliderChanged(_:)))
            slider.identifier = NSUserInterfaceItemIdentifier(key); slider.isContinuous = true; slider.setAccessibilityLabel(title)
            let caption = label(title, size: 12)
            caption.widthAnchor.constraint(equalToConstant: 42).isActive = true
            let row = NSStackView(views: [caption, slider, number])
            row.spacing = 10; row.alignment = .centerY
            rows.append(row)
        }
        inspector.add(inspectorSection("色调", views: rows))
        let note = label(asset.frameCount > 1 ? "动画使用首帧调整；导出会另存为图片。" : "调整用于预览，导出会另存为图片。", size: 11, color: .secondaryLabelColor)
        note.maximumNumberOfLines = 2; note.lineBreakMode = .byWordWrapping
        inspector.add(note)
        let reset = NSButton(title: "重置", target: self, action: #selector(resetEdits(_:)))
        let export = NSButton(title: "导出图片…", target: self, action: #selector(exportImage(_:)))
        [reset, export].forEach { $0.bezelStyle = .rounded }
        inspector.footer.distribution = .fill
        inspector.footer.addArrangedSubview(reset)
        inspector.footer.addArrangedSubview(NSView())
        inspector.footer.addArrangedSubview(export)
    }

    func layoutInspector() {
        inspector.layoutSubtreeIfNeeded()
        guard let panel = inspectorPanel else { return }
        let area = panel.screen?.visibleFrame ?? screenArea
        let height = min(inspector.preferredHeight, max(220, area.height - 60))
        let top = panel.frame.maxY
        panel.setContentSize(NSSize(width: 320, height: height))
        panel.setFrameOrigin(NSPoint(
            x: max(area.minX, min(panel.frame.minX, area.maxX - panel.frame.width)),
            y: max(area.minY, min(top - panel.frame.height, area.maxY - panel.frame.height))
        ))
    }

    @objc func transformImage(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: rotateLeft(sender)
        case 1: rotateRight(sender)
        default: flip(sender)
        }
    }
}
