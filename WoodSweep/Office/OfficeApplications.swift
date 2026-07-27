import AppKit
import Foundation
import OSLog

@MainActor
struct WorkspaceOfficeApplicationController:
    OfficeApplicationControlling
{
    func isRunning(_ application: OfficeApplication) -> Bool {
        NSRunningApplication.runningApplications(
            withBundleIdentifier: application.bundleIdentifier
        ).isEmpty == false
    }

    func requestTermination(_ application: OfficeApplication) -> Bool {
        let results = NSRunningApplication.runningApplications(
            withBundleIdentifier: application.bundleIdentifier
        ).map { $0.terminate() }
        return results.contains(true)
    }
}

@MainActor
final class OfficeApplications: OfficeApplicationManaging {
    private let controller: any OfficeApplicationControlling
    private var terminationRequested: Set<OfficeApplication> = []

    init(
        controller: any OfficeApplicationControlling =
            WorkspaceOfficeApplicationController()
    ) {
        self.controller = controller
    }

    func runningStatuses() -> [OfficeApplicationStatus] {
        let runningApplications = Set(
            OfficeApplication.allCases.filter(controller.isRunning)
        )
        terminationRequested.formIntersection(runningApplications)

        return OfficeApplication.allCases.compactMap { application in
            guard runningApplications.contains(application) else {
                return nil
            }
            return OfficeApplicationStatus(
                application: application,
                isRunning: true,
                isWaitingForTermination: terminationRequested.contains(
                    application
                )
            )
        }
    }

    func requestTerminationOfRunningApplications() {
        for application in OfficeApplication.allCases
            where controller.isRunning(application)
        {
            let accepted = controller.requestTermination(application)
            Log.office.info(
                "Requested graceful termination for \(application.displayName, privacy: .public)"
            )
            if accepted {
                terminationRequested.insert(application)
            }
        }
    }

    func waitForAllApplicationsToClose(
        onChange: @escaping ([OfficeApplicationStatus]) -> Void
    ) async {
        var previousStatuses: [OfficeApplicationStatus]?

        while Task.isCancelled == false {
            let statuses = runningStatuses()
            if statuses != previousStatuses {
                logClosedApplications(
                    previous: previousStatuses,
                    current: statuses
                )
                onChange(statuses)
                previousStatuses = statuses
            }

            if statuses.isEmpty {
                Log.office.info(
                    "All supported Office applications are closed"
                )
                return
            }

            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
        }
    }

    private func logClosedApplications(
        previous: [OfficeApplicationStatus]?,
        current: [OfficeApplicationStatus]
    ) {
        guard let previous else {
            return
        }
        let runningApplications = Set(current.map(\.application))
        for status in previous
            where runningApplications.contains(status.application) == false
        {
            Log.office.info(
                "\(status.application.displayName, privacy: .public) closed"
            )
        }
    }
}
