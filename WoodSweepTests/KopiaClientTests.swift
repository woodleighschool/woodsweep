import Foundation
import Testing
@testable import WoodSweep

@Suite("Kopia client")
struct KopiaClientTests {
    @Test("missing config connects and validates")
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
            "repository", "connect", "s3",
            "--bucket", "exam-backups",
            "--endpoint", "s3.example.test",
            "--access-key", "access",
            "--secret-access-key", "secret",
            "--cache-directory", fixture.cacheDirectory.path,
            "--no-check-for-updates",
            "--region", "ap-southeast-2",
            "--prefix", "sac/",
        ])
        #expect(invocations[1].arguments == fixture.baseArguments + [
            "repository", "status", "--json",
        ])
        #expect(
            invocations.allSatisfy {
                $0.arguments.contains("--no-persist-credentials")
                    && $0.arguments.contains("password")
            }
        )
    }

    @Test("matching connected settings skip reconnect")
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

    @Test("empty optional settings match omitted settings")
    func normalizesOptionalSettings() async throws {
        let fixture = try KopiaFixture(region: nil, prefix: nil)
        try fixture.writeRepositoryConfig(region: "", prefix: "")
        let runner = RecordingProcessRunner(results: [.status])
        let client = KopiaClient(
            processRunner: runner,
            executableProvider: { fixture.executable }
        )

        try await client.prepare(fixture.context)

        #expect(await runner.invocations.count == 1)
    }

    @Test("stale settings replace only local config and retain cache")
    func replacesStaleRepositoryConfig() async throws {
        let fixture = try KopiaFixture()
        try fixture.writeRepositoryConfig(bucket: "old-bucket")
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

    @Test("non-empty optional values retain their exact bytes")
    func preservesOptionalSettingBytes() async throws {
        let fixture = try KopiaFixture(
            region: " ap-southeast-2 ",
            prefix: " sac/ "
        )
        let runner = RecordingProcessRunner(results: [.success, .status])
        let client = KopiaClient(
            processRunner: runner,
            executableProvider: { fixture.executable }
        )

        try await client.prepare(fixture.context)

        let arguments = try #require(
            await runner.invocations.first?.arguments
        )
        let regionIndex = try #require(arguments.firstIndex(of: "--region"))
        let prefixIndex = try #require(arguments.firstIndex(of: "--prefix"))
        #expect(arguments[regionIndex + 1] == " ap-southeast-2 ")
        #expect(arguments[prefixIndex + 1] == " sac/ ")
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
            #expect(description.contains("password") == false)
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

    @Test("cancellation terminates the launched child")
    func cancelsChild() async {
        let task = Task {
            try await ProcessRunner().run(
                executable: URL(filePath: "/bin/sleep"),
                arguments: ["10"]
            )
        }

        try? await Task.sleep(for: .milliseconds(100))
        task.cancel()

        await #expect(throws: CancellationError.self) {
            try await task.value
        }
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
    let executable: URL
    let context: KopiaContext

    var baseArguments: [String] {
        [
            "--config-file", configFile.path,
            "--password", "password",
            "--no-persist-credentials",
            "--no-progress",
        ]
    }

    init(region: String? = "ap-southeast-2", prefix: String? = "sac/") throws {
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
            settings: RepositorySettings(
                endpoint: "s3.example.test",
                bucket: "exam-backups",
                region: region,
                prefix: prefix,
                accessKeyID: "access"
            ),
            credentials: RepositoryCredentials(
                secretAccessKey: "secret",
                repositoryPassword: "password"
            ),
            homeURL: homeDirectory
        )
        self.root = root
        self.homeDirectory = context.homeURL
        self.outsideDirectory = outsideDirectory
        configFile = context.configFile
        cacheDirectory = context.cacheDirectory
        executable = root.appending(path: "kopia")
        self.context = context
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func writeRepositoryConfig(
        bucket: String = "exam-backups",
        region: String? = "ap-southeast-2",
        prefix: String? = "sac/",
        at destination: URL? = nil
    ) throws {
        let destination = destination ?? configFile
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let optionalValues = [
            region.map { "\"region\":\"\($0)\"," } ?? "",
            prefix.map { "\"prefix\":\"\($0)\"," } ?? "",
        ].joined()
        let json = """
        {
          "storage": {
            "type": "s3",
            "config": {
              "bucket": "\(bucket)",
              "endpoint": "s3.example.test",
              "accessKeyID": "access",
              "secretAccessKey": "secret",
              \(optionalValues)
              "unused": "ignored"
            }
          }
        }
        """
        try Data(json.utf8).write(to: destination)
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
}
