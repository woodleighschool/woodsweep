import Darwin
import Foundation
import Security
import SimpleKeychain

nonisolated protocol CredentialStoring: Sendable {
    func load() throws -> AppConfiguration?
    func save(_ configuration: AppConfiguration) throws
}

nonisolated struct KeychainCredentialStore: CredentialStoring {
    struct Error: Swift.Error, LocalizedError {
        let status: OSStatus

        var errorDescription: String? {
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Unknown error"
            return "System keychain: \(message) (\(status))."
        }
    }

    func load() throws -> AppConfiguration? {
        do {
            let data = try keychain().data(forKey: "repository")
            return try JSONDecoder().decode(AppConfiguration.self, from: data)
        } catch SimpleKeychainError.itemNotFound {
            return nil
        }
    }

    func save(_ configuration: AppConfiguration) throws {
        guard geteuid() == 0 else {
            throw BootstrapCommand.Error.requiresRoot
        }
        let data = try JSONEncoder().encode(configuration)
        try keychain().set(data, forKey: "repository")
    }

    private func keychain() throws -> SimpleKeychain {
        // System enrollment must work before a login session exists (Apple TN3137).
        var keychain: SecKeychain?
        let status = SecKeychainOpen("/Library/Keychains/System.keychain", &keychain)
        guard status == errSecSuccess else {
            throw Error(status: status)
        }
        guard let keychain else {
            throw Error(status: errSecNoSuchKeychain)
        }
        // The file-based keychain's default access list trusts the creating app's code signature.
        return SimpleKeychain(
            service: "au.edu.vic.woodleigh.WoodSweep",
            attributes: [
                kSecUseDataProtectionKeychain as String: false,
                kSecUseKeychain as String: keychain,
                kSecMatchSearchList as String: [keychain],
            ]
        )
    }
}
