nonisolated enum ResetOperation: Equatable, Sendable {
    // periphery:ignore
    case checkingConnection
    case backingUp
    case resettingWord
    case resettingExcel
    case resettingPowerPoint
    case clearing(String)
    case removing(String)
}

nonisolated struct ResetFailure: Equatable, Sendable {
    let operation: ResetOperation
    // periphery:ignore
    let message: String
    let canRetry: Bool
}

enum ResetState: Equatable, Sendable {
    case checking
    case backupUnavailable(String)
    case confirmation(username: String)
    case closingApps([OfficeApplicationStatus])
    case backingUp
    case resetting(ResetOperation)
    case failed(ResetFailure)
    case restartRequired
}
