ViaView 应用图标构建资源

lighthouse.pdf 与 lighthouse-small.pdf 是已确认 SVG 的矢量 PDF 导出。
scripts/Icon.swift 使用 macOS Core Graphics 直接按目标尺寸渲染 PDF；正常构建不需要第三方工具。
scripts/build.sh 随后生成 AppIcon.icns，写入应用资源目录并签名。

唯一设计源稿位于：
design/viaview-lighthouse/viaview-icon.svg
design/viaview-lighthouse/viaview-icon-small.svg

修改源稿后，从仓库根目录运行以下命令同步 PDF（此维护步骤需要 librsvg）：
rsvg-convert --format pdf design/viaview-lighthouse/viaview-icon.svg -o Resources/AppIcon/lighthouse.pdf
rsvg-convert --format pdf design/viaview-lighthouse/viaview-icon-small.svg -o Resources/AppIcon/lighthouse-small.pdf

常规构建：zsh scripts/build.sh
16 pt 的 1x / 2x 均使用小尺寸源稿；32 pt 及以上使用带塔身窗户的主图。
ICNS 包含 16、32、64、128、256、512、1024 像素规格，共 10 个表示。
