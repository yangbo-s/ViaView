import AppKit

extension ViewerController {
    // All entry points describe the next action using the same live window state.
    func commandTitle(for action: Selector) -> String? {
        switch action {
        case #selector(recognizeText(_:)):
            return supportsLiveTextForCurrentImage ? (liveText.isEngaged ? "退出文字选择" : "选择图片文字") : "识别图片文字…"
        case #selector(toggleFileList(_:)):
            return fileListPanel?.isVisible == true ? "隐藏文件列表" : "显示文件列表"
        case #selector(toggleInfo(_:)):
            return inspectorPanel?.isVisible == true && inspectorMode == .information ? "隐藏图片信息" : "显示图片信息"
        case #selector(toggleAdjustments(_:)):
            return inspectorPanel?.isVisible == true && inspectorMode == .adjustments ? "隐藏图像调整" : "显示图像调整"
        case #selector(editTags(_:)):
            return tagsPanel?.isVisible == true ? "隐藏 Finder 标签" : "编辑 Finder 标签…"
        case #selector(slideshow(_:)):
            return timer == nil ? "开始幻灯片" : "暂停幻灯片"
        case #selector(toggleAnimation(_:)):
            return canvas.animates ? "暂停动画" : "播放动画"
        case #selector(fullscreen(_:)):
            return window?.styleMask.contains(.fullScreen) == true ? "退出全屏" : "进入全屏"
        case #selector(alwaysOnTop(_:)):
            return window?.level == .floating ? "取消窗口置顶" : "窗口置顶"
        default:
            return nil
        }
    }
}
