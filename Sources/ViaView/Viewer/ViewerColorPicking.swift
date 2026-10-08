import AppKit
import ViewerCore

extension ViewerController {
    @objc func pickColor(_ sender: Any?) {
        guard gallery.current != nil, !samplingColor else { return }
        samplingColor = true; timer?.invalidate(); timer = nil; updateSlideshowButton()
        setChrome(false); topChrome.isHidden = true; bottomChrome.isHidden = true; colorFeedback.isHidden = true
        window?.displayIfNeeded()
        NSColorSampler().show { [weak self] color in
            guard let self else { return }
            self.samplingColor = false
            if let hex = ColorHex.copy(color) {
                self.feedbackGeneration += 1; let generation = self.feedbackGeneration
                self.colorFeedback.stringValue = "已复制 \(hex)"; self.colorFeedback.isHidden = false
                NSAccessibility.post(element: self.colorFeedback, notification: .announcementRequested, userInfo: [.announcement: "已复制色号 \(hex)", .priority: NSAccessibilityPriorityLevel.medium.rawValue])
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) { [weak self] in
                    if self?.feedbackGeneration == generation { self?.colorFeedback.isHidden = true }
                }
            }
            self.refreshChrome()
        }
    }
}
