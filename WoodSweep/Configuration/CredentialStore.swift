import Foundation
import Security

nonisolated protocol CredentialStoring: Sendable {
    func value(for key: CredentialKey) throws -> String?
    func set(_ value: String, for key: CredentialKey) throws
}

nonisolated struct KeychainCredentialStore: CredentialStoring {
    enum Error: Swift.Error, Equatable, LocalizedError {
        case invalidData(account: String)
        case operationFailed(
            account: String,
            status: OSStatus,
            message: String
        )

        var errorDescription: String? {
            switch self {
            case let .invalidData(account):
                "Keychain item \(account) does not contain UTF-8 data."
            case let .operationFailed(account, status, message):
                "Keychain operation failed for \(account): \(message) (\(status))."
            }
        }
    }

    private static let service =
        "au.edu.vic.woodleigh.WoodSweep.credentials"

    func value(for key: CredentialKey) throws -> String? {
        var result: CFTypeRef?
        var query = itemQuery(for: key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard
                let data = result as? Data,
                let value = String(data: data, encoding: .utf8)
            else {
                throw Error.invalidData(account: key.rawValue)
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw securityError(status: status, account: key.rawValue)
        }
    }

    func set(_ value: String, for key: CredentialKey) throws {
        let data = Data(value.utf8)
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String:
                kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
        ]

        let updateStatus = SecItemUpdate(
            itemQuery(for: key) as CFDictionary,
            attributes as CFDictionary
        )
        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = itemQuery(for: key)
            item.merge(attributes) { _, new in new }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw securityError(
                    status: addStatus,
                    account: key.rawValue
                )
            }
        default:
            throw securityError(
                status: updateStatus,
                account: key.rawValue
            )
        }
    }

    private func itemQuery(for key: CredentialKey) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.service,
            kSecAttrAccount as String: key.rawValue,
            kSecUseDataProtectionKeychain as String: true,
            kSecAttrSynchronizable as String: false,
        ]
    }

    private func securityError(
        status: OSStatus,
        account: String
    ) -> Error {
        let message =
            SecCopyErrorMessageString(status, nil) as String?
                ?? "Unknown Security framework error"
        return .operationFailed(
            account: account,
            status: status,
            message: message
        )
    }
}
