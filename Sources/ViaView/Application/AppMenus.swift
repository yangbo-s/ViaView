import AppKit
import Sparkle

func menuItem(_ title: String, _ action: Selector?, _ key: String = "", modifiers: NSEvent.ModifierFlags = .command, target: AnyObject? = nil) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
    item.keyEquivalentModifierMask = modifiers; item.target = target
    return item
}

extension AppDelegate {
    func configureMenus() {
        let main = NSMenu(); NSApp.mainMenu = main
        func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenu {
            let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
            let child = NSMenu(title: title); parent.submenu = child; main.addItem(parent)
            items.forEach { child.addItem($0) }; return child
        }
        _ = submenu("ViaView", [menuItem("关于 ViaView", #selector(about(_:)), target: self), .separator(), menuItem("设置…", #selector(preferences(_:)), ",", target: self), menuItem("清空图像缓存", #selector(clearCache(_:)), target: self), .separator(), menuItem("隐藏 ViaView", #selector(NSApplication.hide(_:)), "h"), menuItem("退出 ViaView", #selector(NSApplication.terminate(_:)), "q")])
        let file = submenu("文件", [menuItem("打开图片或文件夹…", #selector(open(_:)), "o", target: self), menuItem("新窗口", #selector(newWindow(_:)), "n", target: self)])
        main.items.first?.submenu?.insertItem(menuItem("检查更新…", #selector(SPUStandardUpdaterController.checkForUpdates(_:)), target: updaterController), at: 1)
        let recent = NSMenuItem(title: "最近打开", action: nil, keyEquivalent: ""); recentMenu = NSMenu(); recentMenu.delegate = self; recent.submenu = recentMenu; file.addItem(recent)
        [NSMenuItem.separator(), menuItem("导出图片…", #selector(ViewerController.exportImage(_:)), "s", modifiers: [.command, .shift]), menuItem("打印…", #selector(ViewerController.printImage(_:)), "p"), menuItem("在 Finder 中显示", #selector(ViewerController.reveal(_:)), "r", modifiers: [.command, .shift]), menuItem("用外部编辑器打开", #selector(ViewerController.openEditor(_:))), menuItem("编辑 Finder 标签…", #selector(ViewerController.editTags(_:))), .separator(), menuItem("移到废纸篓", #selector(ViewerController.moveToTrash(_:)), String(UnicodeScalar(NSBackspaceCharacter)!)), .separator(), menuItem("关闭窗口", #selector(NSWindow.performClose(_:)), "w")].forEach { file.addItem($0) }
        _ = submenu("编辑", [menuItem("剪切", #selector(NSText.cut(_:)), "x"), menuItem("复制图片 / 选区", #selector(copyContent(_:)), "c", target: self), menuItem("粘贴", #selector(NSText.paste(_:)), "v"), menuItem("全选", #selector(NSText.selectAll(_:)), "a"), .separator(), menuItem("复制文件路径", #selector(ViewerController.copyPath(_:)), "c", modifiers: [.command, .option]), menuItem("取色并复制 HEX", #selector(ViewerController.pickColor(_:)), "c", modifiers: [.command, .shift]), .separator(), menuItem("向右旋转", #selector(ViewerController.rotateRight(_:)), "r"), menuItem("向左旋转", #selector(ViewerController.rotateLeft(_:)), "l"), menuItem("水平镜像", #selector(ViewerController.flip(_:))), menuItem("重置所有调整", #selector(ViewerController.resetEdits(_:))), .separator(), menuItem("识别图片文字…", #selector(ViewerController.recognizeText(_:)), "t", modifiers: [.command, .shift])])
        _ = submenu("显示", [menuItem("上一张", #selector(ViewerController.previous(_:)), String(UnicodeScalar(NSLeftArrowFunctionKey)!), modifiers: []), menuItem("下一张", #selector(ViewerController.next(_:)), String(UnicodeScalar(NSRightArrowFunctionKey)!), modifiers: []), .separator(), menuItem("放大", #selector(ViewerController.zoomIn(_:)), "="), menuItem("缩小", #selector(ViewerController.zoomOut(_:)), "-"), menuItem("适应窗口", #selector(ViewerController.fit(_:)), "0"), menuItem("实际大小", #selector(ViewerController.actualSize(_:)), "1"), .separator(), menuItem("文件列表", #selector(ViewerController.toggleFileList(_:)), "b"), menuItem("图片信息", #selector(ViewerController.toggleInfo(_:)), "i"), menuItem("图像调整", #selector(ViewerController.toggleAdjustments(_:)), "f"), menuItem("取色并复制色号", #selector(ViewerController.pickColor(_:)), "e"), menuItem("动画播放 / 暂停", #selector(ViewerController.toggleAnimation(_:))), menuItem("幻灯片播放 / 暂停", #selector(ViewerController.slideshow(_:)), " ", modifiers: []), .separator(), menuItem("进入 / 退出全屏", #selector(ViewerController.fullscreen(_:)), "f", modifiers: [.command, .control])])
        let windows = submenu("窗口", [menuItem("最小化", #selector(NSWindow.performMiniaturize(_:)), "m"), menuItem("窗口置顶", #selector(ViewerController.alwaysOnTop(_:)), "a", modifiers: [.command, .option]), menuItem("全部置前", #selector(NSApplication.arrangeInFront(_:)))]); NSApp.windowsMenu = windows
        NSApp.helpMenu = submenu("帮助", [menuItem("快捷键", #selector(shortcuts(_:)), target: self)])
    }
}
