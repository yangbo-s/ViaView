# 更新构建与发布

ViaView 使用 Sparkle 2.10.0；版本与源码修订锁定在 Package.resolved。应用保留沙盒和原有 bundle identity，更新器由 AppDelegate 持有，设置与菜单共用实例。`UpdateSettingsModel` 通过 KVO 观察 Sparkle，用户切换时才写入其属性；不另建 defaults。原生 Sparkle UI 负责发现更新、取消、错误和重试。最低系统保持 macOS 14，当前公开包为 arm64。

## 密钥与签名

公钥在 Resources/Info.plist 的 SUPublicEDKey；私钥保存在发布机器的登录钥匙串，Sparkle account 为 `ViaView`。私钥不写入仓库、日志、安装包或环境文件。首次配置可运行 `.build/artifacts/sparkle/Sparkle/bin/generate_keys --account ViaView`；它会复用已有密钥。已有用户开始使用后，不能直接换成新公钥，否则旧客户端无法验证后续更新。维护者应安全备份钥匙串；跨机器迁移按照 Sparkle 官方密钥导出/导入流程操作，勿提交导出的私钥。

`SURequireSignedFeed` 和 `SUVerifyUpdateBeforeExtraction` 同时开启，分别验证 appcast 和解包前的 ZIP。签名后不得编辑 appcast 或重新打包 ZIP。`generate-appcast.sh` 首先比对钥匙串和应用公钥，再使用官方 generate_appcast 和 sign_update，最后用 CryptoKit 按应用内公钥独立验证 ZIP。缺少密钥、密钥不符或验证失败时退出非零。

Sparkle 的 Installer.xpc 配合 SUEnableInstallerLauncherService 与应用 ID 对应的 mach-lookup 权限安装更新；应用已有 network.client 权限，因此不启用 Downloader 服务。build.sh 用 ditto 保留 framework 符号链接，按辅助程序、framework、应用顺序签名。

当前版本延续 ad-hoc 签名，尚无 Developer ID 或 Apple 公证。ad-hoc 应用没有 Team ID，构建脚本仅对此模式加入 disable-library-validation 以加载 Sparkle；更新包仍强制 Ed25519 验证。有证书时通过 `VIAVIEW_SIGNING_IDENTITY` 指定签名身份，会保留 library validation；公证需要另外完成。不可把本机 ad-hoc 验证视作 Developer ID 分发验证。

## 发布顺序

1. 更新 Info.plist 的显示版本和递增 build（Sparkle 按 build 比较），同步 README 与 CHANGELOG。
2. 执行 `zsh scripts/check.sh`、`zsh scripts/check-appkit.sh`、`python3 scripts/audit.py`，提交源码。
3. 从该提交构建：`VIAVIEW_GENERATE_APPCAST=1 zsh scripts/package.sh`。DMG、ZIP、SHA256SUMS 和 appcast.xml 位于 dist。普通本地打包省略该变量，不需要发布私钥。
4. 推送源码和对应版本标签；创建 GitHub 草稿 Release 并上传以上四个文件，核对附件 SHA-256。
5. 全部核对后公开并标记 Latest；匿名下载附件，校验哈希和签名，并从真实应用检查更新。

更新 URL 固定为 `https://github.com/yangbo-s/ViaView/releases/latest/download/appcast.xml`。每个新 Latest Release 都必须带有签名 appcast.xml，否则客户端检查会失败。ZIP 的 URL 指向具体版本，不能覆盖旧附件。不要通过删除历史 Release 修正更新错误；修复后递增 build 发布。

签名账户可用 `VIAVIEW_SPARKLE_ACCOUNT` 指定，必须与包内公钥匹配。`VIAVIEW_BUILD_DIR` 可改变构建与工具位置。测试更新安装时使用独立副本与隔离偏好，不降低正式包的版本或替换用户正在使用的应用。

参考：[程序化接入](https://sparkle-project.org/documentation/programmatic-setup/)、[设置状态](https://sparkle-project.org/documentation/preferences-ui/)、[沙盒与签名](https://sparkle-project.org/documentation/sandboxing/)、[更新发布](https://sparkle-project.org/documentation/)。
