import AppKit
import ArgumentParser
import Darwin
import SwiftUI

@main
enum WoodSweepMain {
    @MainActor
    static func main() async {
        // Xcode launches hosted tests with AppKit arguments, not CLI arguments.
        let isTestHost = NSClassFromString("XCTestCase") != nil
        if CommandLine.arguments.count > 1, isTestHost == false {
            await WoodSweepCLI.main()
            return
        }

        WoodSweepApp.main()
    }
}

struct WoodSweepApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self)
    private var appDelegate

    @State private var coordinator: ResetCoordinator

    init() {
        let configuration = AppConfigurationStore()
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
        Window("WoodSweep", id: "main") {
            RootView(coordinator: coordinator)
        }
        .windowResizability(.contentSize)
    }
}
