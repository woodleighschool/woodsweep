import Foundation
import Testing
@testable import WoodSweep

@Suite("Office applications")
@MainActor
struct OfficeApplicationsTests {
    @Test("the reset allowlist contains only Word, Excel, and PowerPoint")
    func definesResetTargets() {
        #expect(OfficeApplication.allCases == [.word, .excel, .powerPoint])
        #expect(OfficeApplication.word.displayName == "Microsoft Word")
        #expect(OfficeApplication.excel.displayName == "Microsoft Excel")
        #expect(
            OfficeApplication.powerPoint.displayName
                == "Microsoft PowerPoint"
        )
        #expect(
            OfficeApplication.word.bundleIdentifier == "com.microsoft.Word"
        )
        #expect(
            OfficeApplication.excel.bundleIdentifier == "com.microsoft.Excel"
        )
        #expect(
            OfficeApplication.powerPoint.bundleIdentifier
                == "com.microsoft.Powerpoint"
        )
        #expect(
            OfficeApplication.powerPoint.applicationURL
                == URL(filePath: "/Applications/Microsoft PowerPoint.app")
        )
    }

    @Test("one request targets every running Office reset app")
    func requestsAllRunningApplications() {
        let controller = FakeOfficeApplicationController(running: [
            "com.microsoft.Word",
            "com.microsoft.Powerpoint",
        ])
        let applications = OfficeApplications(controller: controller)

        applications.requestTerminationOfRunningApplications()

        #expect(controller.requested == [
            "com.microsoft.Word",
            "com.microsoft.Powerpoint",
        ])
        #expect(applications.runningStatuses() == [
            OfficeApplicationStatus(
                application: .word,
                isRunning: true,
                isWaitingForTermination: true
            ),
            OfficeApplicationStatus(
                application: .powerPoint,
                isRunning: true,
                isWaitingForTermination: true
            ),
        ])
    }

    @Test("stopped apps are omitted and a relaunch is no longer waiting")
    func observesTerminationAndRelaunch() {
        let controller = FakeOfficeApplicationController(running: [
            "com.microsoft.Word",
        ])
        let applications = OfficeApplications(controller: controller)
        applications.requestTerminationOfRunningApplications()

        controller.stop(.word)
        #expect(applications.runningStatuses().isEmpty)

        controller.start(.word)
        #expect(applications.runningStatuses() == [
            OfficeApplicationStatus(
                application: .word,
                isRunning: true,
                isWaitingForTermination: false
            ),
        ])
    }

    @Test("a rejected termination remains non-waiting and is retried")
    func retriesRejectedTermination() {
        let controller = FakeOfficeApplicationController(
            running: ["com.microsoft.Word"],
            acceptsTermination: false
        )
        let applications = OfficeApplications(controller: controller)

        applications.requestTerminationOfRunningApplications()

        #expect(controller.requested == ["com.microsoft.Word"])
        #expect(applications.runningStatuses() == [
            OfficeApplicationStatus(
                application: .word,
                isRunning: true,
                isWaitingForTermination: false
            ),
        ])

        controller.setTerminationAccepted(true)
        applications.requestTerminationOfRunningApplications()

        #expect(controller.requested == [
            "com.microsoft.Word",
            "com.microsoft.Word",
        ])
        #expect(applications.runningStatuses() == [
            OfficeApplicationStatus(
                application: .word,
                isRunning: true,
                isWaitingForTermination: true
            ),
        ])
    }

    @Test("waiting emits only changed statuses until every app closes")
    func waitsForAllApplicationsToClose() async {
        let controller = FakeOfficeApplicationController(running: [
            "com.microsoft.Word",
            "com.microsoft.Excel",
        ])
        let applications = OfficeApplications(controller: controller)
        applications.requestTerminationOfRunningApplications()
        let recorder = OfficeStatusRecorder()

        let waitTask = Task {
            await applications.waitForAllApplicationsToClose {
                recorder.record($0)
            }
        }
        await recorder.waitForEmission(count: 1)
        controller.stop(.word)
        await recorder.waitForEmission(count: 2)
        controller.stop(.excel)
        await waitTask.value

        #expect(recorder.changes == [
            [
                OfficeApplicationStatus(
                    application: .word,
                    isRunning: true,
                    isWaitingForTermination: true
                ),
                OfficeApplicationStatus(
                    application: .excel,
                    isRunning: true,
                    isWaitingForTermination: true
                ),
            ],
            [
                OfficeApplicationStatus(
                    application: .excel,
                    isRunning: true,
                    isWaitingForTermination: true
                ),
            ],
            [],
        ])
    }

    @Test("waiting returns when its task is cancelled")
    func cancelsWaiting() async {
        let controller = FakeOfficeApplicationController(running: [
            "com.microsoft.Word",
        ])
        let applications = OfficeApplications(controller: controller)

        let waitTask = Task {
            await applications.waitForAllApplicationsToClose { _ in }
        }
        waitTask.cancel()

        await waitTask.value
        #expect(controller.isRunning(.word))
    }
}

@MainActor
private final class FakeOfficeApplicationController:
    OfficeApplicationControlling
{
    private var running: Set<String>
    private var acceptsTermination: Bool
    private(set) var requested: [String] = []

    init(
        running: Set<String>,
        acceptsTermination: Bool = true
    ) {
        self.running = running
        self.acceptsTermination = acceptsTermination
    }

    func isRunning(_ application: OfficeApplication) -> Bool {
        running.contains(application.bundleIdentifier)
    }

    func requestTermination(_ application: OfficeApplication) -> Bool {
        requested.append(application.bundleIdentifier)
        return acceptsTermination
    }

    func setTerminationAccepted(_ accepted: Bool) {
        acceptsTermination = accepted
    }

    func start(_ application: OfficeApplication) {
        running.insert(application.bundleIdentifier)
    }

    func stop(_ application: OfficeApplication) {
        running.remove(application.bundleIdentifier)
    }
}

@MainActor
private final class OfficeStatusRecorder {
    private(set) var changes: [[OfficeApplicationStatus]] = []
    private var awaitedCount = 0
    private var continuation: CheckedContinuation<Void, Never>?

    func record(_ statuses: [OfficeApplicationStatus]) {
        changes.append(statuses)
        guard changes.count >= awaitedCount, let continuation else {
            return
        }
        self.continuation = nil
        continuation.resume()
    }

    func waitForEmission(count: Int) async {
        guard changes.count < count else {
            return
        }
        precondition(continuation == nil)
        awaitedCount = count
        await withCheckedContinuation {
            continuation = $0
        }
    }
}
