import SwiftUI
import Security
import AppKit
import NaturalLanguage
import LocalAuthentication

@MainActor struct Keychain {
    static let service = "app.walkietalkie.translator"
    /// Public signing metadata only. Reading this never opens the Keychain.
    static let signingIdentity: String? = {
        var dynamicCode: SecCode?
        var staticCode: SecStaticCode?
        var requirement: SecRequirement?
        var text: CFString?
        guard SecCodeCopySelf([], &dynamicCode) == errSecSuccess, let dynamicCode,
              SecCodeCopyStaticCode(dynamicCode, [], &staticCode) == errSecSuccess, let staticCode,
              SecCodeCopyDesignatedRequirement(staticCode, [], &requirement) == errSecSuccess, let requirement,
              SecRequirementCopyString(requirement, [], &text) == errSecSuccess else { return nil }
        return text as String?
    }()
    static func query(_ id: UUID) -> [String: Any] { [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: id.uuidString] }
    static func read(_ id: UUID, allowPrompt: Bool = false) throws -> String {
        var q = query(id)
        let context = LAContext()
        context.interactionNotAllowed = !allowPrompt
        q[kSecUseAuthenticationContext as String] = context
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = try withInteraction(allowPrompt) { SecItemCopyMatching(q as CFDictionary, &result) }
        if status == errSecItemNotFound { return "" }
        if status == errSecInteractionNotAllowed || status == errSecAuthFailed || status == errSecUserCanceled {
            throw AppError.message("已保存的密钥需要重新授权。请打开 API 设置，点击“授权读取”，或重新输入密钥后保存，无需删除 API。")
        }
        guard status == errSecSuccess, let data = result as? Data, let value = String(data: data, encoding: .utf8) else { throw AppError.message("无法读取钥匙串，请解锁系统钥匙串后重试。") }
        return value
    }
    static func save(_ key: String, id: UUID) throws {
        try withInteraction(false) { try saveItem(key, id: id) }
    }
    private static func saveItem(_ key: String, id: UUID) throws {
        if key.isEmpty { try delete(id); return }
        let data = Data(key.utf8)
        let status = SecItemUpdate(query(id) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if status == errSecItemNotFound {
            var q = query(id)
            q[kSecValueData as String] = data
            q[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            guard SecItemAdd(q as CFDictionary, nil) == errSecSuccess else { throw AppError.message("密钥保存失败，请检查系统钥匙串。") }
        } else if status != errSecSuccess { throw AppError.message("密钥更新失败，请检查系统钥匙串。") }
    }
    /// Existing releases use the file-based login keychain. LAContext alone cannot
    /// suppress all legacy ACL dialogs, so scope the legacy process flag synchronously
    /// on the main actor and restore it before doing anything else.
    static func withInteraction<T>(_ allowed: Bool, operation: () throws -> T) throws -> T {
        var previous = DarwinBoolean(true)
        guard SecKeychainGetUserInteractionAllowed(&previous) == errSecSuccess,
              SecKeychainSetUserInteractionAllowed(allowed) == errSecSuccess else {
            throw AppError.message("无法设置钥匙串访问方式，请稍后重试。")
        }
        defer { SecKeychainSetUserInteractionAllowed(previous.boolValue) }
        return try operation()
    }
    static func delete(_ id: UUID) throws {
        var q = query(id)
        let context = LAContext(); context.interactionNotAllowed = true
        q[kSecUseAuthenticationContext as String] = context
        let status = try withInteraction(false) { SecItemDelete(q as CFDictionary) }
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AppError.message("无法删除钥匙串中的密钥，请重试。") }
    }
}

@MainActor final class AppStore: ObservableObject {
    @Published var providers: [Provider] = []
    @Published var selectedID: UUID? { didSet { defaults.set(selectedID?.uuidString, forKey: "selectedProvider"); if selectedID != oldValue { invalidate() } } }
    @Published var source: Language = .auto { didSet { defaults.set(source.rawValue, forKey: "sourceLanguage"); invalidate() } }
    @Published var target: Language = .zhHans { didSet { defaults.set(target.rawValue, forKey: "targetLanguage"); invalidate() } }
    @Published var input = "" { didSet { if input != oldValue { invalidate() } } }
    @Published var output = ""
    @Published var busy = false
    @Published var error: String?
    @Published var lastProvider = ""
    @Published var pinned = false
    @Published var shortcut = 0 { didSet { defaults.set(shortcut, forKey: "shortcut"); onShortcutChange?() } }
    @Published var shortcutError: String?
    @Published var settingsTab = 0
    var onShortcutChange: (() -> Void)?
    var showSettings: (() -> Void)?
    private var task: Task<Void, Never>?
    private var generation = UUID()
    private let defaults = UserDefaults.standard
    let credentials = CredentialCache()
    var selected: Provider? { providers.first { $0.id == selectedID } }
    var canTranslate: Bool { !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selected != nil }
    var shortcutLabel: String { ["⌃⌥Space", "⌘⇧Space", "⌃⇧T"][min(max(shortcut, 0), 2)] }
    init() {
        if let data = defaults.data(forKey: "providers") {
            do { providers = try JSONDecoder().decode([Provider].self, from: data) }
            catch { self.error = "API 配置读取失败，请在设置中重新添加。" }
        }
        selectedID = UUID(uuidString: defaults.string(forKey: "selectedProvider") ?? "") ?? providers.first?.id
        if !providers.contains(where: { $0.id == selectedID }) { selectedID = providers.first?.id }
        source = Language(rawValue: defaults.string(forKey: "sourceLanguage") ?? "") ?? .auto
        target = Language(rawValue: defaults.string(forKey: "targetLanguage") ?? "") ?? .zhHans
        if target == .auto { target = .zhHans }
        shortcut = min(max(defaults.integer(forKey: "shortcut"), 0), 2)
    }
    /// nil preserves the stored key without reading it. A supplied key creates a fresh
    /// item for this signed app, so repairing an old ACL never requires deleting the API.
    func save(_ provider: Provider, key: String?) throws {
        _ = try provider.endpoint()
        guard !provider.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !provider.model.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw AppError.message("请填写配置名称和模型名称。") }
        let index = providers.firstIndex { $0.id == provider.id }
        let trimmed = key?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !provider.requiresKey || (trimmed == nil && index != nil) || !(trimmed ?? "").isEmpty else { throw AppError.message("请填写 API 密钥，或关闭“需要 API 密钥”。") }
        var saved = provider
        if let trimmed {
            if index != nil { saved.id = UUID() }
            try credentials.save(trimmed, id: saved.id)
            saved.credentialOwner = credentials.currentOwner
        }
        if let index { providers[index] = saved } else { providers.append(saved) }
        defaults.set(try JSONEncoder().encode(providers), forKey: "providers")
        if selectedID == nil || selectedID == provider.id { selectedID = saved.id }
        if saved.id != provider.id {
            // The replacement is already persisted. A locked old item may remain in Keychain.
            if credentials.owns(provider.credentialOwner) { try? credentials.delete(provider.id) }
            else { credentials.forget(provider.id) }
        }
    }
    func delete(_ provider: Provider) throws {
        if credentials.owns(provider.credentialOwner) { try credentials.delete(provider.id) }
        else { credentials.forget(provider.id) }
        providers.removeAll { $0.id == provider.id }
        defaults.set(try JSONEncoder().encode(providers), forKey: "providers")
        if selectedID == provider.id { selectedID = providers.first?.id }
    }
    func invalidate() { cancel(); output = ""; lastProvider = ""; error = nil }
    func cancel() { generation = UUID(); task?.cancel(); task = nil; busy = false }
    func clear() { input = ""; invalidate() }
    func paste() { if let text = NSPasteboard.general.string(forType: .string) { input = text } }
    func swap() {
        let previousSource = source
        let previousTarget = target
        let previousInput = input
        let previousOutput = output
        let detected = Self.detectLanguage(previousInput)
        source = previousTarget
        target = previousSource == .auto ? detected : previousSource
        if !previousOutput.isEmpty { input = previousOutput } // A fresh translation makes swapped results unambiguous.
    }
    static func detectLanguage(_ text: String) -> Language {
        let language = NLLanguageRecognizer.dominantLanguage(for: text)
        let mapping: [NLLanguage: Language] = [.simplifiedChinese: .zhHans, .traditionalChinese: .zhHant, .english: .en, .japanese: .ja, .korean: .ko, .french: .fr, .german: .de, .spanish: .es, .italian: .it, .portuguese: .pt, .russian: .ru, .arabic: .ar]
        return language.flatMap { mapping[$0] } ?? .en
    }
    func translate() {
        guard canTranslate, let provider = selected else { showSettings?(); return }
        cancel()
        error = nil; output = ""; lastProvider = ""; busy = true
        let id = generation
        let text = input; let from = source; let to = target
        task = Task {
            do {
                let key = provider.requiresKey ? try credentials.read(provider.id, owner: provider.credentialOwner) : ""
                let result = try await TranslationService.translate(text: text, source: from, target: to, provider: provider, key: key)
                guard id == generation else { return }
                output = result; lastProvider = "\(provider.name) · \(provider.model)"; busy = false
            } catch {
                guard id == generation else { return }
                busy = false
                if !(error is CancellationError), (error as? URLError)?.code != .cancelled { self.error = error.localizedDescription }
            }
        }
    }
}
