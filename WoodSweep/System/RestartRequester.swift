import CoreServices
import Foundation

nonisolated protocol RestartRequesting: Sendable {
    func requestRestart() throws
}

nonisolated struct RestartRequester: RestartRequesting {
    func requestRestart() throws {
        let target = NSAppleEventDescriptor(
            bundleIdentifier: "com.apple.loginwindow"
        )
        let event = NSAppleEventDescriptor(
            eventClass: AEEventClass(kCoreEventClass),
            eventID: AEEventID(kAERestart),
            targetDescriptor: target,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID)
        )

        _ = try event.sendEvent(options: .noReply, timeout: 0)
    }
}
