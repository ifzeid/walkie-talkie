import Foundation

struct Fixture: Codable {
    let id: UUID
    let owner: String
}

@main struct CredentialIntegration {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        let path = URL(fileURLWithPath: args[2])
        guard let identity = Keychain.signingIdentity else { throw AppError.message("Test executable must be signed") }
        let mode = args[1]
        if mode == "create" {
            let fixture = Fixture(id: UUID(), owner: identity)
            // Write metadata first so cleanup is possible even if creation fails.
            try JSONEncoder().encode(fixture).write(to: path, options: .atomic)
            try Keychain.save("walkie-talkie-disposable-test-value", id: fixture.id)
            print("PASS: Creator A saved a disposable test item")
            return
        }
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: path))
        if mode == "changed-signature" {
            precondition(identity != fixture.owner, "Fixture must use a different real code signature")
            var calls = 0
            let cache = CredentialCache(load: { id, prompt in
                calls += 1
                return try Keychain.read(id, allowPrompt: prompt)
            })
            for _ in 0..<10 {
                do { _ = try cache.read(fixture.id, owner: fixture.owner); throw AppError.message("Old owner incorrectly accepted") }
                catch { precondition(calls == 0, "Old item reached a real Keychain read") }
            }
            print("PASS: Reader B rejected A's real item 10 times with zero Keychain calls")
        } else if mode == "restart" {
            precondition(identity == fixture.owner)
            let cache = CredentialCache()
            let result = try cache.read(fixture.id, owner: fixture.owner)
            precondition(result == "walkie-talkie-disposable-test-value")
            print("PASS: Creator A read its saved item after restarting without interactive access")
        } else if mode == "cleanup" {
            precondition(identity == fixture.owner)
            try Keychain.delete(fixture.id)
            print("PASS: Disposable test item removed")
        }
    }
}
