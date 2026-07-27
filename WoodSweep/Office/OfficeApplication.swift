import Foundation

enum OfficeApplication: String, CaseIterable, Identifiable, Sendable {
    case word
    case excel
    case powerPoint

    var id: Self {
        self
    }

    var displayName: String {
        switch self {
        case .word:
            "Microsoft Word"
        case .excel:
            "Microsoft Excel"
        case .powerPoint:
            "Microsoft PowerPoint"
        }
    }

    var bundleIdentifier: String {
        switch self {
        case .word:
            "com.microsoft.Word"
        case .excel:
            "com.microsoft.Excel"
        case .powerPoint:
            "com.microsoft.Powerpoint"
        }
    }

    var applicationURL: URL {
        URL(filePath: "/Applications/\(displayName).app")
    }
}

struct OfficeApplicationStatus: Identifiable, Equatable, Sendable {
    let application: OfficeApplication
    // periphery:ignore
    let isRunning: Bool
    // periphery:ignore
    let isWaitingForTermination: Bool

    var id: OfficeApplication {
        application
    }
}

@MainActor
protocol OfficeApplicationControlling {
    func isRunning(_ application: OfficeApplication) -> Bool
    func requestTermination(_ application: OfficeApplication) -> Bool
}

@MainActor
protocol OfficeApplicationManaging {
    // periphery:ignore
    func runningStatuses() -> [OfficeApplicationStatus]
    // periphery:ignore
    func requestTerminationOfRunningApplications()
    // periphery:ignore
    func waitForAllApplicationsToClose(
        onChange: @escaping ([OfficeApplicationStatus]) -> Void
    ) async
}
