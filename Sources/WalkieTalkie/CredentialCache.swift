import Foundation

/// In-memory only; no API key is stored in preferences, files, or logs.
@MainActor final class CredentialCache {
    typealias Read = @MainActor (UUID, Bool) throws -> String
    private var keys: [UUID: String] = [:]
    private let identity: @MainActor () -> String?
    var currentOwner: String? { identity() }
    func owns(_ owner: String?) -> Bool {
        guard let owner, let currentOwner else { return false }
        return owner == currentOwner
    }
    private let load: Read
    private let write: @MainActor (String, UUID) throws -> Void
    private let remove: @MainActor (UUID) throws -> Void

    init(identity: @escaping @MainActor () -> String? = { Keychain.signingIdentity },
         load: @escaping Read = { try Keychain.read($0, allowPrompt: $1) },
         write: @escaping @MainActor (String, UUID) throws -> Void = { try Keychain.save($0, id: $1) },
         remove: @escaping @MainActor (UUID) throws -> Void = { try Keychain.delete($0) }) {
        self.identity = identity
        self.load = load; self.write = write; self.remove = remove
    }
    func read(_ id: UUID, owner: String? = nil, authorize: Bool = false) throws -> String {
        if let key = keys[id] { return key }
        // Do not even ask macOS to read items created by unknown/older signatures.
        // Prompt-suppression flags alone did not reliably protect this path on all hosts.
        guard authorize || owns(owner) else {
            throw AppError.message("此密钥由旧版本保存，已暂停读取以避免系统弹窗。请到 API 设置重新填写密钥并保存，或主动点击“授权读取”。无需删除 API。")
        }
        let key = try load(id, authorize)
        keys[id] = key
        return key
    }
    func save(_ key: String, id: UUID) throws {
        try write(key, id)
        keys[id] = key
    }
    func forget(_ id: UUID) { keys.removeValue(forKey: id) }
    func delete(_ id: UUID) throws {
        keys.removeValue(forKey: id)
        try remove(id)
    }
}
