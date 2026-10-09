# ViaView

轻巧的 macOS 原生看图应用。让图片占据窗口，把操作留在需要时。

[下载 DMG](https://github.com/yangbo-s/ViaView/releases/download/v0.1.3/ViaView-0.1.3-arm64.dmg) · [下载 ZIP](https://github.com/yangbo-s/ViaView/releases/download/v0.1.3/ViaView-0.1.3-arm64.zip) · [更新记录](CHANGELOG.md)

## 安装

需要 **macOS 14 或更新版本、Apple Silicon Mac**。macOS 26 及更新版本提供 Liquid Glass 界面。

1. 下载并打开 DMG。
2. 将 **ViaView** 拖入 **Applications**。
3. 从“应用程序”打开 ViaView，拖入图片即可浏览。

当前版本尚未经过 Apple 公证。首次打开如遇系统提示，可在“系统设置 → 隐私与安全性”中选择“仍要打开”。[Apple 操作说明](https://support.apple.com/zh-cn/102445)

## 功能

- **专注浏览**：窗口随图片比例与缩放调整，鼠标移到顶部或底部时显示工具栏。
- **顺手导航**：文件列表、缩略图网格、自然排序、幻灯片、全屏和窗口置顶。
- **图像调整**：旋转、镜像、亮度、对比度、饱和度、曝光和滤镜，导出为 PNG、JPEG 或 TIFF。
- **查看与提取**：EXIF、直方图、框选复制、取色复制 HEX、本地文字识别。
- **融入 macOS**：Finder 标签、分享、打印、外部编辑器和文件夹授权管理。

支持 JPEG、PNG、GIF、WebP、HEIC、TIFF、SVG、PDF 等格式；RAW 使用 macOS 图像框架解码。

## 操作

滚轮或双指捏合缩放，拖动平移，`⌘` + 拖动框选。打开文件夹后，可连续浏览其中的图片。

| 快捷键 | 操作 |
| --- | --- |
| `⌘O` / `⌘N` | 打开 / 新窗口 |
| `←` / `→` | 上一张 / 下一张 |
| `⌘=` / `⌘-` | 放大 / 缩小 |
| `⌘0` / `⌘1` | 适应窗口 / 实际大小 |
| `⌘B` / `⌘I` / `⌘F` | 文件列表 / 图片信息 / 图像调整 |
| `⌘R` / `⌘L` | 向右 / 向左旋转 |
| `⌘C` | 复制图片或选区 |
| `⌘E` | 取色并复制 HEX |
| `⌘⇧T` | 识别文字 |
| `⌘⇧S` | 导出图片 |
| 空格 | 播放 / 暂停幻灯片 |
| `Esc` / `Delete` | 退出全屏 |
| `⌘,` | 设置 |

更多快捷键可在“设置 → 快捷键”中搜索。

在“设置 → 通用 → 外观”选择跟随系统、浅色或深色。首次安装默认跟随系统，其余选项使用应用默认值；升级保留已有偏好。全屏看图始终使用黑色背景。

## 从源码构建

使用 Xcode 16 或更新版本；Liquid Glass 构建使用 macOS 26+ SDK。

```sh
git clone https://github.com/yangbo-s/ViaView.git
cd ViaView
zsh scripts/build.sh
open dist/ViaView.app
```

检查与打包：

```sh
zsh scripts/check.sh
zsh scripts/check-appkit.sh
python3 scripts/audit.py
zsh scripts/package.sh
```

应用和安装包输出到 `dist/`。`DEVELOPER_DIR` 可指定 Xcode，`VIAVIEW_BUILD_DIR` 可指定构建目录，`VIAVIEW_REQUIRE_MODERN=1` 可要求使用 macOS 26+ SDK。

项目使用 Swift、AppKit 和系统图像框架。模块与状态设计见 [架构说明](docs/ARCHITECTURE.md)。

## 许可

[MIT License](LICENSE)。工具栏图标来自 [Lucide](https://lucide.dev/)，许可随[图标资源](Sources/ViaView/Resources/Lucide/LICENSE)提供。
