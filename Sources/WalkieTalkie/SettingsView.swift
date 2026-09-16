import SwiftUI

struct SettingsView: View {
    @ObservedObject var store: AppStore
    @ObservedObject var updater: UpdateManager
    @Binding var selection: Int
    var body: some View {
        TabView(selection: $selection) {
            APISettingsView(store: store).tabItem { Label("API 与快捷键", systemImage: "slider.horizontal.3") }.tag(0)
            UpdateSettingsView(updater: updater).tabItem { Label("软件更新", systemImage: "arrow.triangle.2.circlepath") }.tag(1)
        }.padding(12).frame(width: 626, height: 590)
    }
}

struct APISettingsView: View {
    @ObservedObject var store: AppStore
    @ViewState private var editing: Provider?
    @ViewState private var deleting: Provider?
    @ViewState private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 5) {
                    Text("连接你的翻译引擎").font(.system(size: 21, weight: .semibold))
                    Text("保存多个 API，在主窗口随时切换。").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Menu { ForEach(Array(Provider.presets.enumerated()), id: \.offset) { _, preset in
                    Button(preset.name) { var p = preset; p.id = UUID(); editing = p }
                } } label: { Label("添加 API", systemImage: "plus") }.fixedSize()
            }
            Group {
                if store.providers.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "network").font(.system(size: 32, weight: .light)).foregroundStyle(.secondary)
                        Text("还没有连接 API").font(.headline)
                        Text("使用 DeepSeek、OpenAI 或兼容服务，\n也可以连接本机的 Ollama。").multilineTextAlignment(.center).font(.system(size: 12)).foregroundStyle(.secondary)
                        Button("添加 DeepSeek") { var p = Provider.presets[0]; p.id = UUID(); editing = p }
                    }.frame(maxWidth: .infinity, minHeight: 205)
                } else {
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(store.providers) { provider in
                                HStack(spacing: 12) {
                                    Image(systemName: provider.requiresKey ? "network" : "desktopcomputer").font(.system(size: 18)).foregroundStyle(Color.accentColor).frame(width: 32)
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack { Text(provider.name).fontWeight(.medium); if store.selectedID == provider.id { Text("使用中").font(.system(size: 9, weight: .medium)).foregroundStyle(Color.accentColor).padding(.horizontal, 6).padding(.vertical, 3).background(Color.accentColor.opacity(0.1), in: Capsule()) } }
                                        Text(provider.model).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                                    }
                                    Spacer()
                                    if store.selectedID != provider.id { Button("使用") { store.selectedID = provider.id }.controlSize(.small) }
                                    Button("编辑") { editing = provider }.controlSize(.small)
                                    Button { deleting = provider } label: { Image(systemName: "trash") }.buttonStyle(.borderless).foregroundStyle(.secondary).accessibilityLabel("删除 \(provider.name)")
                                }.padding(14)
                                if provider.id != store.providers.last?.id { Divider().padding(.leading, 58) }
                            }
                        }
                    }.frame(height: 235)
                }
            }.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("全局快捷键").font(.system(size: 13, weight: .medium))
                    Text("在任何应用中呼出或收起对讲机").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Picker("全局快捷键", selection: $store.shortcut) {
                    Text("⌃⌥ Space").tag(0)
                    Text("⌘⇧ Space").tag(1)
                    Text("⌃⇧ T").tag(2)
                }.labelsHidden().frame(width: 155)
            }
            if let shortcutError = store.shortcutError { Text(shortcutError).font(.caption).foregroundStyle(.orange) }
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            Divider()
            Label("密钥保存在 macOS 钥匙串中。点击翻译或调用“用对讲机翻译”服务时，原文会发送至所选 API，应用不保存翻译历史。", systemImage: "lock.shield")
                .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack { Text("对讲机 · Walkie Talkie"); Spacer(); Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版") }.font(.system(size: 10)).foregroundStyle(.tertiary)
        }.padding(26).frame(width: 550)
            .sheet(item: $editing) { provider in ProviderEditor(store: store, original: provider) }
            .alert("删除 API 配置？", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } })) {
                Button("取消", role: .cancel) { deleting = nil }
                Button("删除", role: .destructive) {
                    if let deleting { do { try store.delete(deleting) } catch { self.error = error.localizedDescription } }
                    deleting = nil
                }
            } message: { Text("将删除此 API 配置。当前版本保存的密钥会一并删除；旧版本的受保护条目会保留，避免触发系统授权。") }
    }
}

struct ProviderEditor: View {
    @ObservedObject var store: AppStore
    let original: Provider
    @Environment(\.dismiss) private var dismiss
    @ViewState private var draft: Provider
    @ViewState private var key = ""
    @ViewState private var error: String?
    @ViewState private var message: String?
    @ViewState private var working = false
    @ViewState private var availableModels: [String] = []
    @ViewState private var operation: Task<Void, Never>?
    @ViewState private var keyLoaded = false
    private var isExisting: Bool { store.providers.contains { $0.id == original.id } }
    init(store: AppStore, original: Provider) {
        self.store = store; self.original = original; _draft = State(initialValue: original)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(store.providers.contains(where: { $0.id == original.id }) ? "编辑 API" : "添加 API").font(.system(size: 21, weight: .semibold))
            VStack(alignment: .leading, spacing: 14) {
                field("配置名称", hint: "例如：我的 DeepSeek", value: $draft.name)
                field("API 地址", hint: "https://api.example.com/v1", value: $draft.baseURL)
                Text("支持 OpenAI Chat Completions 格式，可填写 Base URL 或完整接口地址。").font(.system(size: 11)).foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 6) {
                    HStack { Text("API 密钥").font(.system(size: 12, weight: .medium)); Spacer(); Toggle("需要 API 密钥", isOn: $draft.requiresKey).font(.system(size: 11)).toggleStyle(.checkbox) }
                    SecureField(isExisting && !keyLoaded ? "已保存密钥，留空保持不变" : (draft.requiresKey ? "输入密钥，将安全保存至钥匙串" : "本地服务可留空"), text: $key).textFieldStyle(.roundedBorder)
                }
                if isExisting {
                    HStack(alignment: .top) {
                        Text("编辑配置不会读取密钥。重新填写并保存可修复更新后的授权，无需删除 API。")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Button("授权读取") {
                            do { key = try store.credentials.read(original.id, authorize: true); keyLoaded = true; error = nil; message = "密钥已读取。点击保存，为当前版本保存新的授权条目。" }
                            catch { self.error = error.localizedDescription }
                        }.controlSize(.small)
                    }
                }
                HStack(alignment: .bottom) {
                    field("模型名称", hint: "填写服务商提供的模型 ID", value: $draft.model)
                    Menu {
                        if availableModels.isEmpty { Text("先点击“获取模型”") }
                        ForEach(availableModels, id: \.self) { model in Button(model) { draft.model = model } }
                    } label: { Image(systemName: "chevron.down") }.frame(width: 36).disabled(availableModels.isEmpty).help("选择模型")
                }
            }.disabled(working)
            HStack {
                Button("获取模型") { run(test: false) }.disabled(working)
                Button("测试翻译") { run(test: true) }.disabled(working)
                if working { ProgressView().controlSize(.small) }
                Spacer()
            }
            Text("测试翻译会发送一句 “Hello”，可能产生少量 API 费用。").font(.system(size: 10)).foregroundStyle(.secondary)
            if let error { Text(error).font(.system(size: 12)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true) }
            if let message { Label(message, systemImage: "checkmark.circle.fill").font(.system(size: 12)).foregroundStyle(.green) }
            Divider()
            HStack {
                Button("取消") { operation?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") {
                    do {
                        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        draft.model = draft.model.trimmingCharacters(in: .whitespacesAndNewlines)
                        draft.baseURL = draft.baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
                        let retainedKey: String? = isExisting && !keyLoaded && key.isEmpty ? nil : key
                        try store.save(draft, key: retainedKey); dismiss()
                    } catch { self.error = error.localizedDescription }
                }.buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction).disabled(working)
            }
        }.padding(26).frame(width: 480)
        .onDisappear { operation?.cancel() }
        .onChange(of: draft.baseURL) { _ in message = nil; error = nil; availableModels = [] }
        .onChange(of: draft.model) { _ in message = nil; error = nil }
        .onChange(of: key) { _ in message = nil; error = nil; availableModels = [] }
    }
    private func field(_ title: String, hint: String, value: Binding<String>) -> some View {
        VStack(alignment: .leading, spacing: 6) { Text(title).font(.system(size: 12, weight: .medium)); TextField(hint, text: value).textFieldStyle(.roundedBorder) }
    }
    private func run(test: Bool) {
        working = true; error = nil; message = nil
        let provider = draft
        let credential: String
        do {
            credential = isExisting && !keyLoaded && key.isEmpty && draft.requiresKey
                ? try store.credentials.read(original.id, owner: original.credentialOwner)
                : key.trimmingCharacters(in: .whitespacesAndNewlines)
        } catch { working = false; self.error = error.localizedDescription; return }
        operation = Task { @MainActor in
            defer { working = false }
            do {
                if test {
                    _ = try await TranslationService.translate(text: "Hello", source: .en, target: .zhHans, provider: provider, key: credential)
                    try Task.checkCancellation()
                    message = "连接成功，翻译正常。"
                } else {
                    let models = try await TranslationService.models(provider: provider, key: credential)
                    try Task.checkCancellation()
                    availableModels = models
                    message = models.isEmpty ? "服务商未返回模型，请手动填写。" : "已获取 \(models.count) 个模型，可在模型右侧选择。"
                }
            } catch { if !Task.isCancelled { self.error = error.localizedDescription } }
        }
    }
}
