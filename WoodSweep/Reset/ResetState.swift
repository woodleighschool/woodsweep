nonisolated enum ResetOperation: Equatable, Sendable {
    case checkingConnection
    case backingUp
    case resettingWord
    case resettingExcel
    case resettingPowerPoint
    case clearing(String)
    case removing(String)
    case restarting
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
    case restarting
    case failed(ResetFailure)
}
