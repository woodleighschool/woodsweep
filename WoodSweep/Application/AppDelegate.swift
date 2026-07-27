import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak var coordinator: ResetCoordinator?

    func applicationShouldTerminate(
        _: NSApplication
    ) -> NSApplication.TerminateReply {
        if coordinator?.allowsTermination == false {
            return .terminateCancel
        }
        return .terminateNow
    }
}
