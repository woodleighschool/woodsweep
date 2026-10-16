import ArgumentParser
import Foundation

struct WoodSweepCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "WoodSweep",
        abstract: "Configure or check this Mac's backup repository. Open the app to back up and reset the logged-in account.",
        version: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "development",
        subcommands: [Bootstrap.self, Status.self]
    )

    struct Bootstrap: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Enroll this Mac as root. Safe to run again after an update or failed setup."
        )

        @OptionGroup var options: BootstrapArguments

        mutating func run() async throws {
            let configuration = try await BootstrapCommand.live.run(arguments: options)
            print("Configured \(configuration.user.value) at \(configuration.serverURL).")
        }
    }

    struct Status: AsyncParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Check the machine credential and repository connection without resetting a home."
        )

        mutating func run() async throws {
            let configuration = try AppConfigurationStore().load()
            print("Server: \(configuration.serverURL)")
            print("Account: \(configuration.user.value)")
            try print("Hostname: \(KopiaHostname.current())")
            print("Credential: available in System keychain")
            let clock = ContinuousClock()
            let start = clock.now
            let client = KopiaClient(
                processRunner: ProcessRunner(),
                executableProvider: { try KopiaExecutable.bundled() }
            )
            try await KopiaContext.withTemporaryHome(configuration: configuration) { context in
                try await client.prepare(context)
            }
            print("Repository: available (\(start.duration(to: clock.now)))")
        }
    }
}
