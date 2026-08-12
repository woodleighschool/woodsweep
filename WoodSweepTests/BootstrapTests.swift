import ArgumentParser
import Foundation
import Testing
@testable import WoodSweep

@Suite("Bootstrap")
struct BootstrapTests {
    @Test("arguments require the server and bootstrap identity")
    func parsesArguments() throws {
        let arguments = try BootstrapArguments.parse([
            "--server-url", "https://kopia.example.test:51515",
            "--bootstrap-user", "bootstrap@woodsweep",
            "--bootstrap-password", "bootstrap-password",
        ])

        #expect(arguments.serverURL == "https://kopia.example.test:51515")
        #expect(arguments.user == KopiaUser("bootstrap@woodsweep"))
        #expect(arguments.bootstrapPassword == "bootstrap-password")
    }

    @Test("arguments reject missing and invalid values")
    func rejectsInvalidArguments() {
        #expect(throws: (any Error).self) {
            try BootstrapArguments.parse([
                "--server-url", "https://kopia.example.test:51515",
                "--bootstrap-user", "Bootstrap@Woodsweep",
                "--bootstrap-password", "bootstrap-password",
            ])
        }
        #expect(throws: (any Error).self) {
            try BootstrapArguments.parse([
                "--server-url", "https://kopia.example.test:51515",
            ])
        }
    }

    @Test("configuration uses the effective UserDefaults value")
    func appliesEffectiveServerURL() throws {
        let defaults = MemoryDefaults(effectiveValues: [
            DefaultsKey.kopiaServerURL.rawValue:
                " https://managed-kopia.example.test:51515 ",
        ])
        let store = AppConfigurationStore(
            defaults: defaults,
            credentials: MemoryCredentialStore()
        )

        let effective = try store.apply(
            serverURL: "https://local-kopia.example.test:51515"
        )

        #expect(
            defaults.values[DefaultsKey.kopiaServerURL.rawValue]
                == "https://local-kopia.example.test:51515"
        )
        #expect(effective == "https://managed-kopia.example.test:51515")
    }

    @Test("configuration stores only the machine password in Keychain")
    func storesMachinePassword() throws {
        let defaults = MemoryDefaults([
            DefaultsKey.kopiaServerURL.rawValue:
                " https://kopia.example.test:51515 ",
        ])
        let credentials = MemoryCredentialStore()
        let store = AppConfigurationStore(
            defaults: defaults,
            credentials: credentials
        )

        try store.store(serverPassword: " machine-password ")
        let configuration = try store.load()

        #expect(configuration == AppConfiguration(
            serverURL: "https://kopia.example.test:51515",
            serverPassword: "machine-password"
        ))
        #expect(credentials.values == [
            .serverPassword: " machine-password ",
        ])
        #expect(defaults.values.values.contains("machine-password") == false)
    }

    @Test("configuration fails safely when either required value is absent")
    func rejectsMissingConfiguration() {
        let missingURL = AppConfigurationStore(
            defaults: MemoryDefaults(),
            credentials: MemoryCredentialStore([
                .serverPassword: "machine-password",
            ])
        )
        #expect(
            throws: AppConfigurationStore.Error.missingValue("kopiaServerURL")
        ) {
            try missingURL.load()
        }

        let missingPassword = AppConfigurationStore(
            defaults: MemoryDefaults([
                DefaultsKey.kopiaServerURL.rawValue:
                    "https://kopia.example.test:51515",
            ]),
            credentials: MemoryCredentialStore()
        )
        #expect(
            throws: AppConfigurationStore.Error.missingValue("serverPassword")
        ) {
            try missingPassword.load()
        }
    }

    @Test("bootstrap provisions the process user's machine identity")
    func provisionsMachineIdentity() async throws {
        let state = try BootstrapCommandState()
        let command = BootstrapCommand(
            applyServerURL: { requestedURL in
                state.events.append("applyURL")
                state.requestedURL = requestedURL
                return "https://managed-kopia.example.test:51515/"
            },
            storeServerPassword: { password in
                state.events.append("storePassword")
                state.storedPassword = password
            },
            resolveAccount: {
                state.events.append("resolveAccount")
                return TargetAccount(
                    username: "sacuser",
                    homeURL: state.homeURL
                )
            },
            hostname: {
                state.events.append("hostname")
                return "SC-SAC-01.example.test"
            },
            generatePassword: {
                state.events.append("generatePassword")
                return "machine-password"
            },
            bootstrapRepository: { credentials, context in
                state.events.append("bootstrapRepository")
                state.bootstrapCredentials = credentials
                state.context = context
            },
            writeError: { state.errors.append($0) }
        )

        let status = await command.run(arguments: [
            "--server-url", "https://local-kopia.example.test:51515",
            "--bootstrap-user", "bootstrap@woodsweep",
            "--bootstrap-password", "bootstrap-password",
        ])

        #expect(status == 0)
        #expect(state.events == [
            "applyURL",
            "resolveAccount",
            "generatePassword",
            "hostname",
            "bootstrapRepository",
            "storePassword",
        ])
        #expect(
            state.requestedURL
                == "https://local-kopia.example.test:51515"
        )
        #expect(try state.bootstrapCredentials == KopiaBootstrapCredentials(
            user: #require(KopiaUser("bootstrap@woodsweep")),
            password: "bootstrap-password"
        ))
        #expect(state.context?.serverURL
            == "https://managed-kopia.example.test:51515")
        #expect(state.context?.user.value == "woodsweep@sc-sac-01")
        #expect(state.context?.homeURL == state.homeURL)
        #expect(state.storedPassword == "machine-password")
        #expect(state.errors.isEmpty)
    }

    @Test("bootstrap returns usage, configuration, and server failures")
    func returnsFailureClasses() async throws {
        let usageState = try BootstrapCommandState()
        let usage = command(state: usageState)
        #expect(await usage.run(arguments: ["--unknown"]) == 64)
        #expect(usageState.events.isEmpty)
        #expect(usageState.errors.count == 1)
        #expect(usageState.errors[0].isEmpty == false)

        let configurationState = try BootstrapCommandState()
        configurationState.applyError = AppConfigurationStore.Error
            .missingValue("kopiaServerURL")
        #expect(
            await command(state: configurationState).run(arguments: validArgs)
                == 78
        )
        #expect(configurationState.storedPassword == nil)

        let serverState = try BootstrapCommandState()
        serverState.bootstrapError = KopiaClient.Error.commandFailed(
            command: "server users add",
            status: 1,
            message: "access denied"
        )
        #expect(
            await command(state: serverState).run(arguments: validArgs) == 69
        )
        #expect(serverState.storedPassword == nil)
    }

    private var validArgs: [String] {
        [
            "--server-url", "https://kopia.example.test:51515",
            "--bootstrap-user", "bootstrap@woodsweep",
            "--bootstrap-password", "bootstrap-password",
        ]
    }

    private func command(state: BootstrapCommandState) -> BootstrapCommand {
        BootstrapCommand(
            applyServerURL: { value in
                if let error = state.applyError {
                    throw error
                }
                return value
            },
            storeServerPassword: { state.storedPassword = $0 },
            resolveAccount: {
                TargetAccount(username: "sacuser", homeURL: state.homeURL)
            },
            hostname: { "sc-sac-01" },
            generatePassword: { "machine-password" },
            bootstrapRepository: { _, _ in
                if let error = state.bootstrapError {
                    throw error
                }
            },
            writeError: { state.errors.append($0) }
        )
    }
}

private final class BootstrapCommandState: @unchecked Sendable {
    let homeURL: URL
    var events: [String] = []
    var requestedURL: String?
    var storedPassword: String?
    var bootstrapCredentials: KopiaBootstrapCredentials?
    var context: KopiaContext?
    var errors: [String] = []
    var applyError: (any Error)?
    var bootstrapError: (any Error)?

    init() throws {
        let homeURL = FileManager.default.temporaryDirectory.appending(
            path: "WoodSweepBootstrapTests-\(UUID().uuidString)",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: homeURL,
            withIntermediateDirectories: false
        )
        self.homeURL = homeURL.resolvingSymlinksInPath().standardizedFileURL
    }

    deinit {
        try? FileManager.default.removeItem(at: homeURL)
    }
}

private final class MemoryDefaults: DefaultsStoring, @unchecked Sendable {
    var values: [String: String]
    var effectiveValues: [String: String]

    init(
        _ values: [String: String] = [:],
        effectiveValues: [String: String] = [:]
    ) {
        self.values = values
        self.effectiveValues = effectiveValues
    }

    func string(forKey key: String) -> String? {
        effectiveValues[key] ?? values[key]
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
