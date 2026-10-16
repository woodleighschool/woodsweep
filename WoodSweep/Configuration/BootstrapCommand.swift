import Darwin
import Foundation
import Security

nonisolated struct BootstrapCommand: Sendable {
    enum Error: Swift.Error, Equatable, LocalizedError {
        case requiresRoot
        case passwordGenerationFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case .requiresRoot:
                "Bootstrap must run as root."
            case let .passwordGenerationFailed(status):
                "Unable to generate a machine password (\(status))."
            }
        }
    }

    let credentials: any CredentialStoring
    let isRoot: @Sendable () -> Bool
    let generateDeviceID: @Sendable () -> UUID
    let generatePassword: @Sendable () throws -> String
    let bootstrapRepository: @Sendable (KopiaBootstrapCredentials, AppConfiguration) async throws -> Void

    func run(arguments: BootstrapArguments) async throws -> AppConfiguration {
        guard isRoot() else {
            throw Error.requiresRoot
        }
        let stored: AppConfiguration?
        do {
            stored = try credentials.load()
        } catch is DecodingError {
            stored = nil
        }
        let configuration = try AppConfiguration(
            serverURL: arguments.serverURL,
            serverPassword: stored?.serverPassword ?? generatePassword(),
            deviceID: stored?.deviceID ?? generateDeviceID()
        )
        // Save before changing the server so a failed enrollment can reuse the same credential.
        if configuration != stored {
            try credentials.save(configuration)
        }
        try await bootstrapRepository(
            KopiaBootstrapCredentials(user: arguments.user, password: arguments.bootstrapPassword),
            configuration
        )
        return configuration
    }
}

extension BootstrapCommand {
    static var live: BootstrapCommand {
        let client = KopiaClient(
            processRunner: ProcessRunner(),
            executableProvider: { try KopiaExecutable.bundled() }
        )
        return BootstrapCommand(
            credentials: KeychainCredentialStore(),
            isRoot: { geteuid() == 0 },
            generateDeviceID: { UUID() },
            generatePassword: generateMachinePassword,
            bootstrapRepository: { credentials, configuration in
                try await KopiaContext.withTemporaryHome(configuration: configuration) { context in
                    try await client.bootstrap(credentials: credentials, context: context)
                }
            }
        )
    }

    private nonisolated static func generateMachinePassword() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        guard status == errSecSuccess else {
            throw Error.passwordGenerationFailed(status)
        }
        return Data(bytes).base64EncodedString()
    }
}
