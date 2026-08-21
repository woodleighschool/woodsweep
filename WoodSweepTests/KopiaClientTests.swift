import Foundation
import Testing
@testable import WoodSweep

@Suite("Kopia client")
struct KopiaClientTests {
    @Test("missing config connects to the server and validates")
    func connectsMissingRepository() async throws {
        let fixture = try KopiaFixture()
        let runner = RecordingProcessRunner(results: [.success, .status])
        let client = KopiaClient(
            processRunner: runner,
            executableProvider: { fixture.executable }
        )

        try await client.prepare(fixture.context)

        let invocations = await runner.invocations
        #expect(invocations.count == 2)
        #expect(
            invocations.allSatisfy { $0.executable == fixture.executable }
        )
        #expect(invocations[0].arguments == fixture.baseArguments + [
            "repository", "connect", "server",
            "--url", "https://kopia.example.test:51515",
            "--cache-directory", fixture.cacheDirectory.path,
            "--no-check-for-updates",
            "--override-username", "woodsweep",
            "--override-hostname", "sc-sac-01",
        ])
        #expect(invocations[1].arguments == fixture.baseArguments + [
            "repository", "status", "--json",
        ])
        #expect(
            invocations.allSatisfy {
                $0.arguments.contains("--no-persist-credentials")
                    && $0.arguments.contains("machine-password")
            }
        )
    }

    @Test("matching server settings skip reconnect")
    func keepsMatchingRepositoryConnected() async throws {
        let fixture = try KopiaFixture()
        try fixture.writeRepositoryConfig()
        let runner = RecordingProcessRunner(results: [.status])
        let client = KopiaClient(
            processRunner: runner,
            executableProvider: { fixture.executable }
        )

        try await client.prepare(fixture.context)

        let invocations = await runner.invocations
        #expect(invocations.count == 1)
        #expect(invocations[0].arguments.suffix(3) == [
            "repository", "status", "--json",
        ])
        #expect(FileManager.default.fileExists(atPath: fixture.configFile.path))
    }

    @Test("stale server URL replaces only local config and retains cache")
    func replacesStaleRepositoryConfig() async throws {
        let fixture = try KopiaFixture()
        try fixture.writeRepositoryConfig(
            serverURL: "https://old-kopia.example.test:51515"
        )
        try FileManager.default.createDirectory(
            at: fixture.cacheDirectory,
            withIntermediateDirectories: true
        )
        let cachedBlob = fixture.cacheDirectory.appending(path: "keep")
        try Data("cache".utf8).write(to: cachedBlob)
        let runner = RecordingProcessRunner(results: [.success, .status])
        let client = KopiaClient(
            processRunner: runner,
            executableProvider: { fixture.executable }
        )

        try await client.prepare(fixture.context)

        let invocations = await runner.invocations
        #expect(invocations.count == 2)
        #expect(invocations[0].arguments.contains(fixture.cacheDirectory.path))
        #expect(FileManager.default.fileExists(atPath: cachedBlob.path))
        #expect(
            FileManager.default.fileExists(atPath: fixture.configFile.path)
                == false
        )
    }

    @Test("fingerprint-pinned config is replaced for system TLS trust")
    func replacesFingerprintConfig() async throws {
        let fixture = try KopiaFixture()
        try fixture.writeRepositoryConfig(fingerprint: "ABC123")
        let runner = RecordingProcessRunner(results: [.success, .status])
        let client = KopiaClient(
            processRunner: runner,
            executableProvider: { fixture.executable }
        )

        try await client.prepare(fixture.context)

        #expect(await runner.invocations.count == 2)
    }

    @Test("bootstrap adds and immediately activates the machine user")
    func bootstrapsNewMachineUser() async throws {
        let fixture = try KopiaFixture()
        let runner = RecordingProcessRunner(results: [
            .success,
            .users([]),
            .success,
            .success,
            .success,
            .status,
        ])
        let client = KopiaClient(
            processRunner: runner,
            executableProvider: { fixture.executable }
        )

        try await client.bootstrap(
            credentials: fixture.bootstrapCredentials,
            context: fixture.context
        )

        let invocations = await runner.invocations
        #expect(invocations.count == 6)
        #expect(invocations[0].arguments == fixture.bootstrapBaseArguments + [
            "repository", "connect", "server",
            "--url", fixture.context.serverURL,
            "--cache-directory",
            fixture.bootstrapDirectory.appending(path: "cache").path,
            "--no-check-for-updates",
            "--override-username", "bootstrap",
            "--override-hostname", "woodsweep",
        ])
        #expect(invocations[1].arguments == fixture.bootstrapBaseArguments + [
            "server", "users", "list", "--json",
        ])
        #expect(invocations[2].arguments == fixture.bootstrapBaseArguments + [
            "server", "users", "add", "woodsweep@sc-sac-01",
            "--user-password", "machine-password",
        ])
        #expect(invocations[3].arguments == [
            "server", "refresh",
            "--address", fixture.context.serverURL,
            "--server-control-username", "bootstrap@woodsweep",
            "--server-control-password", "bootstrap-password",
        ])
        #expect(invocations[4].arguments == fixture.baseArguments + [
            "repository", "connect", "server",
            "--url", fixture.context.serverURL,
            "--cache-directory", fixture.cacheDirectory.path,
            "--no-check-for-updates",
            "--override-username", "woodsweep",
            "--override-hostname", "sc-sac-01",
        ])
        #expect(invocations[5].arguments == fixture.baseArguments + [
            "repository", "status", "--json",
        ])
        #expect(
            FileManager.default.fileExists(
                atPath: fixture.bootstrapDirectory.path
            ) == false
        )
    }

    @Test("bootstrap rotates an existing machine user's password")
    func bootstrapsExistingMachineUser() async throws {
        let fixture = try KopiaFixture()
        try fixture.writeRepositoryConfig()
        let runner = RecordingProcessRunner(results: [
            .success,
            .users(["woodsweep@sc-sac-01"]),
            .success,
            .success,
            .success,
            .status,
        ])
        let client = KopiaClient(
            processRunner: runner,
            executableProvider: { fixture.executable }
        )

        try await client.bootstrap(
            credentials: fixture.bootstrapCredentials,
            context: fixture.context
        )

        let invocations = await runner.invocations
        #expect(invocations[2].arguments.contains("set"))
        #expect(invocations[2].arguments.contains("add") == false)
        #expect(
            FileManager.default.fileExists(atPath: fixture.configFile.path)
                == false
        )
    }

    @Test("failed bootstrap removes transient state and never connects machine")
    func cleansUpFailedBootstrap() async throws {
        let fixture = try KopiaFixture()
        let runner = RecordingProcessRunner(results: [
            .success,
            .users([]),
            ProcessResult(
                terminationStatus: 1,
                standardOutput: "",
                standardError: "access denied"
            ),
        ])
        let client = KopiaClient(
            processRunner: runner,
            executableProvider: { fixture.executable }
        )

        await #expect(throws: KopiaClient.Error.self) {
            try await client.bootstrap(
                credentials: fixture.bootstrapCredentials,
                context: fixture.context
            )
        }

        #expect(await runner.invocations.count == 3)
        #expect(
            FileManager.default.fileExists(
                atPath: fixture.bootstrapDirectory.path
            ) == false
        )
        #expect(
            FileManager.default.fileExists(atPath: fixture.configFile.path)
                == false
        )
    }

    @Test("preparation rejects a symlinked Kopia ancestor")
    func rejectsSymlinkedKopiaAncestor() async throws {
        let fixture = try KopiaFixture()
        let library = fixture.homeDirectory.appending(
            path: "Library",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: library,
            withIntermediateDirectories: false
        )
        let applicationSupport = library.appending(
            path: "Application Support",
            directoryHint: .isDirectory
        )
        try FileManager.default.createSymbolicLink(
            at: applicationSupport,
            withDestinationURL: fixture.outsideDirectory
        )
        let outsideFile = fixture.outsideDirectory.appending(path: "keep")
        try Data("keep".utf8).write(to: outsideFile)
        let runner = RecordingProcessRunner(results: [.success, .status])
        let client = KopiaClient(
            processRunner: runner,
            executableProvider: { fixture.executable }
        )

        await #expect(throws: HomeScope.Error.symlinkTraversal) {
            try await client.prepare(fixture.context)
        }

        #expect(await runner.invocations.isEmpty)
        #expect(FileManager.default.fileExists(atPath: outsideFile.path))
        #expect(
            FileManager.default.fileExists(
                atPath: fixture.outsideDirectory
                    .appending(path: "WoodSweep").path
            ) == false
        )
        #expect(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: applicationSupport.path
            ) == fixture.outsideDirectory.path
        )
    }

    @Test("a symlink config leaf is unlinked without reading its target")
    func replacesSymlinkedRepositoryConfig() async throws {
        let fixture = try KopiaFixture()
        try FileManager.default.createDirectory(
            at: fixture.configFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let outsideConfig = fixture.outsideDirectory.appending(path: "keep")
        try fixture.writeRepositoryConfig(at: outsideConfig)
        try FileManager.default.createSymbolicLink(
            at: fixture.configFile,
            withDestinationURL: outsideConfig
        )
        let runner = RecordingProcessRunner(results: [.success, .status])
        let client = KopiaClient(
            processRunner: runner,
            executableProvider: { fixture.executable }
        )

        try await client.prepare(fixture.context)

        #expect(await runner.invocations.count == 2)
        #expect(
            FileManager.default.fileExists(atPath: fixture.configFile.path)
                == false
        )
        #expect(FileManager.default.fileExists(atPath: outsideConfig.path))
        #expect(try Data(contentsOf: outsideConfig).isEmpty == false)
    }

    @Test("a directory named repository config is never deleted")
    func rejectsDirectoryRepositoryConfig() async throws {
        let fixture = try KopiaFixture()
        try FileManager.default.createDirectory(
            at: fixture.configFile,
            withIntermediateDirectories: true
        )
        let nestedFile = fixture.configFile.appending(path: "keep")
        try Data("keep".utf8).write(to: nestedFile)
        let runner = RecordingProcessRunner(results: [.success, .status])
        let client = KopiaClient(
            processRunner: runner,
            executableProvider: { fixture.executable }
        )

        await #expect(throws: HomeScope.Error.unsafeNode) {
            try await client.prepare(fixture.context)
        }

        #expect(await runner.invocations.isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.configFile.path))
        #expect(FileManager.default.fileExists(atPath: nestedFile.path))
    }

    @Test("context normalizes URL and hostname and rejects non-system TLS")
    func validatesContextIdentity() throws {
        let fixture = try KopiaFixture()

        #expect(fixture.context.serverURL
            == "https://kopia.example.test:51515")
        #expect(fixture.context.hostname == "sc-sac-01")
        #expect(fixture.context.user.value == "woodsweep@sc-sac-01")

        for serverURL in [
            "http://kopia.example.test:51515",
            "https://user@kopia.example.test:51515",
            "https://kopia.example.test:51515?fingerprint=abc",
        ] {
            #expect(throws: KopiaContext.Error.invalidServerURL) {
                try KopiaContext(
                    serverURL: serverURL,
                    serverPassword: "machine-password",
                    hostname: "sc-sac-01",
                    homeURL: fixture.homeDirectory
                )
            }
        }
    }

    @Test("snapshot has the resolved home as its only source")
    func snapshotsOnlyResolvedHome() async throws {
        let fixture = try KopiaFixture()
        let runner = RecordingProcessRunner(results: [.success])
        let client = KopiaClient(
            processRunner: runner,
            executableProvider: { fixture.executable }
        )

        try await client.snapshot(
            homeURL: fixture.homeDirectory,
            context: fixture.context
        )

        let invocation = try #require(await runner.invocations.first)
        #expect(invocation.arguments == fixture.baseArguments + [
            "snapshot", "create", fixture.homeDirectory.path,
        ])
        #expect(
            invocation.arguments.filter {
                $0 == fixture.homeDirectory.path
            }.count == 1
        )
    }

    @Test("nonzero status reports trimmed stderr without arguments")
    func reportsSafeCommandFailure() async throws {
        let fixture = try KopiaFixture()
        let runner = RecordingProcessRunner(results: [
            ProcessResult(
                terminationStatus: 1,
                standardOutput: "",
                standardError: "  repository unavailable \n"
            ),
        ])
        let client = KopiaClient(
            processRunner: runner,
            executableProvider: { fixture.executable }
        )

        do {
            try await client.validate(fixture.context)
            Issue.record("Expected validation to fail")
        } catch {
            let description = error.localizedDescription
            #expect(description.contains("repository unavailable"))
            #expect(description.contains("machine-password") == false)
            #expect(description.contains("--config-file") == false)
        }
    }
}

@Suite("Process runner")
struct ProcessRunnerTests {
    @Test("drains both streams concurrently and keeps only bounded tails")
    func boundsConcurrentOutput() async throws {
        let script = """
        (dd if=/dev/zero bs=4096 count=100 2>/dev/null | tr '\\0' O; \
        printf OUT-END) & \
        (dd if=/dev/zero bs=4096 count=100 2>/dev/null | tr '\\0' E; \
        printf ERR-END) >&2 & wait
        """

        let result = try await ProcessRunner().run(
            executable: URL(filePath: "/bin/sh"),
            arguments: ["-c", script]
        )

        #expect(result.terminationStatus == 0)
        #expect(result.standardOutput.utf8.count == 256 * 1024)
        #expect(result.standardError.utf8.count == 256 * 1024)
        #expect(result.standardOutput.hasSuffix("OUT-END"))
        #expect(result.standardError.hasSuffix("ERR-END"))
    }
}

private actor RecordingProcessRunner: ProcessRunning {
    struct Invocation: Equatable, Sendable {
        let executable: URL
        let arguments: [String]
    }

    private(set) var invocations: [Invocation] = []
    private var results: [ProcessResult]

    init(results: [ProcessResult]) {
        self.results = results
    }

    func run(
        executable: URL,
        arguments: [String]
    ) async throws -> ProcessResult {
        invocations.append(Invocation(
            executable: executable,
            arguments: arguments
        ))
        return results.removeFirst()
    }
}

private final class KopiaFixture: @unchecked Sendable {
    let root: URL
    let homeDirectory: URL
    let outsideDirectory: URL
    let configFile: URL
    let cacheDirectory: URL
    let bootstrapDirectory: URL
    let executable: URL
    let context: KopiaContext
    let bootstrapCredentials = KopiaBootstrapCredentials(
        user: KopiaUser("bootstrap@woodsweep")!,
        password: "bootstrap-password"
    )

    var baseArguments: [String] {
        [
            "--config-file", configFile.path,
            "--password", "machine-password",
            "--no-persist-credentials",
            "--no-progress",
        ]
    }

    var bootstrapBaseArguments: [String] {
        [
            "--config-file",
            bootstrapDirectory.appending(path: "repository.config").path,
            "--password", "bootstrap-password",
            "--no-persist-credentials",
            "--no-progress",
        ]
    }

    init() throws {
        let root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        let homeDirectory = root.appending(
            path: "home",
            directoryHint: .isDirectory
        )
        let outsideDirectory = root.appending(
            path: "outside",
            directoryHint: .isDirectory
        )
        try FileManager.default.createDirectory(
            at: homeDirectory,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: outsideDirectory,
            withIntermediateDirectories: false
        )
        let context = try KopiaContext(
            serverURL: "https://kopia.example.test:51515/",
            serverPassword: "machine-password",
            hostname: "SC-SAC-01.example.test",
            homeURL: homeDirectory
        )
        self.root = root
        self.homeDirectory = context.homeURL
        self.outsideDirectory = outsideDirectory
        configFile = context.configFile
        cacheDirectory = context.cacheDirectory
        bootstrapDirectory = context.bootstrapDirectory
        executable = root.appending(path: "kopia")
        self.context = context
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func writeRepositoryConfig(
        serverURL: String = "https://kopia.example.test:51515",
        fingerprint: String = "",
        at destination: URL? = nil
    ) throws {
        let destination = destination ?? configFile
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let data = try JSONSerialization.data(withJSONObject: [
            "apiServer": [
                "url": serverURL,
                "serverCertFingerprint": fingerprint,
            ],
            "hostname": "sc-sac-01",
            "username": "woodsweep",
        ])
        try data.write(to: destination)
    }
}

private extension ProcessResult {
    static let success = ProcessResult(
        terminationStatus: 0,
        standardOutput: "",
        standardError: ""
    )
    static let status = ProcessResult(
        terminationStatus: 0,
        standardOutput: "{}",
        standardError: ""
    )

    static func users(_ usernames: [String]) -> ProcessResult {
        let data = try! JSONSerialization.data(
            withJSONObject: usernames.map { ["username": $0] }
        )
        return ProcessResult(
            terminationStatus: 0,
            standardOutput: String(decoding: data, as: UTF8.self),
            standardError: ""
        )
    }
}
