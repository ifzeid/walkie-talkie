import SwiftUI
import AppKit

// Keep the property-wrapper spelling unambiguous on SDKs that also expose a State macro.
typealias ViewState<Value> = SwiftUI.State<Value>

struct TranslatorView: View {
    @ObservedObject var store: AppStore
    @FocusState private var inputFocused: Bool
    @ViewState private var copied = false
    @ViewState private var inputCopied = false
    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: "wave.3.left.circle.fill").font(.system(size: 25)).foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text("对讲机").font(.system(size: 15, weight: .semibold))
                    Text("WALKIE TALKIE").font(.system(size: 9, weight: .medium, design: .rounded)).tracking(1.5).foregroundStyle(.secondary)
                }
                Spacer()
                if store.providers.isEmpty {
                    Button { store.showSettings?() } label: { Label("添加 API", systemImage: "plus") }
                } else {
                    Menu {
                        ForEach(store.providers) { provider in
                            Button { store.selectedID = provider.id } label: {
                                if store.selectedID == provider.id { Label(provider.name, systemImage: "checkmark") } else { Text(provider.name) }
                            }
                        }
                        Divider()
                        Button("管理 API…") { store.showSettings?() }
                    } label: {
                        HStack(spacing: 6) {
                            Circle().fill(Color.accentColor).frame(width: 5, height: 5)
                            Text(store.selected?.name ?? "选择 API").lineLimit(1)
                        }
                    }.menuStyle(.borderlessButton).fixedSize().frame(maxWidth: 160, alignment: .trailing)
                }
                Button { store.showSettings?() } label: { Image(systemName: "slider.horizontal.3") }
                    .buttonStyle(.borderless).help("API 与快捷键设置（⌘,）").accessibilityLabel("设置")
            }
            .padding(.horizontal, 2)

            VStack(alignment: .leading, spacing: 12) {
                Text("原文").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                ZStack(alignment: .topLeading) {
                    if store.input.isEmpty {
                        Text("输入或粘贴一段文字")
                            .font(.system(size: 16)).foregroundStyle(.tertiary).lineSpacing(6).padding(.leading, 5).padding(.top, 1).allowsHitTesting(false)
                    }
                    TextEditor(text: $store.input).font(.system(size: 16)).lineSpacing(6)
                        .scrollContentBackground(.hidden).focused($inputFocused).accessibilityLabel("原文输入框")
                }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(.horizontal, -5)
                TextPanelActions(text: store.input, isSource: true, copied: $inputCopied,
                                 canClear: !store.input.isEmpty || !store.output.isEmpty || store.error != nil) {
                    store.clear(); inputFocused = true
                }
            }.padding(16).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07)))

            HStack(spacing: 8) {
                languageMenu(value: $store.source, values: Language.allCases)
                Button { store.swap() } label: { Image(systemName: "arrow.left.arrow.right").font(.system(size: 14, weight: .medium)).frame(width: 36, height: 28) }
                    .buttonStyle(.borderless).foregroundStyle(.secondary).help("交换语言").accessibilityLabel("交换源语言和目标语言")
                languageMenu(value: $store.target, values: Language.allCases.filter { $0 != .auto })
            }.padding(.horizontal, 12).padding(.vertical, 5)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.045)))

            VStack(alignment: .leading, spacing: 12) {
                Text("译文").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
                if store.busy {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.small)
                        Text("正在用 \(store.selected?.name ?? "API") 翻译…").font(.system(size: 12)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let error = store.error {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("翻译未完成", systemImage: "exclamationmark.circle").font(.system(size: 13, weight: .medium)).foregroundStyle(.orange)
                        Text(error).font(.system(size: 13)).foregroundStyle(.secondary).textSelection(.enabled)
                        HStack {
                            Button("重试") { store.translate() }.disabled(!store.canTranslate)
                            Button("API 设置") { store.showSettings?() }
                        }
                        Spacer(minLength: 0)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else if store.output.isEmpty {
                    Text("让语言不再有距离。")
                        .font(.system(size: 16)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                } else {
                    ScrollView {
                        Text(store.output).font(.system(size: 16)).lineSpacing(6).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.frame(maxHeight: .infinity)
                }
                TextPanelActions(text: store.output, isSource: false, copied: $copied,
                                 canClear: !store.output.isEmpty || store.error != nil || store.busy) {
                    store.invalidate()
                }
            }.padding(16).background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Color.primary.opacity(0.07)))

            HStack(spacing: 14) {
                Spacer()
                if store.busy {
                    Button("取消") { store.cancel() }.controlSize(.large)
                } else {
                    Button { store.translate() } label: {
                        Text("翻译").fontWeight(.medium).frame(minWidth: 88)
                    }.buttonStyle(TranslateButtonStyle()).keyboardShortcut(.return, modifiers: .command)
                        .disabled(!store.canTranslate)
                        .help(store.selected == nil ? "请先添加并选择 API" : (store.canTranslate ? "翻译原文" : "请输入需要翻译的文字"))
                }
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 10)
        .padding(.bottom, 18)
        .background(.ultraThinMaterial)
        .frame(minWidth: 440, minHeight: 580)
        .onAppear { inputFocused = true }
        .onChange(of: store.output) { _ in copied = false }
        .onChange(of: store.input) { _ in inputCopied = false }
    }
    private func languageMenu(value: Binding<Language>, values: [Language]) -> some View {
        Menu { ForEach(values) { language in Button { value.wrappedValue = language } label: {
            if value.wrappedValue == language { Label(language.title, systemImage: "checkmark") } else { Text(language.title) }
        } } } label: { Text(value.wrappedValue.title).font(.system(size: 13, weight: .medium)).frame(maxWidth: .infinity) }
            .menuStyle(.borderlessButton).frame(maxWidth: .infinity).accessibilityLabel(value.wrappedValue.title)
    }
}

/// Both text regions keep statistics and actions in the same stable bottom row.
private struct TextPanelActions: View {
    let text: String
    let isSource: Bool
    @Binding var copied: Bool
    let canClear: Bool
    let clear: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            Text("\(text.count) 字").monospacedDigit()
                .accessibilityLabel("\(isSource ? "原文" : "译文") \(text.count) 字")
            if isSource { clearButton.keyboardShortcut("k", modifiers: .command) }
            else { clearButton }
            Spacer(minLength: 12)
            if isSource { copyButton }
            else { copyButton.keyboardShortcut("c", modifiers: [.command, .shift]) }
        }
        .buttonStyle(.borderless).font(.system(size: 11)).foregroundStyle(.secondary)
        .frame(minHeight: 18)
    }
    private var clearButton: some View {
        Button(action: clear) { Label("清空", systemImage: "xmark") }
            .disabled(!canClear)
            .help(isSource ? "清空原文和译文" : "清空译文，保留原文")
            .accessibilityLabel(isSource ? "清空原文和译文" : "清空译文")
    }
    private var copyButton: some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
            copied = true
        } label: { Label(copied ? "已复制" : "复制", systemImage: copied ? "checkmark" : "doc.on.doc") }
            .disabled(text.isEmpty)
            .help(isSource ? "复制原文" : "复制译文")
            .accessibilityLabel(isSource ? "复制原文" : "复制译文")
    }
}

/// Give disabled text its own semantic color instead of fading a white label.
private struct TranslateButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.isFocused) private var isFocused

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13))
            .foregroundStyle(isEnabled ? Color.white : Color(nsColor: .labelColor))
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(isEnabled ? Color.accentColor : Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 9))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color.primary.opacity(isEnabled ? 0 : 0.12)))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .keyboardFocusIndicatorColor), lineWidth: 2).padding(-3).opacity(isFocused ? 1 : 0))
            .brightness(isEnabled && configuration.isPressed ? -0.08 : 0)
    }
}
