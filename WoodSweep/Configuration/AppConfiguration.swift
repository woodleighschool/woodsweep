import Foundation
import OSLog

nonisolated enum DefaultsKey: String, CaseIterable {
    case kopiaServerURL
}

nonisolated enum CredentialKey: String, CaseIterable {
    case serverPassword
}

nonisolated struct AppConfiguration: Equatable, Sendable {
    let serverURL: String
    let serverPassword: String
}

nonisolated protocol DefaultsStoring: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String)
}

nonisolated protocol ConfigurationLoading: Sendable {
    func load() throws -> AppConfiguration
}

nonisolated struct AppConfigurationStore: ConfigurationLoading {
    enum Error: Swift.Error, Equatable, LocalizedError {
        case missingValue(String)

        var errorDescription: String? {
            switch self {
            case let .missingValue(key):
                "Missing required configuration value: \(key)."
            }
        }
    }

    private let defaults: any DefaultsStoring
    private let credentials: any CredentialStoring

    init(
        defaults: any DefaultsStoring,
        credentials: any CredentialStoring = KeychainCredentialStore()
    ) {
        self.defaults = defaults
        self.credentials = credentials
    }

    func apply(serverURL: String) throws -> String {
        Log.configuration.info("Applying Kopia server URL")
        defaults.set(serverURL, forKey: DefaultsKey.kopiaServerURL.rawValue)
        return try requiredDefault(.kopiaServerURL)
    }

    func store(serverPassword: String) throws {
        Log.configuration.info("Storing machine repository credential")
        try credentials.set(serverPassword, for: .serverPassword)
    }

    func load() throws -> AppConfiguration {
        Log.configuration.info("Loading effective configuration")
        return try AppConfiguration(
            serverURL: requiredDefault(.kopiaServerURL),
            serverPassword: requiredCredential(.serverPassword)
        )
    }

    private func requiredDefault(_ key: DefaultsKey) throws -> String {
        try requiredValue(
            defaults.string(forKey: key.rawValue),
            key: key.rawValue
        )
    }

    private func requiredCredential(_ key: CredentialKey) throws -> String {
        try requiredValue(
            credentials.value(for: key),
            key: key.rawValue
        )
    }

    private func requiredValue(
        _ value: String?,
        key: String
    ) throws -> String {
        guard let value = normalized(value) else {
            throw Error.missingValue(key)
        }
        return value
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension UserDefaults: DefaultsStoring {
    nonisolated func set(_ value: String, forKey key: String) {
        set(value as Any, forKey: key)
    }
}
