import AppKit
import ViewerCore

extension ViewerController {
    func move(_ delta: Int) {
        guard gallery.urls.count > 1 else { return }
        let before = gallery.index
        let wrap = UserDefaults.standard.object(forKey: "wrap") == nil || UserDefaults.standard.bool(forKey: "wrap")
        gallery.move(delta, wrap: wrap)
        if gallery.index != before { loadCurrent() } else if timer != nil { slideshow(nil) }
    }
    @objc func previous(_ sender: Any?) { move(-1) }
    @objc func next(_ sender: Any?) { move(1) }
    func reorderGallery() {
        sortRevision += 1
        let revision = sortRevision, context = galleryRevision
        let urls = gallery.urls, order = sort, reversed = descending
        guard !urls.isEmpty else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let ordered = Gallery.ordered(urls, by: order, descending: reversed)
            DispatchQueue.main.async {
                guard let self, self.galleryRevision == context, self.sortRevision == revision else { return }
                // Navigation and recycling can happen while sorting. Keep the live
                // selection and only reorder members still present in this gallery.
                let remaining = Set(self.gallery.urls)
                self.gallery = Gallery(urls: ordered.filter(remaining.contains), selected: self.gallery.current)
                self.updateUI()
            }
        }
    }
    @objc func grantFolder(_ sender: Any?) {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.directoryURL = gallery.current?.deletingLastPathComponent(); panel.message = "选择图片所在文件夹以浏览相邻图片"; panel.prompt = "允许此文件夹"
        if panel.runModal() == .OK, let url = panel.url { FileAccessStore.shared.retain(url); openURLs([gallery.current ?? url]) }
    }
    @objc func slideshow(_ sender: Any?) {
        if let timer { timer.invalidate(); self.timer = nil }
        else if gallery.urls.count > 1 {
            let interval = UserDefaults.standard.integer(forKey: "slideDelay")
            timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(interval > 0 ? interval : 3), repeats: true) { [weak self] _ in self?.move(1) }
        }
        updateSlideshowButton()
    }
    func updateSlideshowButton() {
        buttons["play"]?.image = (timer == nil ? ToolbarIcon.play : .pause).image
        buttons["play"]?.toolTip = timer == nil ? "开始幻灯片 · 空格" : "暂停幻灯片 · 空格"
        buttons["play"]?.setAccessibilityLabel(timer == nil ? "开始幻灯片" : "暂停幻灯片")
    }
}
