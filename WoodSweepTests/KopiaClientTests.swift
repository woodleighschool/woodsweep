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
        root = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString,
            directoryHint: .isDirectory
        )
        homeDirectory = root.appending(
            path: "home",
            directoryHint: .isDirectory
        )
        configFile = homeDirectory.appending(
            path: "Library/Application Support/WoodSweep/kopia/repository.config"
        )
        cacheDirectory = homeDirectory.appending(
            path: "Library/Caches/WoodSweep/kopia",
            directoryHint: .isDirectory
        )
        executable = root.appending(path: "kopia")
        context = KopiaContext(
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
            configFile: configFile,
            cacheDirectory: cacheDirectory
        )
        try FileManager.default.createDirectory(
            at: homeDirectory,
            withIntermediateDirectories: true
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: root)
    }

    func writeRepositoryConfig(
        bucket: String = "exam-backups",
        region: String? = "ap-southeast-2",
        prefix: String? = "sac/"
    ) throws {
        try FileManager.default.createDirectory(
            at: configFile.deletingLastPathComponent(),
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
        try Data(json.utf8).write(to: configFile)
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
