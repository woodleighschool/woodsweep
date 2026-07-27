import Foundation
import OSLog

nonisolated struct KopiaContext: Equatable, Sendable {
    let settings: RepositorySettings
    let credentials: RepositoryCredentials
    let configFile: URL
    let cacheDirectory: URL
}

extension KopiaContext {
    nonisolated init(
        configuration: AppConfiguration,
        targetAccount: TargetAccount
    ) {
        let applicationSupport = targetAccount.homeURL.appending(
            path: "Library/Application Support/WoodSweep/kopia",
            directoryHint: .isDirectory
        )
        let cacheDirectory = targetAccount.homeURL.appending(
            path: "Library/Caches/WoodSweep/kopia",
            directoryHint: .isDirectory
        )
        self.init(
            settings: configuration.repository,
            credentials: configuration.credentials,
            configFile: applicationSupport.appending(
                path: "repository.config"
            ),
            cacheDirectory: cacheDirectory
        )
    }
}

nonisolated protocol KopiaServicing: Sendable {
    // periphery:ignore
    func prepare(_ context: KopiaContext) async throws
    // periphery:ignore
    func validate(_ context: KopiaContext) async throws
    // periphery:ignore
    func snapshot(homeURL: URL, context: KopiaContext) async throws
}

actor KopiaClient: KopiaServicing {
    enum Error: Swift.Error, Equatable, LocalizedError {
        case launchFailed(command: String, message: String)
        case commandFailed(command: String, status: Int32, message: String)

        var errorDescription: String? {
            switch self {
            case let .launchFailed(command, message):
                "Kopia \(command) could not start: \(message)"
            case let .commandFailed(command, status, message):
                if message.isEmpty {
                    "Kopia \(command) exited with status \(status)."
                } else {
                    "Kopia \(command) failed: \(message)"
                }
            }
        }
    }

    private let processRunner: any ProcessRunning
    private let executableProvider: @Sendable () throws -> URL
    private var operationActive = false
    private var operationWaiters: [CheckedContinuation<Void, Never>] = []

    init(
        processRunner: any ProcessRunning,
        executableProvider: @escaping @Sendable () throws -> URL
    ) {
        self.processRunner = processRunner
        self.executableProvider = executableProvider
    }

    func prepare(_ context: KopiaContext) async throws {
        await acquireOperation()
        defer { releaseOperation() }
        try Task.checkCancellation()

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: context.configFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.createDirectory(
            at: context.cacheDirectory,
            withIntermediateDirectories: true
        )

        var connected = false
        if fileManager.fileExists(atPath: context.configFile.path) {
            connected = repositoryMatches(context)
            if connected == false {
                try fileManager.removeItem(at: context.configFile)
            }
        }

        if connected == false {
            try await connect(context)
        }
        try await validateUnlocked(context)
    }

    func validate(_ context: KopiaContext) async throws {
        await acquireOperation()
        defer { releaseOperation() }
        try Task.checkCancellation()
        try await validateUnlocked(context)
    }

    func snapshot(homeURL: URL, context: KopiaContext) async throws {
        await acquireOperation()
        defer { releaseOperation() }
        try Task.checkCancellation()
        try await execute(
            command: "snapshot create",
            arguments: baseArguments(context) + [
                "snapshot", "create", homeURL.path,
            ]
        )
    }

    private func connect(_ context: KopiaContext) async throws {
        var arguments = baseArguments(context) + [
            "repository", "connect", "s3",
            "--bucket", context.settings.bucket,
            "--endpoint", context.settings.endpoint,
            "--access-key", context.settings.accessKeyID,
            "--secret-access-key", context.credentials.secretAccessKey,
            "--cache-directory", context.cacheDirectory.path,
            "--no-check-for-updates",
        ]
        if let region = normalized(context.settings.region) {
            arguments.append(contentsOf: ["--region", region])
        }
        if let prefix = normalized(context.settings.prefix) {
            arguments.append(contentsOf: ["--prefix", prefix])
        }
        try await execute(
            command: "repository connect",
            arguments: arguments
        )
    }

    private func validateUnlocked(_ context: KopiaContext) async throws {
        try await execute(
            command: "repository status",
            arguments: baseArguments(context) + [
                "repository", "status", "--json",
            ]
        )
    }

    private func execute(
        command: String,
        arguments: [String]
    ) async throws {
        let executable: URL
        do {
            executable = try executableProvider()
        } catch let error as KopiaExecutable.Error {
            Log.kopia.error("\(command, privacy: .public) could not start")
            throw Error.launchFailed(
                command: command,
                message: error.localizedDescription
            )
        } catch {
            Log.kopia.error("\(command, privacy: .public) could not start")
            throw Error.launchFailed(
                command: command,
                message: "The Kopia process could not start."
            )
        }

        let result: ProcessResult
        do {
            Log.kopia.info("Running \(command, privacy: .public)")
            result = try await processRunner.run(
                executable: executable,
                arguments: arguments
            )
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            Log.kopia.error("\(command, privacy: .public) could not start")
            throw Error.launchFailed(
                command: command,
                message: "The Kopia process could not start."
            )
        }

        Log.kopia.info(
            "\(command, privacy: .public) exited \(result.terminationStatus)"
        )
        guard result.terminationStatus == 0 else {
            throw Error.commandFailed(
                command: command,
                status: result.terminationStatus,
                message: result.standardError.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
            )
        }
    }

    private func repositoryMatches(_ context: KopiaContext) -> Bool {
        guard
            let data = try? Data(contentsOf: context.configFile),
            let repository = try? JSONDecoder().decode(
                KopiaRepositoryConfig.self,
                from: data
            )
        else {
            return false
        }

        let storage = repository.storage
        return storage.type == "s3"
            && storage.config.bucket == context.settings.bucket
            && storage.config.endpoint == context.settings.endpoint
            && storage.config.accessKeyID == context.settings.accessKeyID
            && storage.config.secretAccessKey
            == context.credentials.secretAccessKey
            && normalized(storage.config.region)
            == normalized(context.settings.region)
            && normalized(storage.config.prefix)
            == normalized(context.settings.prefix)
    }

    private func baseArguments(_ context: KopiaContext) -> [String] {
        [
            "--config-file", context.configFile.path,
            "--password", context.credentials.repositoryPassword,
            "--no-persist-credentials",
            "--no-progress",
        ]
    }

    private func normalized(_ value: String?) -> String? {
        guard let value else {
            return nil
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func acquireOperation() async {
        if operationActive == false {
            operationActive = true
            return
        }
        await withCheckedContinuation { continuation in
            operationWaiters.append(continuation)
        }
    }

    private func releaseOperation() {
        guard operationWaiters.isEmpty == false else {
            operationActive = false
            return
        }
        operationWaiters.removeFirst().resume()
    }
}
