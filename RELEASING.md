# 发布与自动更新

## 固定发布位置

- 仓库：<https://github.com/ifzeid/walkie-talkie>
- 更新源：<https://github.com/ifzeid/walkie-talkie/releases/latest/download/appcast.xml>
- 安装包：每个 tag 的不可变 Release 附件，例如 `releases/download/v1.3.0/Walkie-Talkie-1.3.0.zip`。
- 每个 Release 包含签名安装包和 `appcast.xml`；客户端通过 latest 地址找到当前版本，再从固定 tag 下载 ZIP。

## 常规发布

1. 提升 `Resources/Info.plist` 的 `CFBundleShortVersionString` 和 `CFBundleVersion`，构建号必须单调递增。
2. 新增 `ReleaseNotes/VERSION.md`；完成检查并提交代码，工作区保持干净。
3. 在已登录 GitHub CLI 且持有原更新签名密钥的 Mac 上执行：

```sh
python3 Scripts/publish-release.py
```

脚本检查仓库与内置更新源匹配，构建应用，使用 Sparkle 官方 `sign_update` 生成 Ed25519 签名，使用内置公钥验证 ZIP 并确认篡改文件被拒绝，然后推送代码/tag、上传草稿附件，最后发布。已经存在的版本不会被覆盖。每次本地准备使用独立的 `Releases/VERSION-随机后缀/` 目录，便于在签名授权或网络失败后重试。

如果网络中断留下草稿，先在 GitHub 检查该草稿的附件和 tag；不要改写已经公开的同版本 ZIP。签名失败时不得发布未签名文件或更换公钥来绕过问题。

发布后检查固定更新源能以未登录方式下载，并在旧版应用中验证「检查 → 下载 → 安装并重启」。新版需保持相同 bundle identifier 和应用包名称。

## 首次连接旧版客户端

1.2.x 已携带 Sparkle 和同一验证公钥，但没有内置发布地址。在「设置 → 软件更新」中填入上述更新源并保存，即可通过应用内更新安装最新版本。无需手动覆盖。1.3.0 起内置地址。

## 签名与密钥

更新引擎固定为 Sparkle 2.10.0。更新验证公钥位于 Info.plist；对应私钥位于发布者本机 login Keychain，account 为 `app.walkietalkie.translator.updates`。

**不要导出私钥到项目、日志、安装包或 GitHub。** 使用官方 `generate_keys` 的备份流程时，应单独保管。不要重新生成并替换公钥，否则旧客户端无法验证更新。首次运行官方签名工具时，macOS 可能要求由用户在系统窗口中授权访问发布密钥。

当前构建仅有 ad-hoc 代码签名。Ed25519 保护更新文件，Apple 代码签名决定应用身份和 Gatekeeper/钥匙串行为。若要保持升级后密钥免迁移，并减少首次安装限制，应使用固定 Developer ID Application 证书签名及公证。已有客户端首次从 ad-hoc 转换为证书签名时仍可能需要迁移密钥。

```sh
WALKIE_SIGN_IDENTITY='Developer ID Application: YOUR NAME (TEAMID)' \
python3 Scripts/publish-release.py
```

现有构建脚本支持同一证书签名所有嵌套组件；不自动申请证书或执行公证。

## 单独准备文件

```sh
./Scripts/build.sh
python3 Scripts/prepare-release.py \
  --output Releases/1.3.0 \
  --notes ReleaseNotes/1.3.0.md \
  --download-prefix https://github.com/ifzeid/walkie-talkie/releases/download/v1.3.0/
```

仅准备文件不会公开发布。`Releases/`、`dist/` 和 `.build/` 均排除在 Git 之外。

[官方 Sparkle 发布文档](https://sparkle-project.org/documentation/publishing/)
