import ArgumentParser
import Foundation
import Security

nonisolated struct BootstrapCommand: Sendable {
    enum Error: Swift.Error, Equatable, LocalizedError {
        case passwordGenerationFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case let .passwordGenerationFailed(status):
                "Unable to generate a machine password (\(status))."
            }
        }
    }

    private let applyServerURL: @Sendable (String) throws -> String
    private let storeServerPassword: @Sendable (String) throws -> Void
    private let resolveAccount: @Sendable () throws -> TargetAccount
    private let hostname: @Sendable () throws -> String
    private let generatePassword: @Sendable () throws -> String
    private let bootstrapRepository:
        @Sendable (KopiaBootstrapCredentials, KopiaContext) async throws -> Void
    private let writeError: @Sendable (String) -> Void

    init(
        applyServerURL: @escaping @Sendable (String) throws -> String,
        storeServerPassword: @escaping @Sendable (String) throws -> Void,
        resolveAccount: @escaping @Sendable () throws -> TargetAccount,
        hostname: @escaping @Sendable () throws -> String,
        generatePassword: @escaping @Sendable () throws -> String,
        bootstrapRepository:
        @escaping @Sendable (
            KopiaBootstrapCredentials,
            KopiaContext
        ) async throws -> Void,
        writeError: @escaping @Sendable (String) -> Void
    ) {
        self.applyServerURL = applyServerURL
        self.storeServerPassword = storeServerPassword
        self.resolveAccount = resolveAccount
        self.hostname = hostname
        self.generatePassword = generatePassword
        self.bootstrapRepository = bootstrapRepository
        self.writeError = writeError
    }

    func run(arguments: [String]) async -> Int32 {
        let parsedArguments: BootstrapArguments
        do {
            parsedArguments = try BootstrapArguments.parse(arguments)
        } catch {
            writeError(BootstrapArguments.fullMessage(for: error))
            return 64
        }

        let context: KopiaContext
        let machinePassword: String
        do {
            let serverURL = try applyServerURL(parsedArguments.serverURL)
            let account = try resolveAccount()
            machinePassword = try generatePassword()
            context = try KopiaContext(
                serverURL: serverURL,
                serverPassword: machinePassword,
                hostname: hostname(),
                homeURL: account.homeURL
            )
        } catch {
            writeError(error.localizedDescription)
            return 78
        }

        do {
            try await bootstrapRepository(
                KopiaBootstrapCredentials(
                    user: parsedArguments.user,
                    password: parsedArguments.bootstrapPassword
                ),
                context
            )
            try storeServerPassword(machinePassword)
            return 0
        } catch {
            writeError(error.localizedDescription)
            return 69
        }
    }
}

extension BootstrapCommand {
    static let live: BootstrapCommand = {
        let store = AppConfigurationStore(
            defaults: UserDefaults.standard,
            credentials: KeychainCredentialStore()
        )
        let resolver = SystemTargetAccountResolver()
        let client = KopiaClient(
            processRunner: ProcessRunner(),
            executableProvider: { try KopiaExecutable.bundled() }
        )

        return BootstrapCommand(
            applyServerURL: { try store.apply(serverURL: $0) },
            storeServerPassword: { try store.store(serverPassword: $0) },
            resolveAccount: { try resolver.resolve() },
            hostname: { try KopiaHostname.current() },
            generatePassword: generateMachinePassword,
            bootstrapRepository: { credentials, context in
                try await client.bootstrap(
                    credentials: credentials,
                    context: context
                )
            },
            writeError: writeStandardError
        )
    }()

    private nonisolated static func generateMachinePassword() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw Error.passwordGenerationFailed(status)
        }
        return Data(bytes).base64EncodedString()
    }

    private nonisolated static func writeStandardError(_ message: String) {
        FileHandle.standardError.write(Data("\(message)\n".utf8))
    }
}
