import Foundation
import Testing
@testable import WoodSweep

@Suite("Configuration")
struct ConfigurationTests {
    @Test("configure accepts individual values")
    func parsesPartialUpdate() throws {
        let update = try ConfigurationArguments.parse([
            "--username", "sac",
            "--bucket", "exam-backups",
            "--repository-password", "repository-secret",
        ])

        #expect(update.username == "sac")
        #expect(update.bucket == "exam-backups")
        #expect(update.repositoryPassword == "repository-secret")
        #expect(update.endpoint == nil)
    }

    @Test("configure maps every supported option")
    func parsesEverySupportedOption() throws {
        let update = try ConfigurationArguments.parse([
            "--username", "sac",
            "--endpoint", "s3.example.test",
            "--bucket", "exam-backups",
            "--region", "ap-southeast-2",
            "--prefix", "sac/",
            "--access-key", "access",
            "--secret-access-key", "secret",
            "--repository-password", "password",
        ])

        #expect(update == ConfigurationUpdate(
            username: "sac",
            endpoint: "s3.example.test",
            bucket: "exam-backups",
            region: "ap-southeast-2",
            prefix: "sac/",
            accessKeyID: "access",
            secretAccessKey: "secret",
            repositoryPassword: "password"
        ))
    }

    @Test("configure rejects unknown flags")
    func rejectsUnknownFlag() {
        #expect(throws: ConfigurationArguments.Error.unknownOption("--backend")) {
            try ConfigurationArguments.parse(["--backend", "filesystem"])
        }
    }

    @Test(
        "configure rejects missing, empty, and duplicate values",
        arguments: [
            (
                ["--endpoint"],
                ConfigurationArguments.Error.missingValue("--endpoint")
            ),
            (
                ["--endpoint", "--bucket", "exam-backups"],
                ConfigurationArguments.Error.missingValue("--endpoint")
            ),
            (
                ["--username", "   "],
                ConfigurationArguments.Error.emptyValue("--username")
            ),
            (
                ["--bucket", "first", "--bucket", "second"],
                ConfigurationArguments.Error.duplicateOption("--bucket")
            ),
        ]
    )
    func rejectsInvalidOptionValues(
        arguments: [String],
        expectedError: ConfigurationArguments.Error
    ) {
        #expect(throws: expectedError) {
            try ConfigurationArguments.parse(arguments)
        }
    }

    @Test("non-secrets and secrets use different stores")
    func routesValuesToTheirStores() throws {
        let defaults = MemoryDefaults()
        let credentials = MemoryCredentialStore()
        let store = AppConfigurationStore(
            defaults: defaults,
            credentials: credentials
        )

        try store.apply(ConfigurationUpdate(
            username: "sac",
            endpoint: "s3.example.test",
            bucket: "exam-backups",
            region: nil,
            prefix: "sac/",
            accessKeyID: "access",
            secretAccessKey: "secret",
            repositoryPassword: "password"
        ))

        #expect(defaults.values[DefaultsKey.targetUsername.rawValue] == "sac")
        #expect(defaults.values.values.contains("secret") == false)
        #expect(defaults.values.values.contains("password") == false)
        #expect(credentials.values[.secretAccessKey] == "secret")
        #expect(credentials.values[.repositoryPassword] == "password")
    }

    @Test("partial updates preserve values omitted by configure")
    func preservesOmittedValues() throws {
        let defaults = MemoryDefaults([
            DefaultsKey.targetUsername.rawValue: "existing-user",
            DefaultsKey.s3Bucket.rawValue: "existing-bucket",
        ])
        let credentials = MemoryCredentialStore([
            .repositoryPassword: "existing-password",
        ])
        let store = AppConfigurationStore(
            defaults: defaults,
            credentials: credentials
        )

        try store.apply(ConfigurationUpdate(
            username: nil,
            endpoint: "new.example.test",
            bucket: nil,
            region: nil,
            prefix: nil,
            accessKeyID: nil,
            secretAccessKey: "new-secret",
            repositoryPassword: nil
        ))

        #expect(
            defaults.values[DefaultsKey.targetUsername.rawValue]
                == "existing-user"
        )
        #expect(
            defaults.values[DefaultsKey.s3Bucket.rawValue] == "existing-bucket"
        )
        #expect(
            defaults.values[DefaultsKey.s3Endpoint.rawValue]
                == "new.example.test"
        )
        #expect(credentials.values[.secretAccessKey] == "new-secret")
        #expect(
            credentials.values[.repositoryPassword] == "existing-password"
        )
    }

    @Test("load reads and validates the effective values")
    func loadsEffectiveConfiguration() throws {
        let defaults = MemoryDefaults([
            DefaultsKey.targetUsername.rawValue: " sac ",
            DefaultsKey.s3Endpoint.rawValue: " s3.example.test ",
            DefaultsKey.s3Bucket.rawValue: " exam-backups ",
            DefaultsKey.s3Region.rawValue: "   ",
            DefaultsKey.s3Prefix.rawValue: " sac/ ",
            DefaultsKey.s3AccessKeyID.rawValue: " access ",
        ])
        let credentials = MemoryCredentialStore([
            .secretAccessKey: " secret ",
            .repositoryPassword: " password ",
        ])
        let store = AppConfigurationStore(
            defaults: defaults,
            credentials: credentials
        )

        let configuration = try store.load()

        #expect(configuration.targetUsername == "sac")
        #expect(configuration.repository.endpoint == "s3.example.test")
        #expect(configuration.repository.bucket == "exam-backups")
        #expect(configuration.repository.region == nil)
        #expect(configuration.repository.prefix == "sac/")
        #expect(configuration.repository.accessKeyID == "access")
        #expect(configuration.credentials.secretAccessKey == "secret")
        #expect(configuration.credentials.repositoryPassword == "password")
    }

    @Test("load reads defaults again instead of caching")
    func reloadsEffectiveDefaults() throws {
        let defaults = configuredDefaults()
        let credentials = configuredCredentials()
        let store = AppConfigurationStore(
            defaults: defaults,
            credentials: credentials
        )

        #expect(try store.load().repository.bucket == "exam-backups")

        defaults.set("managed-exam-backups", forKey: DefaultsKey.s3Bucket.rawValue)

        #expect(try store.load().repository.bucket == "managed-exam-backups")
    }

    @Test("load rejects the first missing required value")
    func rejectsMissingRequiredValue() {
        let defaults = configuredDefaults()
        defaults.set(" \n ", forKey: DefaultsKey.targetUsername.rawValue)
        let store = AppConfigurationStore(
            defaults: defaults,
            credentials: configuredCredentials()
        )

        #expect(throws: AppConfigurationStore.Error.missingValue("targetUsername")) {
            try store.load()
        }
    }

    @Test("load rejects missing credentials")
    func rejectsMissingCredential() {
        let store = AppConfigurationStore(
            defaults: configuredDefaults(),
            credentials: MemoryCredentialStore()
        )

        #expect(throws: AppConfigurationStore.Error.missingValue("secretAccessKey")) {
            try store.load()
        }
    }

    private func configuredDefaults() -> MemoryDefaults {
        MemoryDefaults([
            DefaultsKey.targetUsername.rawValue: "sac",
            DefaultsKey.s3Endpoint.rawValue: "s3.example.test",
            DefaultsKey.s3Bucket.rawValue: "exam-backups",
            DefaultsKey.s3AccessKeyID.rawValue: "access",
        ])
    }

    private func configuredCredentials() -> MemoryCredentialStore {
        MemoryCredentialStore([
            .secretAccessKey: "secret",
            .repositoryPassword: "password",
        ])
    }
}

private final class MemoryDefaults: DefaultsStoring, @unchecked Sendable {
    var values: [String: String]

    init(_ values: [String: String] = [:]) {
        self.values = values
    }

    func string(forKey key: String) -> String? {
        values[key]
    }

    func set(_ value: String, forKey key: String) {
        values[key] = value
    }
}

private final class MemoryCredentialStore:
    CredentialStoring,
    @unchecked Sendable
{
    var values: [CredentialKey: String]

    init(_ values: [CredentialKey: String] = [:]) {
        self.values = values
    }

    func value(for key: CredentialKey) throws -> String? {
        values[key]
    }

    func set(_ value: String, for key: CredentialKey) throws {
        values[key] = value
    }
}
