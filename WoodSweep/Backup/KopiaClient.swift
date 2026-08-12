import Foundation
import OSLog

nonisolated struct KopiaUser: Equatable, Sendable {
    let username: String
    let hostname: String

    init?(_ value: String) {
        let parts = value.split(
            separator: "@",
            maxSplits: 1,
            omittingEmptySubsequences: false
        )
        guard parts.count == 2 else {
            return nil
        }

        let username = String(parts[0])
        let hostname = String(parts[1])
        guard Self.valid(component: username), Self.valid(component: hostname) else {
            return nil
        }
        self.username = username
        self.hostname = hostname
    }

    var value: String {
        "\(username)@\(hostname)"
    }

    private static func valid(component: String) -> Bool {
        let allowed = CharacterSet(
            charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_."
        )
        return component.isEmpty == false
            && component.unicodeScalars.allSatisfy(allowed.contains)
    }
}

nonisolated enum KopiaHostname {
    enum Error: Swift.Error, Equatable, LocalizedError {
        case unavailable

        var errorDescription: String? {
            "The machine hostname is unavailable."
        }
    }

    static func current() throws -> String {
        try normalized(ProcessInfo.processInfo.hostName)
    }

    static func normalized(_ value: String) throws -> String {
        let hostname = value
            .split(separator: ".", maxSplits: 1)
            .first
            .map(String.init)?
            .lowercased() ?? ""
        guard KopiaUser("woodsweep@\(hostname)") != nil else {
            throw Error.unavailable
        }
        return hostname
    }
}

nonisolated struct KopiaBootstrapCredentials: Equatable, Sendable {
    let user: KopiaUser
    let password: String
}

nonisolated struct KopiaContext: Equatable, Sendable {
    enum Error: Swift.Error, Equatable, LocalizedError {
        case invalidServerURL

        var errorDescription: String? {
            "The Kopia server URL must be a valid HTTPS URL."
        }
    }

    static let username = "woodsweep"

    let serverURL: String
    let serverPassword: String
    let hostname: String
    let homeURL: URL

    var user: KopiaUser {
        guard let user = KopiaUser("\(Self.username)@\(hostname)") else {
            preconditionFailure("Validated Kopia identity became invalid")
        }
        return user
    }

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

    var bootstrapDirectory: URL {
        homeURL.appending(
            path: "Library/Caches/WoodSweep/kopia-bootstrap",
            directoryHint: .isDirectory
        )
    }

    init(
        serverURL: String,
        serverPassword: String,
        hostname: String,
        homeURL: URL
    ) throws {
        let serverURL = serverURL.trimmingCharacters(
            in: .whitespacesAndNewlines
        )
        guard var components = URLComponents(string: serverURL),
              components.scheme?.lowercased() == "https",
              components.host?.isEmpty == false,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil
        else {
            throw Error.invalidServerURL
        }
        components.scheme = "https"
        guard let normalizedServerURL = components.url?.absoluteString else {
            throw Error.invalidServerURL
        }

        let normalizedHostname = try KopiaHostname.normalized(hostname)
        let scope = try HomeScope(homeURL: homeURL)
        self.serverURL = normalizedServerURL.hasSuffix("/")
            ? String(normalizedServerURL.dropLast())
            : normalizedServerURL
        self.serverPassword = serverPassword
        self.hostname = normalizedHostname
        self.homeURL = scope.canonicalHomeURL
    }
}

extension KopiaContext {
    nonisolated init(
        configuration: AppConfiguration,
        targetAccount: TargetAccount
    ) throws {
        try self.init(
            serverURL: configuration.serverURL,
            serverPassword: configuration.serverPassword,
            hostname: KopiaHostname.current(),
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

    private struct RepositoryUser: Decodable {
        let username: String
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

    func bootstrap(
        credentials: KopiaBootstrapCredentials,
        context: KopiaContext
    ) async throws {
        await acquireOperation()
        defer { releaseOperation() }
        try Task.checkCancellation()

        let scope = try HomeScope(homeURL: context.homeURL)
        try scope.removeItem(at: context.bootstrapDirectory)
        try scope.ensureDirectoryHierarchy(
            at: context.bootstrapDirectory,
            permissions: 0o700
        )

        let bootstrapConfig = context.bootstrapDirectory.appending(
            path: "repository.config"
        )
        let bootstrapCache = context.bootstrapDirectory.appending(
            path: "cache",
            directoryHint: .isDirectory
        )

        var bootstrapError: (any Swift.Error)?
        do {
            try await connect(
                serverURL: context.serverURL,
                user: credentials.user,
                password: credentials.password,
                configFile: bootstrapConfig,
                cacheDirectory: bootstrapCache
            )

            let users = try await repositoryUsers(
                configFile: bootstrapConfig,
                password: credentials.password
            )
            let operation = users.contains(context.user.value) ? "set" : "add"
            try await execute(
                command: "server users \(operation)",
                arguments: baseArguments(
                    configFile: bootstrapConfig,
                    password: credentials.password
                ) + [
                    "server", "users", operation, context.user.value,
                    "--user-password", context.serverPassword,
                ]
            )
            try await refreshServer(
                serverURL: context.serverURL,
                credentials: credentials
            )
        } catch {
            bootstrapError = error
        }

        do {
            try scope.removeItem(at: context.bootstrapDirectory)
        } catch where bootstrapError == nil {
            throw error
        } catch {
            Log.kopia.error("Unable to remove transient bootstrap state")
        }
        if let bootstrapError {
            throw bootstrapError
        }

        try prepareDirectories(context, scope: scope)
        try scope.unlinkRegularFileOrSymbolicLink(at: context.configFile)
        try await connect(context)
        try await validateUnlocked(context)
    }

    func prepare(_ context: KopiaContext) async throws {
        await acquireOperation()
        defer { releaseOperation() }
        try Task.checkCancellation()

        let scope = try HomeScope(homeURL: context.homeURL)
        try prepareDirectories(context, scope: scope)

        let configData = try scope.dataIfRegularFile(at: context.configFile)
        let connected = repositoryMatches(configData, context: context)
        if connected == false {
            try scope.unlinkRegularFileOrSymbolicLink(at: context.configFile)
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

    private func prepareDirectories(
        _ context: KopiaContext,
        scope: HomeScope
    ) throws {
        try scope.ensureDirectoryHierarchy(
            at: context.configFile.deletingLastPathComponent(),
            permissions: 0o700
        )
        try scope.ensureDirectoryHierarchy(
            at: context.cacheDirectory,
            permissions: 0o700
        )
    }

    private func connect(_ context: KopiaContext) async throws {
        try await connect(
            serverURL: context.serverURL,
            user: context.user,
            password: context.serverPassword,
            configFile: context.configFile,
            cacheDirectory: context.cacheDirectory
        )
    }

    private func connect(
        serverURL: String,
        user: KopiaUser,
        password: String,
        configFile: URL,
        cacheDirectory: URL
    ) async throws {
        try await execute(
            command: "repository connect",
            arguments: baseArguments(
                configFile: configFile,
                password: password
            ) + [
                "repository", "connect", "server",
                "--url", serverURL,
                "--cache-directory", cacheDirectory.path,
                "--no-check-for-updates",
                "--override-username", user.username,
                "--override-hostname", user.hostname,
            ]
        )
    }

    private func repositoryUsers(
        configFile: URL,
        password: String
    ) async throws -> Set<String> {
        let result = try await execute(
            command: "server users list",
            arguments: baseArguments(
                configFile: configFile,
                password: password
            ) + [
                "server", "users", "list", "--json",
            ]
        )
        let users = try JSONDecoder().decode(
            [RepositoryUser].self,
            from: Data(result.standardOutput.utf8)
        )
        return Set(users.map(\.username))
    }

    private func refreshServer(
        serverURL: String,
        credentials: KopiaBootstrapCredentials
    ) async throws {
        try await execute(
            command: "server refresh",
            arguments: [
                "server", "refresh",
                "--address", serverURL,
                "--server-control-username", credentials.user.value,
                "--server-control-password", credentials.password,
            ]
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

    @discardableResult
    private func execute(
        command: String,
        arguments: [String]
    ) async throws -> ProcessResult {
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
        return result
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
            ),
            let server = repository.apiServer
        else {
            return false
        }

        return server.url == context.serverURL
            && (server.serverCertFingerprint ?? "").isEmpty
            && repository.username == context.user.username
            && repository.hostname == context.user.hostname
    }

    private func baseArguments(_ context: KopiaContext) -> [String] {
        baseArguments(
            configFile: context.configFile,
            password: context.serverPassword
        )
    }

    private func baseArguments(
        configFile: URL,
        password: String
    ) -> [String] {
        [
            "--config-file", configFile.path,
            "--password", password,
            "--no-persist-credentials",
            "--no-progress",
        ]
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
