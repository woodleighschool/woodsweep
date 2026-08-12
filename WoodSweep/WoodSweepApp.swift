import AppKit
import Darwin
import SwiftUI

@main
enum WoodSweepMain {
    @MainActor
    static func main() async {
        var arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.first == "bootstrap" {
            arguments.removeFirst()
            let status = await BootstrapCommand.live.run(
                arguments: arguments
            )
            Darwin.exit(status)
        }

        WoodSweepApp.main()
    }
}

struct WoodSweepApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    @State private var coordinator: ResetCoordinator

    init() {
        let defaults = UserDefaults.standard
        let credentials = KeychainCredentialStore()
        let configuration = AppConfigurationStore(
            defaults: defaults,
            credentials: credentials
        )
        let accountResolver = SystemTargetAccountResolver()
        let processRunner = ProcessRunner()
        let kopia = KopiaClient(
            processRunner: processRunner,
            executableProvider: {
                try KopiaExecutable.bundled()
            }
        )
        let officeController = WorkspaceOfficeApplicationController()
        let officeApplications = OfficeApplications(
            controller: officeController
        )
        let officeResetter = OfficeResetter()
        let homeReconciler = HomeReconciler()
        let restartRequester = RestartRequester()
        let coordinator = ResetCoordinator(
            configurationLoader: configuration,
            targetAccountResolver: accountResolver,
            kopia: kopia,
            officeApplications: officeApplications,
            officeResetter: officeResetter,
            homeReconciler: homeReconciler,
            restartRequester: restartRequester
        )

        _coordinator = State(initialValue: coordinator)
        appDelegate.coordinator = coordinator
    }

    var body: some Scene {
        WindowGroup {
            RootView(coordinator: coordinator)
        }
        .defaultSize(width: 488, height: 280)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
