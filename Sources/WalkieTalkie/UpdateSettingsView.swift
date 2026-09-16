import SwiftUI

struct UpdateSettingsView: View {
    @ObservedObject var updater: UpdateManager
    @ViewState private var draftFeed = ""
    @ViewState private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.triangle.2.circlepath.circle.fill").font(.system(size: 36)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 4) {
                    Text("软件更新").font(.system(size: 21, weight: .semibold))
                    Text("对讲机 \(updater.version)").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
            }
            VStack(alignment: .leading, spacing: 14) {
                Toggle("自动检查新版本", isOn: $updater.automaticChecks)
                Toggle("自动下载更新，准备好后提示安装", isOn: $updater.automaticDownloads)
                    .disabled(!updater.automaticChecks)
                Text("每天检查一次。下载完成后通过原生更新窗口安装并重新启动，对话中的文字不会保存。")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }.disabled(!updater.started)
            HStack {
                Button("检查更新…") { updater.checkForUpdates(nil) }
                    .buttonStyle(.borderedProminent).disabled(!updater.started || !updater.canCheck)
                if let date = updater.lastCheck {
                    Text("上次检查：\(date.formatted(date: .abbreviated, time: .shortened))").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("版本发布地址").font(.system(size: 12, weight: .medium))
                HStack {
                    TextField("https://你的域名/appcast.xml", text: $draftFeed).textFieldStyle(.roundedBorder)
                    Button("保存") {
                        do { try updater.saveFeed(draftFeed); error = nil }
                        catch { self.error = error.localizedDescription }
                    }.disabled(updater.started && !updater.canCheck)
                }
                Text("填写 Sparkle appcast.xml 地址。GitHub Releases 也可托管该文件，普通仓库页面或 ZIP 下载链接不能直接用作更新源。")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red) }
            if let message = updater.message { Text(message).font(.system(size: 12)).foregroundStyle(.secondary) }
            Label("更新包通过对讲机的专用签名验证后才会安装。更新检查不会发送原文、译文或 API 密钥。", systemImage: "checkmark.shield")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }.padding(26)
        .onAppear { draftFeed = updater.feed }
    }
}
