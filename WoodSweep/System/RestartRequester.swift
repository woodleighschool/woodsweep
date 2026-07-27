import CoreServices
import Foundation

nonisolated protocol RestartRequesting: Sendable {
    func requestRestart() throws
}

nonisolated struct RestartRequester: RestartRequesting {
    enum Error: Swift.Error, Equatable, LocalizedError {
        case appleEventFailed(OSStatus)

        var errorDescription: String? {
            switch self {
            case let .appleEventFailed(status):
                "The restart dialog could not be requested (\(status))."
            }
        }
    }

    func requestRestart() throws {
        var processID: pid_t = 0
        var target = AEAddressDesc()
        let addressStatus = AECreateDesc(
            DescType(typeKernelProcessID),
            &processID,
            MemoryLayout<pid_t>.size,
            &target
        )
        guard addressStatus == noErr else {
            throw Error.appleEventFailed(OSStatus(addressStatus))
        }
        defer {
            AEDisposeDesc(&target)
        }

        var event = AppleEvent()
        let eventStatus = AECreateAppleEvent(
            AEEventClass(kCoreEventClass),
            AEEventID(kAEShowRestartDialog),
            &target,
            AEReturnID(kAutoGenerateReturnID),
            AETransactionID(kAnyTransactionID),
            &event
        )
        guard eventStatus == noErr else {
            throw Error.appleEventFailed(OSStatus(eventStatus))
        }
        defer {
            AEDisposeDesc(&event)
        }

        let sendStatus = AESendMessage(
            &event,
            nil,
            AESendMode(kAENoReply),
            kAEDefaultTimeout
        )
        guard sendStatus == noErr else {
            throw Error.appleEventFailed(sendStatus)
        }
    }
}
