import ArgumentParser
import Foundation
import Testing
@testable import WoodSweep

@Suite("Bootstrap")
struct BootstrapTests {
    private let deviceID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!

    @Test("first enrollment saves the complete machine credential before contacting the server")
    func enrollsMachine() async throws {
        let store = MemoryCredentialStore()
        let configuration = try await command(store: store) { configuration in
            #expect(store.configuration == configuration)
            #expect(store.writes == 1)
        }.run(arguments: arguments())

        #expect(configuration.serverURL == "https://kopia.example.test:443")
        #expect(configuration.deviceID == deviceID)
        #expect(configuration.serverPassword == "machine-password")
        #expect(configuration.user.value == "00000000-0000-4000-8000-000000000001@woodsweep")
    }

    @Test("rerunning after an interrupted bootstrap retains the credential and identity")
    func retriesInterruptedEnrollment() async throws {
        let store = MemoryCredentialStore()
        await #expect(throws: TestError.offline) {
            try await command(store: store) { _ in throw TestError.offline }
                .run(arguments: arguments())
        }
        let saved = try #require(store.configuration)
        #expect(store.writes == 1)

        let retry = BootstrapCommand(
            credentials: store,
            isRoot: { true },
            generateDeviceID: { Issue.record("Device ID must not be regenerated"); return UUID() },
            generatePassword: { throw TestError.mustNotCall },
            bootstrapRepository: { _, configuration in
                #expect(configuration == saved)
            }
        )
        #expect(try await retry.run(arguments: arguments()) == saved)
        #expect(store.writes == 1)
    }

    @Test("a failed credential write never changes the server")
    func stopsBeforeServerOnStoreFailure() async throws {
        let store = MemoryCredentialStore()
        store.writeError = TestError.storeUnavailable
        await #expect(throws: TestError.storeUnavailable) {
            try await command(store: store) { _ in Issue.record("Server must not be called") }
                .run(arguments: arguments())
        }
        #expect(store.configuration == nil)
    }

    @Test("bootstrap requires root before reading or writing credentials")
    func rejectsNonRoot() async throws {
        let store = MemoryCredentialStore()
        let command = BootstrapCommand(
            credentials: store,
            isRoot: { false },
            generateDeviceID: { Issue.record("Device ID must not be regenerated"); return UUID() },
            generatePassword: { throw TestError.mustNotCall },
            bootstrapRepository: { _, _ in Issue.record("Server must not be called") }
        )
        await #expect(throws: BootstrapCommand.Error.requiresRoot) {
            try await command.run(arguments: arguments())
        }
        #expect(store.reads == 0)
        #expect(store.writes == 0)
    }

    @Test("changing servers retains the machine identity and persists the new endpoint first")
    func changesServer() async throws {
        let store = MemoryCredentialStore()
        store.configuration = try AppConfiguration(
            serverURL: "https://old.example.test:51515", serverPassword: "existing", deviceID: deviceID
        )
        let configuration = try await command(store: store) { configuration in
            #expect(store.configuration == configuration)
        }.run(arguments: arguments())
        #expect(configuration.serverPassword == "existing")
        #expect(configuration.deviceID == deviceID)
        #expect(configuration.serverURL == "https://kopia.example.test:443")
    }

    @Test("configuration round trips as one validated record")
    func validatesConfiguration() throws {
        let configuration = try AppConfiguration(
            serverURL: " https://kopia.example.test/ ", serverPassword: "password", deviceID: deviceID
        )
        let data = try JSONEncoder().encode(configuration)
        #expect(!String(decoding: data, as: UTF8.self).contains("hostname"))
        #expect(try JSONDecoder().decode(AppConfiguration.self, from: data) == configuration)
        for url in ["http://kopia.example.test", "https://user@kopia.example.test", "https://kopia.example.test:0", "https://kopia.example.test:65536", "https://kopia.example.test/path", "https://kopia.example.test?x=y"] {
            #expect(throws: AppConfiguration.Error.invalidServerURL) {
                try AppConfiguration(serverURL: url, serverPassword: "password", deviceID: deviceID)
            }
        }
        #expect(throws: AppConfiguration.Error.notBootstrapped) {
            try AppConfigurationStore(credentials: MemoryCredentialStore()).load()
        }
    }

    @Test("CLI handles help and rejects unknown commands without opening the app")
    func parsesCLI() throws {
        #expect(try WoodSweepCLI.parseAsRoot(["status"]) is WoodSweepCLI.Status)
        #expect(try WoodSweepCLI.parseAsRoot(["bootstrap"] + argumentStrings) is WoodSweepCLI.Bootstrap)
        #expect(throws: (any Error).self) { try WoodSweepCLI.parseAsRoot(["unknown"]) }
        #expect(throws: (any Error).self) { try WoodSweepCLI.parseAsRoot(["status", "--unknown"]) }
        #expect(throws: (any Error).self) { try BootstrapArguments.parse(["--server-url", "https://kopia.example.test"]) }
        _ = try WoodSweepCLI.parseAsRoot(["--help"])
        #expect(WoodSweepCLI.helpMessage().contains("status"))
    }

    private var argumentStrings: [String] {
        ["--server-url", "https://kopia.example.test", "--bootstrap-user", "bootstrap@woodsweep", "--bootstrap-password", "bootstrap-password"]
    }

    private func arguments() throws -> BootstrapArguments {
        try BootstrapArguments.parse(argumentStrings)
    }

    private func command(
        store: MemoryCredentialStore,
        provision: @escaping @Sendable (AppConfiguration) async throws -> Void
    ) -> BootstrapCommand {
        BootstrapCommand(
            credentials: store,
            isRoot: { true },
            generateDeviceID: { deviceID },
            generatePassword: { "machine-password" },
            bootstrapRepository: { credentials, configuration in
                #expect(credentials.user.value == "bootstrap@woodsweep")
                #expect(credentials.password == "bootstrap-password")
                try await provision(configuration)
            }
        )
    }
}

private enum TestError: Error {
    case offline
    case storeUnavailable
    case mustNotCall
}

private final class MemoryCredentialStore: CredentialStoring, @unchecked Sendable {
    var configuration: AppConfiguration?
    var reads = 0
    var writes = 0
    var writeError: (any Error)?

    func load() throws -> AppConfiguration? {
        reads += 1
        return configuration
    }

    func save(_ configuration: AppConfiguration) throws {
        if let writeError {
            throw writeError
        }
        writes += 1
        self.configuration = configuration
    }
}
