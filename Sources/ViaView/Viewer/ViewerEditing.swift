import AppKit
import ViewerCore

extension ViewerController {
    @objc func rotateRight(_ sender: Any?) { edits.turns = (edits.turns + 1) % 4; applyEdits() }
    @objc func rotateLeft(_ sender: Any?) { edits.turns = (edits.turns + 3) % 4; applyEdits() }
    @objc func flip(_ sender: Any?) { edits.flipped.toggle(); applyEdits() }
    @objc func filterChanged(_ sender: NSPopUpButton) { edits.filter = ImageEdits.filters[sender.indexOfSelectedItem].1; applyEdits() }
    @objc func sliderChanged(_ sender: NSSlider) {
        guard let key = sender.identifier?.rawValue else { return }
        let title: String
        switch key {
        case "brightness": edits.brightness = sender.doubleValue; title = "亮度"
        case "contrast": edits.contrast = sender.doubleValue; title = "对比度"
        case "saturation": edits.saturation = sender.doubleValue; title = "饱和度"
        default: edits.exposure = sender.doubleValue; title = "曝光"
        }
        sliderLabels[key]?.stringValue = String(format: "%@    %.2f", title, sender.doubleValue); applyEdits()
    }
    @objc func resetEdits(_ sender: Any?) { edits = ImageEdits(); applyEdits(); rebuildInspector() }
    func applyEdits() {
        guard let asset, let original = asset.cgImage else { return }
        editSerial += 1; let editID = editSerial, loadID = loadSerial, edits = self.edits
        editOperation?.cancel()
        editPending = true
        let operation = BlockOperation(); editOperation = operation
        operation.addExecutionBlock { [weak self, weak operation] in
            guard operation?.isCancelled == false else { return }
            let result = Result { try edits.render(original) }
            DispatchQueue.main.async {
                guard let self, self.editSerial == editID, self.loadSerial == loadID else { return }
                self.editPending = false
                switch result {
                case .success(let cg):
                    self.displayedCG = cg
                    self.canvas.image = edits.isIdentity ? asset.image : NSImage(cgImage: cg, size: .zero)
                    self.canvas.animates = edits.isIdentity && asset.canAnimate
                    self.canvas.frame.size = NSSize(width: cg.width, height: cg.height); self.canvas.selection = .zero
                    self.zoomDriver.reset(self.scroll.magnification)
                    self.updateWindowLimits(); self.applyZoom(self.scroll.magnification, centerImage: true); self.updateUI()
                    if self.inspectorMode == .information { self.rebuildInspector() }
                case .failure(let error): self.showError(error)
                }
            }
        }
        editQueue.addOperation(operation)
    }
}
