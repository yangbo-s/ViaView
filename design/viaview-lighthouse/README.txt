ViaView · 灯塔图标
2026-10-09

设计
以参考照片中的红色圆顶、白色灯塔和碧蓝海水为主体。
采用圆润几何、平面色块和开放留白，呼应 Slack 的轻快视觉语言。
塔身与浪线相连；省去栏杆、梯子、植被和建筑等小尺寸下难以辨认的细节。

文件
viaview-icon.svg         主图；浅色圆角底，1024 × 1024，512 单位设计网格。
viaview-mark.svg         透明底标志；保留白色塔身与白色浪线，无应用底板。
viaview-icon-dark.svg    深色圆角底；提亮灯室、平台与小窗，改善背景分离。
viaview-icon-small.svg   16–24 px 光学校正版；32 单位网格，放大灯光，删除小窗。
viaview-icon-square.svg  铺满画布的方形底；供需要由系统应用遮罩的流程使用。
viaview-icon.png         1024 × 1024 PNG 导出。
preview.png              512 × 512 PNG 预览。
design-sheet.png         主图、深色版、透明底标志、尺寸与色板总览。
size-check.png           实际 16 / 24 / 32 / 48 / 64 px 导出及像素放大检查。

矢量结构
所有 SVG 图标仅使用 path、rect 和 group，带命名图层与无障碍描述。
没有嵌入位图、字体、外部资源、描边、滤镜或渐变，可直接编辑颜色与节点。
主图中标志占画布宽度 62.5%，四周留白；视觉中心上移 2 个设计单位。
32 px 及以上使用主图；16–24 px 使用 small 版。
小尺寸导出请按最终目标尺寸直接渲染 SVG，避免反复缩放 PNG。

配色（sRGB）
珊瑚红   #ED626F
暖黄     #FFCB68
浅海青   #36C5CF
海蓝     #089EBD
深海蓝   #153F59
暖白     #FFFDF8
深色底   #102D40
深色版灯室 #397892

平台使用
圆角底版适合展示及传统静态图标资源。
需要系统施加形状遮罩时，从 square 版或分离的矢量图层开始，避免重复裁切圆角。
本次交付为图标设计资产；不包含 Icon Composer 工程或应用打包产物。
图标简化、矢量缩放与系统遮罩的设计参考：
Apple Human Interface Guidelines — App icons
https://developer.apple.com/design/human-interface-guidelines/app-icons/

验证
已检查 SVG XML、图层 ID、描述引用、纯矢量元素、文件尺寸与独立渲染。
已目视检查浅色 / 深色 / 透明底版，以及 16、24、32、48、64、128 px 显示。
16 px 的灯光与光束会受到像素混色影响，故使用放大灯光、删去小窗的专用版本。
