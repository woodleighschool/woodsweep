nonisolated enum ResetOperation: Equatable, Sendable {
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
    let message: String
}

enum ResetState: Equatable, Sendable {
    case checking
    case confirmation(username: String)
    case closingApps([OfficeApplicationStatus])
    case backingUp
    case resetting(ResetOperation)
    case failed(ResetFailure)
    case restartRequired
}
