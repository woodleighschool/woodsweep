import Foundation
import OSLog

nonisolated enum DefaultsKey: String, CaseIterable {
    case targetUsername
    case s3Endpoint
    case s3Bucket
    case s3Region
    case s3Prefix
    case s3AccessKeyID
}

nonisolated enum CredentialKey: String, CaseIterable {
    case secretAccessKey
    case repositoryPassword
}

nonisolated struct ConfigurationUpdate: Equatable, Sendable {
    let username: String?
    let endpoint: String?
    let bucket: String?
    let region: String?
    let prefix: String?
    let accessKeyID: String?
    let secretAccessKey: String?
    let repositoryPassword: String?
}

nonisolated struct RepositorySettings: Equatable, Sendable {
    let endpoint: String
    let bucket: String
    let region: String?
    let prefix: String?
    let accessKeyID: String
}

nonisolated struct RepositoryCredentials: Equatable, Sendable {
    let secretAccessKey: String
    let repositoryPassword: String
}

nonisolated struct AppConfiguration: Equatable, Sendable {
    let targetUsername: String
    let repository: RepositorySettings
    let credentials: RepositoryCredentials
}

nonisolated protocol DefaultsStoring: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String)
}

nonisolated protocol ConfigurationLoading: Sendable {
    // periphery:ignore
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

    func apply(_ update: ConfigurationUpdate) throws {
        Log.configuration.info("Applying configuration update")

        set(update.username, for: .targetUsername)
        set(update.endpoint, for: .s3Endpoint)
        set(update.bucket, for: .s3Bucket)
        set(update.region, for: .s3Region)
        set(update.prefix, for: .s3Prefix)
        set(update.accessKeyID, for: .s3AccessKeyID)

        if let secretAccessKey = update.secretAccessKey {
            try credentials.set(secretAccessKey, for: .secretAccessKey)
        }
        if let repositoryPassword = update.repositoryPassword {
            try credentials.set(repositoryPassword, for: .repositoryPassword)
        }
    }

    func load() throws -> AppConfiguration {
        Log.configuration.info("Loading effective configuration")

        let targetUsername = try requiredDefault(.targetUsername)
        let endpoint = try requiredDefault(.s3Endpoint)
        let bucket = try requiredDefault(.s3Bucket)
        let region = optionalDefault(.s3Region)
        let prefix = optionalDefault(.s3Prefix)
        let accessKeyID = try requiredDefault(.s3AccessKeyID)
        let secretAccessKey = try requiredCredential(.secretAccessKey)
        let repositoryPassword = try requiredCredential(.repositoryPassword)

        return AppConfiguration(
            targetUsername: targetUsername,
            repository: RepositorySettings(
                endpoint: endpoint,
                bucket: bucket,
                region: region,
                prefix: prefix,
                accessKeyID: accessKeyID
            ),
            credentials: RepositoryCredentials(
                secretAccessKey: secretAccessKey,
                repositoryPassword: repositoryPassword
            )
        )
    }

    private func set(_ value: String?, for key: DefaultsKey) {
        guard let value else {
            return
        }
        defaults.set(value, forKey: key.rawValue)
    }

    private func requiredDefault(_ key: DefaultsKey) throws -> String {
        try requiredValue(
            defaults.string(forKey: key.rawValue),
            key: key.rawValue
        )
    }

    private func optionalDefault(_ key: DefaultsKey) -> String? {
        normalized(defaults.string(forKey: key.rawValue))
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
