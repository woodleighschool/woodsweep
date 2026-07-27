import Foundation
import OSLog

nonisolated struct KopiaContext: Equatable, Sendable {
    let settings: RepositorySettings
    let credentials: RepositoryCredentials
    let homeURL: URL

    var configFile: URL {
        homeURL.appending(
            path: "Library/Application Support/WoodSweep/kopia/repository.config"
        )
    }

    var cacheDirectory: URL {
        homeURL.appending(
            path: "Library/Caches/WoodSweep/kopia",
            directoryHint: .isDirectory
        )
    }

    init(
        settings: RepositorySettings,
        credentials: RepositoryCredentials,
        homeURL: URL
    ) throws {
        let scope = try HomeScope(homeURL: homeURL)
        self.settings = settings
        self.credentials = credentials
        self.homeURL = scope.canonicalHomeURL
    }
}

extension KopiaContext {
    nonisolated init(
        configuration: AppConfiguration,
        targetAccount: TargetAccount
    ) throws {
        try self.init(
            settings: configuration.repository,
            credentials: configuration.credentials,
            homeURL: targetAccount.homeURL
        )
    }
}

nonisolated protocol KopiaServicing: Sendable {
    func prepare(_ context: KopiaContext) async throws
    func validate(_ context: KopiaContext) async throws
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

        let scope = try HomeScope(homeURL: context.homeURL)
        try scope.ensureDirectoryHierarchy(
            at: context.configFile.deletingLastPathComponent(),
            permissions: 0o700
        )
        try scope.ensureDirectoryHierarchy(
            at: context.cacheDirectory,
            permissions: 0o700
        )

        let configData = try scope.dataIfRegularFile(at: context.configFile)
        let connected = repositoryMatches(configData, context: context)
        if connected == false {
            try scope.unlinkRegularFileOrSymbolicLink(
                at: context.configFile
            )
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

    private func repositoryMatches(
        _ data: Data?,
        context: KopiaContext
    ) -> Bool {
        guard
            let data,
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
        guard let value, value.isEmpty == false else {
            return nil
        }
        return value
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
