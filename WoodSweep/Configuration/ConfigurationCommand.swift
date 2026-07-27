import Foundation

nonisolated struct ConfigurationCommand: Sendable {
    private let apply: @Sendable (ConfigurationUpdate) throws -> Void
    private let load: @Sendable () throws -> AppConfiguration
    private let resolveAccount:
        @Sendable (String) throws -> TargetAccount
    private let prepareRepository:
        @Sendable (KopiaContext) async throws -> Void
    private let writeError: @Sendable (String) -> Void

    init(
        apply: @escaping @Sendable (ConfigurationUpdate) throws -> Void,
        load: @escaping @Sendable () throws -> AppConfiguration,
        resolveAccount:
        @escaping @Sendable (String) throws -> TargetAccount,
        prepareRepository:
        @escaping @Sendable (KopiaContext) async throws -> Void,
        writeError: @escaping @Sendable (String) -> Void
    ) {
        self.apply = apply
        self.load = load
        self.resolveAccount = resolveAccount
        self.prepareRepository = prepareRepository
        self.writeError = writeError
    }

    func run(arguments: [String]) async -> Int32 {
        let update: ConfigurationUpdate
        do {
            update = try ConfigurationArguments.parse(arguments)
        } catch {
            writeError(error.localizedDescription)
            return 64
        }

        let context: KopiaContext
        do {
            try apply(update)
            let configuration = try load()
            let account = try resolveAccount(configuration.targetUsername)
            context = KopiaContext(
                configuration: configuration,
                targetAccount: account
            )
        } catch {
            writeError(error.localizedDescription)
            return 78
        }

        do {
            try await prepareRepository(context)
            return 0
        } catch {
            writeError(error.localizedDescription)
            return 69
        }
    }
}

extension ConfigurationCommand {
    static let live: ConfigurationCommand = {
        let store = AppConfigurationStore(
            defaults: UserDefaults.standard,
            credentials: KeychainCredentialStore()
        )
        let resolver = SystemTargetAccountResolver()
        let client = KopiaClient(
            processRunner: ProcessRunner(),
            executableProvider: { try KopiaExecutable.bundled() }
        )

        return ConfigurationCommand(
            apply: { try store.apply($0) },
            load: { try store.load() },
            resolveAccount: { try resolver.resolve(username: $0) },
            prepareRepository: { try await client.prepare($0) },
            writeError: writeStandardError
        )
    }()

    private nonisolated static func writeStandardError(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}
