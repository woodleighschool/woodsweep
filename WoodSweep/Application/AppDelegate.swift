import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var coordinator: ResetCoordinator?

    func applicationWillFinishLaunching(_: Notification) {
        // A reset utility has no session to resume after login.
        NSApplication.shared.disableRelaunchOnLogin()
    }

    func applicationShouldTerminate(
        _: NSApplication
    ) -> NSApplication.TerminateReply {
        if coordinator?.allowsTermination == false {
            return .terminateCancel
        }
        return .terminateNow
    }
}
