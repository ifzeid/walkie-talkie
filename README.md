# 对讲机 · Walkie Talkie

原生 macOS 翻译工具。SwiftUI + AppKit，支持多个 OpenAI 兼容 API、全局快捷键和网页选文翻译。

[下载最新版本](https://github.com/ifzeid/walkie-talkie/releases/latest) · [版本说明](https://github.com/ifzeid/walkie-talkie/releases)

## 使用

1. 下载 Release 中的 ZIP，将「对讲机.app」放到「应用程序」。当前安装包支持 Apple Silicon，最低 macOS 13。
2. 打开设置，添加 API 地址、模型及密钥。支持 DeepSeek、OpenAI 兼容服务及本地 Ollama，可随时切换。
3. 输入或粘贴文字，选择语言，点击「翻译」或按 Command-Return。

原文和译文区域使用相同的底部操作栏：左侧字数与清空，右侧复制。清空原文会同时清除译文；清空译文保留原文。

默认全局快捷键为 Control-Option-Space。菜单栏图标菜单包含打开、粘贴并打开、窗口置顶、快捷键、API 设置与检查更新。

浏览器选中文字后，可在右键「服务」中选择「用对讲机翻译」。服务可见性取决于浏览器对 macOS Services 的支持；首次安装后可能需要重新打开浏览器。全局快捷键和服务不需要屏幕录制权限。

## 应用内更新

1.3.0 起内置 GitHub 更新源。软件会自动检查、下载新版，经签名验证后提示安装并重新启动；也可通过菜单栏「检查更新…」立即检查。

**已安装 1.2.x 的用户无需手动覆盖应用**：在「设置 → 软件更新 → 版本发布地址」填写以下地址并保存，再点击「检查更新」即可：

```text
https://github.com/ifzeid/walkie-talkie/releases/latest/download/appcast.xml
```

自动更新使用 Sparkle，安装包通过内置 Ed25519 公钥验证。更新签名私钥保存在发布者本机钥匙串，不在仓库或应用包中。应用目前仍使用 ad-hoc 代码签名，尚未完成 Apple Developer ID 签名和公证。

## API 密钥与数据

- API 密钥保存在 macOS 钥匙串，不写入源码或更新文件。
- 普通翻译不尝试读取由旧签名或未知签名创建的密钥，以避免系统反复弹出校验。
- 升级后若显示密钥迁移提示，编辑原 API，重新填写密钥并保存即可；名称、地址和模型保留，无需删除 API。
- 当前 ad-hoc 签名会随版本变化。长期保持钥匙串身份连续性需要固定的 Apple 代码签名证书；更新包 Ed25519 签名不能替代它。
- 原文通过你选定的 API 发送给服务商。软件更新不会发送原文、译文或 API 密钥；翻译内容不持久保存。

## 本地构建

需要 macOS、Swift 5.9+ 工具链或兼容 Command Line Tools。依赖 Sparkle 固定版本 2.10.0。

```sh
./Scripts/build.sh
./Scripts/test.sh
```

产物位于 `dist/对讲机.app` 和 `dist/Walkie-Talkie.zip`。构建脚本在临时目录完成签名，避免云盘扩展属性影响签名校验。

## 发布新版本

修改 `Resources/Info.plist` 中的显示版本和递增构建号，新增 `ReleaseNotes/VERSION.md`，提交代码后，在持有既有更新签名密钥的 Mac 上运行：

```sh
python3 Scripts/publish-release.py
```

脚本完成构建、更新签名、签名验证、推送 tag、上传 Release 草稿，再发布为最新版。只有最终发布后，已安装客户端才会收到新版本。不会导出更新私钥，也不会要求将其添加到 GitHub Secrets。

详见 [发布说明](RELEASING.md) 和 [验证记录](VALIDATION.md)。
