# ViaView 架构与状态契约

ViaView 使用 Swift Package 管理源码，以 AppKit 构建原生 macOS 窗口。安装、使用和构建命令见 [README](../README.md)。

## 模块边界

Swift Package 提供 `ViaView` 和 `ViewerChecks` 两个可执行产品，两者依赖 `ViewerCore`。应用依赖 AppKit；核心中的图像与颜色模型也使用系统图像类型，因此 `ViewerCore` 是独立于应用窗口的领域模块，不是跨平台 Foundation-only 库。

| 目录／入口 | 负责 | 边界 |
| --- | --- | --- |
| `Application/ViaViewApp.swift` | 注册默认值、启动 NSApplication | 不承担图片状态 |
| `Application/AppDelegate.swift`、`AppMenus.swift` | Viewer 生命周期、活动窗口解析、全局菜单、打开与最近项目 | 每个 Viewer 独立持有图库和编辑状态 |
| `Application/FileAccessStore.swift` | 安全范围 URL、书签保存／恢复／移除 | 不扫描全盘，不决定图片排序 |
| `Application/AppSettings.swift` | 偏好默认值、应用设置、会话保存、授权后刷新 | 保持 UserDefaults 驱动的异步合并刷新 |
| `Viewer/ViewerController.swift` | 单窗口共享状态、生命周期和能力验证 | 各职责用同模块 extension 分文件；没有另建互相复制状态的控制器 |
| `Viewer/ViewerLoading.swift`、`ViewerGallery.swift` | 打开／扫描／加载、选择、排序、导航和幻灯片 | 排序只作用现有集合，不重新打开图片 |
| `Viewer/ViewerEditing.swift`、`ViewerFileActions.swift` | 预览调整、导出、复制、OCR、分享和打印 | 编辑基于原图；外部写入由明确动作触发 |
| `Viewer/ViewerViewport.swift`、`ZoomDriver.swift`、`ImageCanvas.swift` | 窗口／图像几何、连续缩放、拖动与框选 | 倍率更新不重复解码或套用滤镜 |
| `Viewer/ViewerSVG.swift`、`ViewerContextMenu.swift`、`ViewerColorPicking.swift` | 离线矢量显示、菜单／回收、系统采样 | 平台操作和错误返回归属窗口 |
| `UI` | 工具栏、玻璃、图标、hover、标题、溢出菜单及 Controls／FlippedDocument | 消费 Viewer 状态，不另存图库或编辑模型 |
| `Panels` | 工具窗归属、信息／调整、直方图、文件列表、标签 | 列表是 Viewer 状态的投影；标签按 URL 同步 |
| `Settings` | 五个 NSHostingController 承载的原生表单，包含更新设置 | 偏好即时保存，默认应用变更需用户主动点击；更新偏好由 Sparkle 持久化 |
| `ViewerCore` | Gallery、ImageAsset、ImagePipeline、ImageEdits、SVGDocument、ViewportGeometry、FinderTags、ColorHex、ViewerError | 文件和图像操作可由检查程序独立调用 |
| `ViewerChecks` | CheckRunner、拥有临时目录的 CheckFixtures 和领域检查函数 | 退出前清理自身夹具，不读取用户照片或通用剪贴板历史 |

表中 Application／Viewer／UI／Panels／Settings 均位于 `Sources/ViaView`，核心和检查分别位于 `Sources/ViewerCore`、`Sources/ViewerChecks`。工具栏采用固定控件尺寸，随窗口宽度折叠完整分组。

## 单窗口状态与命令归属

`ViewerController` 持有 `gallery`、`asset`、`displayedCG`、`edits`、视口、播放计时器和三个工具面板。`Gallery` 只管理 URL 集合与当前索引；`ImageAsset` 表示一次加载的原始图像和元数据，`displayedCG` 是最新已完成的编辑预览。

`ViewerToolPanel.owner` 为 weak 引用。面板的 `supplementalTarget(forAction:sender:)` 为图片命令提供所属 Viewer，同时保留原生文字控件的 responder 链。应用的 `activeViewer` 按以下顺序解析：key 工具面板 owner、key 图片窗口、main 图片窗口、仍在窗口集合中的最近活动 Viewer、最后的可用 Viewer。主窗口成为 main 时更新最近活动引用；关闭回调先确认通知来自主窗口，避免把工具面板关闭当成图片窗口退出。

`copyContent` 先交给 key window 的文字编辑器，否则复制已解析 Viewer 的图片／选区。菜单能力验证与顶部按钮复用同一 Viewer 能力判断。后续新增图片命令应沿用该归属机制，不直接以窗口创建顺序推断用户当前目标。

## 异步结果与取消

Operation 取消减少无用工作，序号／身份检查决定结果是否仍可写回；两者不能互相替代。UI 写回位于主队列。

| 状态标记 | 保护的工作 | 写回条件 |
| --- | --- | --- |
| `loadSerial` | 图像加载、SVG 初始化、OCR 和部分操作状态反馈 | 仍属于当前加载；切图／关闭会使旧请求失效 |
| `editSerial` + `loadSerial` | 串行编辑队列 | 编辑版本与原图加载版本同时匹配 |
| `galleryRevision` + `sortRevision` | 目录扫描与后台排序 | 扫描核对图库上下文；排序还核对最后一次排序请求；新目录结果作废旧集合的排序 |
| 缩略图请求对象身份 + 文件版本 | 文件列表后台解码 | 仍是该 URL 当前请求，未取消，修改时间／大小仍匹配 |
| `chromeGeneration`、`feedbackGeneration` | 栏淡出与颜色反馈延迟收起 | 旧完成回调不得覆盖新可见状态 |

打开新内容会取消旧加载／编辑并清空可操作的图像状态，但保留上一张已渲染的画面，直到新内容或错误就绪。未显示的新窗口暂缓 `showWindow`，成功或失败时统一完成显示；关闭会取消待显示标记。单个文件立即解码，目录扫描独立补全邻图；多个明确选择的文件直接形成图库。隐藏的图片信息面板只在用户打开时构建。

排序调用 `Gallery.ordered`：按指定字段排序，用文件名与完整路径处理相同键；落地时保留实时当前 URL，只保留仍在当前图库的成员。排序期间导航或回收不会被旧结果反向恢复。目录扫描期间用户改变排序时，扫描完成后按当前设置重新排序；文件夹授权回填同样核对最新排序选择。

编辑队列每窗并发为 1，只应用最后请求；图像加载与低优先级邻图预取共享最多 2 个解码任务。缓存命中的加载同样返回可取消 Operation，并在主 OperationQueue 调用完成函数。SVG 使用独立待显示 WebView，在导航完成后替换旧内容；切图与关闭解除旧代理并核对回调身份。全尺寸内容延伸至标题栏下方，因此本地事件路由先排除原生窗口按钮，再处理 SVG 拖动。

文件类型的 `FileTypeSettingsModel` 通过 `FileTypeAssociationClient` 读写 NSWorkspace。单项与批量共用串行流程，跳过已关联的类型，禁止重入，逐项回读实际关联并汇总失败。判断 ViaView 使用 bundle identifier；同名应用不视为已设置。回归检查注入替身，不修改用户的系统关联。

## 主题与初始偏好

`AppSettings.register` 在应用创建窗口之前注册默认值，首次安装的 `themeMode` 为 `system`，授权书签和待恢复图片列表为空。注册域只提供缺失值，不覆盖用户保存的设置；升级仅在尚未保存新主题且持久域存在旧 `darkCanvas` 值时，将其迁移为 `light` 或 `dark`。不存在持久偏好的新用户不会迁移到旧版的浅色默认。安装包仅包含应用代码与资源，不包含开发者的 UserDefaults。

`AppTheme` 通过 `NSApplication.appearance` 应用全局外观，`system` 清除强制外观以继承 macOS；设置和工具窗口沿用该继承。全屏只对主图局部覆盖深色并保留纯黑背景，退出后移除覆盖。`WorkspaceView.viewDidChangeEffectiveAppearance` 更新画布的 CGColor 和标题对比度，使运行中的系统外观变化即时生效。

## 缓存与图像边界

`ImagePipeline` 的 NSCache 默认预算为 256 MiB、最多 12 项，设置预算限制为 64–2048 MiB。`ImageAsset.cost` 按解码缓冲区与可播放帧数保守估算，并防止整数溢出；这不是进程实际内存测量。缓存命中必须匹配文件修改时间和大小。

`FileListController` 独立维护最多 240 项／16 MiB 的缩略图缓存，后台并发为 2。同 URL 同版本的请求合并；更新时检查可见项，只有集合或版本变化才重载对应内容。解码前显示原生文件图标，nil 结果继续保留图标。清理／取消后的旧请求不能重新填充面板缓存或覆盖新图。

菜单与设置均经 `AppDelegate.clearImageCaches()` 清理主图缓存和各窗口缩略图缓存；该操作不重置当前显示或编辑。文件版本由修改时间和大小识别，不是内容哈希；没有承诺主动监视所有外部文件变化。

静态位图最长边受限为 8192 px；动画解码预算或尺寸超限时仅保留首帧预览。`ImageEdits` 从原图生成结果，导出明确提示受限预览尺寸。SVG 输入限制体积并验证 XML 根节点；显示层禁用 JavaScript，采用 nonPersistent 数据存储、内容规则、CSP 和 about/data 导航白名单。

## 权限、标签和设置

`FileAccessStore` 从现有 UserDefaults 的 `bookmarks` 恢复安全范围访问，保留用户明确选择的 URL。移除文件夹授权停止对应访问并移除保存记录，不删除文件；单文件授权可以独立保留。启动恢复仅尝试仍可读的保存路径，不能把会话路径当作新的磁盘授权。

`Resources/Info.plist` 的 bundle identifier 继续为 `local.ChengTu`，用于继承已有沙盒容器、偏好与书签；Package、target、入口、资源 bundle 和开发文件名均使用 ViaView。修改身份需要独立的数据迁移方案，不能当作普通文本重命名。

`FinderTags` 在写入前重新读取完整标签，保留其他名称和颜色；二进制 plist xattr 表达多标签，旧 label 字段做兼容处理。主写入失败时保留原始错误，恢复旧 label 若也失败则附加恢复诊断。`TagsPanelController` 在成功后发送 `didChangeNotification`，`changedURLKey` 携带标准化 URL，其他已加载同文件面板刷新，发送者跳过自己。写失败先重新读取恢复界面；自动读取失败仅显示不可用状态，不能把七色假作全部未选或反复弹出同一错误。

设置由 `@AppStorage`／UserDefaults 驱动。`AppDelegate.scheduleSettingsRefresh()` 将通知合并到下一次主队列执行，再应用背景、绘制、缓存预算和幻灯片间隔。必须保留该异步边界：原生控件布局本身可能注册 defaults，同步调用 `updateUI()` 会重入系统布局。文件夹新增授权可刷新相应窗口的相邻图片集合，并保留当前倍率与未导出调整。

## 工具链、资源与交付

Sparkle 由 SwiftPM 锁定为 2.10.0。AppDelegate 持有唯一 SPUStandardUpdaterController，启动时启用调度；更新页通过 UpdateSettingsModel 观察 canCheckForUpdates、自动检查/安装、最后检查时间。关闭自动检查会使自动安装不可用，但保留先前安装偏好。检查按钮和菜单遵守更新器的可用状态，下载、校验、安装与错误 UI 委托 Sparkle。沙盒 XPC、密钥、发布流程及 ad-hoc 限制见 [更新发布说明](UPDATES.md)。

`build.sh` 和 `check.sh` 共用 `scripts/lib/toolchain.zsh` 选择工具链、SDK 和缓存路径；使用者可显式设置 `DEVELOPER_DIR`、`VIAVIEW_REQUIRE_MODERN`、`VIAVIEW_BUILD_DIR`。严格模式要求 SDK 26+；旧 `VIA_VIEW_REQUIRE_MODERN` 仅作为弃用别名。选择工具链不修改全局 Xcode 设置。

共享构建函数使用 `--build-system native --sdk`。该兼容处理用于确保实际 Mach-O SDK 标记与所选 SDK 一致；迁移构建引擎前必须让同一校验成立。`build.sh` 校验标记后，在 `dist` 的临时 staging 中放入可执行文件、Info.plist、图标和 `ViaView_ViaView.bundle`，签名并执行严格验证。只有暂存应用通过后才替换既有同身份产物；失败时清理 staging，必要时恢复原产物。同名但不同 bundle ID 的应用拒绝覆盖。

`ToolbarIcons` 优先加载应用 `Contents/Resources` 内的 Lucide 资源，`Bundle.module` 保留开发回退。来源、哈希及许可位于 `Sources/ViaView/Resources/Lucide`。`python3 scripts/audit.py` 只读检查名称、部署版本、资源哈希／许可、当前文档链接与设计侧车源码路径。`scripts/package.sh` 在构建后生成 DMG、ZIP 和 SHA-256 校验文件；DMG 包含应用与 Applications 快捷入口。
