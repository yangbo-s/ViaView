import AppKit
import ViewerCore

extension ViewerController {
    @objc func showMore(_ sender: Any?) {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector, key: String = "") {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key); item.target = self; menu.addItem(item)
        }
        add("上一张", #selector(previous(_:))); add("下一张", #selector(next(_:)))
        menu.addItem(.separator())
        add("文件列表", #selector(toggleFileList(_:)), key: "b")
        add("图片信息", #selector(toggleInfo(_:)), key: "i")
        add("图像调整", #selector(toggleAdjustments(_:)), key: "f")
        add("Finder 标签…", #selector(editTags(_:)))
        add("取色并复制色号", #selector(pickColor(_:)), key: "e")
        menu.addItem(.separator())
        add("放大", #selector(zoomIn(_:)), key: "="); add("缩小", #selector(zoomOut(_:)), key: "-")
        add("适应屏幕", #selector(fit(_:)), key: "0"); add("实际大小", #selector(actualSize(_:)), key: "1")
        add("幻灯片播放 / 暂停", #selector(slideshow(_:)))
        add("进入 / 退出全屏", #selector(fullscreen(_:)))
        add("窗口置顶", #selector(alwaysOnTop(_:)))
        menu.addItem(.separator())
        if needsFolderAccess { add("选择图片所在文件夹…", #selector(grantFolder(_:))) }
        add("在 Finder 中显示", #selector(reveal(_:)))
        add("分享图片", #selector(share(_:)))
        add("用\(AppSettings.editorName)打开", #selector(openEditor(_:)))
        add("导出图片…", #selector(exportImage(_:)))
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: moreButton.bounds.minY - 4), in: moreButton)
        refreshChrome()
    }
}
