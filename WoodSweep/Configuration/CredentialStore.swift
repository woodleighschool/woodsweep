import SimpleKeychain

nonisolated protocol CredentialStoring: Sendable {
    func value(for key: CredentialKey) throws -> String?
    func set(_ value: String, for key: CredentialKey) throws
}

nonisolated struct KeychainCredentialStore: CredentialStoring {
    private let keychain = SimpleKeychain(
        service: "au.edu.vic.woodleigh.WoodSweep.credentials"
    )

    func value(for key: CredentialKey) throws -> String? {
        do {
            return try keychain.string(forKey: key.rawValue)
        } catch SimpleKeychainError.itemNotFound {
            return nil
        }
    }

    func set(_ value: String, for key: CredentialKey) throws {
        try keychain.set(value, forKey: key.rawValue)
    }
}
