import Foundation
import Testing
@testable import WoodSweep

@Suite("Reset coordinator")
@MainActor
struct ResetCoordinatorTests {
    @Test("snapshot failure prevents every reset operation")
    func snapshotFailureStopsCleanup() async throws {
        let fixture = try CoordinatorFixture(
            snapshotResults: [.failure(TestError.snapshot)]
        )

        await fixture.coordinator.start()
        await fixture.coordinator.confirmReset()

        #expect(await fixture.events.values == [
            .loadConfiguration,
            .resolveAccount,
            .prepareRepository,
            .listRunningApplications,
            .validateRepository,
            .snapshot,
        ])
        guard case let .failed(failure) = fixture.coordinator.state else {
            Issue.record("Expected a stage-local failure")
            return
        }
        #expect(failure.operation == .backingUp)
        #expect(failure.canRetry)
        #expect(fixture.coordinator.allowsTermination)
    }

    @Test("successful cleanup is serial and ends at restart required")
    func successfulResetUsesExactOrder() async throws {
        let fixture = try CoordinatorFixture()

        await fixture.coordinator.start()
        await fixture.coordinator.confirmReset()
        #expect(fixture.coordinator.state == .restartRequired)

        try fixture.coordinator.requestRestart()

        #expect(await fixture.events.values == [
            .loadConfiguration,
            .resolveAccount,
            .prepareRepository,
            .listRunningApplications,
            .validateRepository,
            .snapshot,
            .resetWord,
            .resetExcel,
            .resetPowerPoint,
            .reconcileHome,
            .restartRequired,
        ])
        #expect(fixture.restartRequester.requestCount == 1)
    }

    @Test("confirmation is required before Office or snapshot work")
    func requiresConfirmation() async throws {
        let fixture = try CoordinatorFixture()

        await fixture.coordinator.start()

        #expect(fixture.coordinator.state == .confirmation(username: "sac"))
        #expect(await fixture.events.values == [
            .loadConfiguration,
            .resolveAccount,
            .prepareRepository,
        ])
        #expect(fixture.officeApplications.terminationRequestCount == 0)
        #expect(fixture.officeApplications.waitCount == 0)
        #expect(fixture.coordinator.allowsTermination)
    }

    @Test("concurrent startup launches one prerequisite pipeline")
    func startupIsSingleFlight() async throws {
        let prepareGate = AsyncGate()
        let snapshotGate = AsyncGate()
        let fixture = try CoordinatorFixture(
            prepareGate: prepareGate,
            snapshotGate: snapshotGate
        )

        let firstStart = Task {
            await fixture.coordinator.start()
        }
        await prepareGate.waitUntilEntered()
        #expect(fixture.coordinator.state == .checking)
        #expect(fixture.coordinator.allowsTermination)

        let concurrentStart = Task {
            await fixture.coordinator.start()
        }
        await concurrentStart.value

        #expect(await fixture.events.values == [
            .loadConfiguration,
            .resolveAccount,
            .prepareRepository,
        ])
        #expect(fixture.coordinator.state == .checking)

        await prepareGate.open()
        await firstStart.value

        #expect(fixture.coordinator.state == .confirmation(username: "sac"))
        #expect(await fixture.events.values == [
            .loadConfiguration,
            .resolveAccount,
            .prepareRepository,
        ])

        let reset = Task {
            await fixture.coordinator.confirmReset()
        }
        await snapshotGate.waitUntilEntered()

        #expect(fixture.coordinator.state == .backingUp)

        await snapshotGate.open()
        await reset.value
    }

    @Test("one Quit Apps request waits for all scoped applications")
    func quitAppsWaitsForEveryApplication() async throws {
        let running = OfficeApplication.allCases.map {
            status($0, waiting: false)
        }
        let waiting = OfficeApplication.allCases.map {
            status($0, waiting: true)
        }
        let fixture = try CoordinatorFixture(
            officeStatusResults: [running, []],
            waitStatusChanges: [waiting, []]
        )

        await fixture.coordinator.start()
        await fixture.coordinator.confirmReset()

        #expect(fixture.coordinator.state == .closingApps(running))

        await fixture.coordinator.quitApps()

        #expect(fixture.officeApplications.terminationRequestCount == 1)
        #expect(fixture.officeApplications.waitCount == 1)
        #expect(fixture.officeApplications.emittedStatusChanges == [
            waiting,
            [],
        ])
        #expect(fixture.coordinator.state == .restartRequired)
    }

    @Test("an application relaunched before snapshot returns to Close Apps")
    func relaunchedApplicationStopsSnapshot() async throws {
        let initial = [
            status(.word, waiting: false),
            status(.excel, waiting: false),
        ]
        let waiting = initial.map {
            status($0.application, waiting: true)
        }
        let relaunched = [status(.word, waiting: false)]
        let fixture = try CoordinatorFixture(
            officeStatusResults: [initial, relaunched],
            waitStatusChanges: [waiting, []]
        )

        await fixture.coordinator.start()
        await fixture.coordinator.confirmReset()
        await fixture.coordinator.quitApps()

        #expect(fixture.coordinator.state == .closingApps(relaunched))
        #expect(await fixture.events.values == [
            .loadConfiguration,
            .resolveAccount,
            .prepareRepository,
            .listRunningApplications,
            .listRunningApplications,
        ])
        #expect(fixture.officeApplications.terminationRequestCount == 1)
    }

    @Test("repository validation immediately precedes snapshot")
    func revalidatesBeforeSnapshot() async throws {
        let fixture = try CoordinatorFixture()

        await fixture.coordinator.start()
        await fixture.coordinator.confirmReset()

        let events = await fixture.events.values
        let snapshotIndex = try #require(events.firstIndex(of: .snapshot))
        #expect(snapshotIndex > 0)
        #expect(events[snapshotIndex - 1] == .validateRepository)
    }

    @Test(
        "first Office error hard-stops subsequent operations",
        arguments: OfficeApplication.allCases
    )
    func officeFailureStopsImmediately(
        application: OfficeApplication
    ) async throws {
        let fixture = try CoordinatorFixture(
            officeFailure: application
        )

        await fixture.coordinator.start()
        await fixture.coordinator.confirmReset()

        let events = await fixture.events.values
        let failingEvent = CoordinatorEvent.reset(application)
        #expect(events.last == failingEvent)
        guard case let .failed(failure) = fixture.coordinator.state else {
            Issue.record("Expected a stage-local failure")
            return
        }
        #expect(failure.operation == ResetOperation.reset(application))
        #expect(failure.canRetry == false)
    }

    @Test("first home error hard-stops with the current operation")
    func homeFailureStopsImmediately() async throws {
        let fixture = try CoordinatorFixture(
            homeFailure: .home
        )

        await fixture.coordinator.start()
        await fixture.coordinator.confirmReset()

        #expect(await fixture.events.values.suffix(4) == [
            .resetWord,
            .resetExcel,
            .resetPowerPoint,
            .reconcileHome,
        ])
        #expect(
            fixture.coordinator.state == .failed(ResetFailure(
                operation: .removing("student.txt"),
                message: TestError.home.localizedDescription,
                canRetry: false
            ))
        )
    }

    @Test("termination is blocked only during backup and reset")
    func allowsTerminationMatchesDestructiveStates() async throws {
        let snapshotGate = AsyncGate()
        let resetGate = AsyncGate()
        let fixture = try CoordinatorFixture(
            snapshotGate: snapshotGate,
            resetGate: resetGate
        )

        await fixture.coordinator.start()
        #expect(fixture.coordinator.allowsTermination)

        let resetTask = Task {
            await fixture.coordinator.confirmReset()
        }
        await snapshotGate.waitUntilEntered()
        #expect(fixture.coordinator.state == .backingUp)
        #expect(fixture.coordinator.allowsTermination == false)

        await snapshotGate.open()
        await resetGate.waitUntilEntered()
        #expect(fixture.coordinator.state == .resetting(.resettingWord))
        #expect(fixture.coordinator.allowsTermination == false)

        await resetGate.open()
        await resetTask.value
        #expect(fixture.coordinator.state == .restartRequired)
        #expect(fixture.coordinator.allowsTermination)
    }

    @Test("backup retry preserves confirmation and repeats preparation")
    func backupRetryDoesNotBypassConfirmation() async throws {
        let fixture = try CoordinatorFixture(
            snapshotResults: [
                .failure(TestError.snapshot),
                .success(()),
            ],
            officeStatusResults: [[], []]
        )

        await fixture.coordinator.start()
        await fixture.coordinator.confirmReset()
        await fixture.coordinator.retry()

        #expect(fixture.coordinator.state == .restartRequired)
        #expect(await fixture.events.values == [
            .loadConfiguration,
            .resolveAccount,
            .prepareRepository,
            .listRunningApplications,
            .validateRepository,
            .snapshot,
            .prepareRepository,
            .listRunningApplications,
            .validateRepository,
            .snapshot,
            .resetWord,
            .resetExcel,
            .resetPowerPoint,
            .reconcileHome,
        ])
    }

    @Test("restart requests are ignored before restart required")
    func restartRequiresCompletedReset() async throws {
        let fixture = try CoordinatorFixture()

        await fixture.coordinator.start()
        try fixture.coordinator.requestRestart()

        #expect(fixture.restartRequester.requestCount == 0)
        #expect(await fixture.events.values.contains(.restartRequired) == false)
    }

    @Test("restart request failures reach the presentation")
    func restartFailureIsReported() async throws {
        let fixture = try CoordinatorFixture(
            restartFailure: .restart
        )

        await fixture.coordinator.start()
        await fixture.coordinator.confirmReset()

        #expect(throws: TestError.restart) {
            try fixture.coordinator.requestRestart()
        }
    }
}

private enum CoordinatorEvent: Equatable, Sendable {
    case loadConfiguration
    case resolveAccount
    case prepareRepository
    case listRunningApplications
    case validateRepository
    case snapshot
    case resetWord
    case resetExcel
    case resetPowerPoint
    case reconcileHome
    case restartRequired

    static func reset(_ application: OfficeApplication) -> Self {
        switch application {
        case .word:
            .resetWord
        case .excel:
            .resetExcel
        case .powerPoint:
            .resetPowerPoint
        }
    }
}

private extension ResetOperation {
    static func reset(_ application: OfficeApplication) -> Self {
        switch application {
        case .word:
            .resettingWord
        case .excel:
            .resettingExcel
        case .powerPoint:
            .resettingPowerPoint
        }
    }
}

private func status(
    _ application: OfficeApplication,
    waiting: Bool
) -> OfficeApplicationStatus {
    OfficeApplicationStatus(
        application: application,
        isRunning: true,
        isWaitingForTermination: waiting
    )
}

private enum TestError: Swift.Error, Equatable, LocalizedError {
    case snapshot
    case office
    case home
    case restart

    var errorDescription: String? {
        switch self {
        case .snapshot:
            "Snapshot failed."
        case .office:
            "Office reset failed."
        case .home:
            "Home reconciliation failed."
        case .restart:
            "Restart request failed."
        }
    }
}

@MainActor
private final class CoordinatorFixture {
    let events = EventRecorder()
    let officeApplications: FakeOfficeApplications
    let restartRequester: FakeRestartRequester
    let coordinator: ResetCoordinator

    private let parent: URL

    init(
        snapshotResults: [Result<Void, TestError>] = [.success(())],
        officeStatusResults: [[OfficeApplicationStatus]] = [[]],
        waitStatusChanges: [[OfficeApplicationStatus]] = [],
        officeFailure: OfficeApplication? = nil,
        homeFailure: TestError? = nil,
        restartFailure: TestError? = nil,
        prepareGate: AsyncGate? = nil,
        snapshotGate: AsyncGate? = nil,
        resetGate: AsyncGate? = nil
    ) throws {
        parent = FileManager.default.temporaryDirectory
            .appending(path: "ResetCoordinatorTests-\(UUID().uuidString)")
        let home = parent.appending(path: "home")
        try FileManager.default.createDirectory(
            at: home,
            withIntermediateDirectories: true
        )
        let scope = try HomeScope(homeURL: home)
        let configuration = AppConfiguration(
            serverURL: "https://kopia.example.test:51515",
            serverPassword: "machine-password"
        )
        officeApplications = FakeOfficeApplications(
            events: events,
            statusResults: officeStatusResults,
            waitStatusChanges: waitStatusChanges
        )
        restartRequester = FakeRestartRequester(
            events: events,
            failure: restartFailure
        )

        coordinator = ResetCoordinator(
            configurationLoader: FakeConfigurationLoader(
                events: events,
                configuration: configuration
            ),
            targetAccountResolver: FakeTargetAccountResolver(
                events: events,
                targetAccount: TargetAccount(
                    username: "sac",
                    homeURL: scope.canonicalHomeURL
                )
            ),
            kopia: FakeKopiaService(
                events: events,
                snapshotResults: snapshotResults,
                prepareGate: prepareGate,
                snapshotGate: snapshotGate
            ),
            officeApplications: officeApplications,
            officeResetter: FakeOfficeResetter(
                events: events,
                failure: officeFailure,
                resetGate: resetGate
            ),
            homeReconciler: FakeHomeReconciler(
                events: events,
                failure: homeFailure
            ),
            restartRequester: restartRequester
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: parent)
    }
}

private actor EventRecorder {
    private nonisolated let storage = Locked<[CoordinatorEvent]>([])

    var values: [CoordinatorEvent] {
        storage.read()
    }

    nonisolated func record(_ event: CoordinatorEvent) {
        storage.withValue { $0.append(event) }
    }
}

private final class Locked<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value

    init(_ value: Value) {
        self.value = value
    }

    func read() -> Value {
        lock.withLock { value }
    }

    func withValue(_ body: (inout Value) -> Void) {
        lock.withLock {
            body(&value)
        }
    }
}

private struct FakeConfigurationLoader: ConfigurationLoading {
    let events: EventRecorder
    let configuration: AppConfiguration

    func load() throws -> AppConfiguration {
        events.record(.loadConfiguration)
        return configuration
    }
}

private struct FakeTargetAccountResolver: TargetAccountResolving {
    let events: EventRecorder
    let targetAccount: TargetAccount

    func resolve() throws -> TargetAccount {
        events.record(.resolveAccount)
        return targetAccount
    }
}

private actor FakeKopiaService: KopiaServicing {
    let events: EventRecorder
    var snapshotResults: [Result<Void, TestError>]
    let prepareGate: AsyncGate?
    let snapshotGate: AsyncGate?
    var prepareCount = 0

    init(
        events: EventRecorder,
        snapshotResults: [Result<Void, TestError>],
        prepareGate: AsyncGate?,
        snapshotGate: AsyncGate?
    ) {
        self.events = events
        self.snapshotResults = snapshotResults
        self.prepareGate = prepareGate
        self.snapshotGate = snapshotGate
    }

    func prepare(_: KopiaContext) async throws {
        events.record(.prepareRepository)
        prepareCount += 1
        if prepareCount == 1, let prepareGate {
            await prepareGate.enter()
        }
    }

    func validate(_: KopiaContext) async throws {
        events.record(.validateRepository)
    }

    func snapshot(homeURL _: URL, context _: KopiaContext) async throws {
        events.record(.snapshot)
        if let snapshotGate {
            await snapshotGate.enter()
        }
        let result = snapshotResults.removeFirst()
        try result.get()
    }
}

@MainActor
private final class FakeOfficeApplications: OfficeApplicationManaging {
    let events: EventRecorder
    private var statusResults: [[OfficeApplicationStatus]]
    private let waitStatusChanges: [[OfficeApplicationStatus]]
    private(set) var terminationRequestCount = 0
    private(set) var waitCount = 0
    private(set) var emittedStatusChanges: [[OfficeApplicationStatus]] = []

    init(
        events: EventRecorder,
        statusResults: [[OfficeApplicationStatus]],
        waitStatusChanges: [[OfficeApplicationStatus]]
    ) {
        self.events = events
        self.statusResults = statusResults
        self.waitStatusChanges = waitStatusChanges
    }

    func runningStatuses() -> [OfficeApplicationStatus] {
        events.record(.listRunningApplications)
        guard statusResults.isEmpty == false else {
            return []
        }
        return statusResults.removeFirst()
    }

    func requestTerminationOfRunningApplications() {
        terminationRequestCount += 1
    }

    func waitForAllApplicationsToClose(
        onChange: @escaping ([OfficeApplicationStatus]) -> Void
    ) async {
        waitCount += 1
        for statuses in waitStatusChanges {
            emittedStatusChanges.append(statuses)
            onChange(statuses)
        }
    }
}

private actor FakeOfficeResetter: OfficeResetting {
    let events: EventRecorder
    let failure: OfficeApplication?
    let resetGate: AsyncGate?

    init(
        events: EventRecorder,
        failure: OfficeApplication?,
        resetGate: AsyncGate?
    ) {
        self.events = events
        self.failure = failure
        self.resetGate = resetGate
    }

    func reset(
        _ application: OfficeApplication,
        in _: HomeScope
    ) async throws {
        events.record(.reset(application))
        if application == .word, let resetGate {
            await resetGate.enter()
        }
        if application == failure {
            throw TestError.office
        }
    }
}

private actor FakeHomeReconciler: HomeReconciling {
    let events: EventRecorder
    let failure: TestError?

    init(
        events: EventRecorder,
        failure: TestError?
    ) {
        self.events = events
        self.failure = failure
    }

    func reconcile(
        _: HomeScope,
        progress: nonisolated(nonsending) @Sendable
        (HomeResetOperation) async -> Void
    ) async throws {
        events.record(.reconcileHome)
        await progress(.clearing("Desktop"))
        await progress(.removing("student.txt"))
        if let failure {
            throw failure
        }
    }
}

private final class FakeRestartRequester:
    RestartRequesting,
    @unchecked Sendable
{
    let events: EventRecorder
    let failure: TestError?
    private let count = Locked(0)

    init(events: EventRecorder, failure: TestError?) {
        self.events = events
        self.failure = failure
    }

    var requestCount: Int {
        count.read()
    }

    func requestRestart() throws {
        count.withValue { $0 += 1 }
        events.record(.restartRequired)
        if let failure {
            throw failure
        }
    }
}

private actor AsyncGate {
    private var entered = false
    private var isOpen = false
    private var entryWaiters: [CheckedContinuation<Void, Never>] = []
    private var openWaiters: [CheckedContinuation<Void, Never>] = []

    func enter() async {
        entered = true
        let waiters = entryWaiters
        entryWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
        guard isOpen == false else {
            return
        }
        await withCheckedContinuation {
            openWaiters.append($0)
        }
    }

    func waitUntilEntered() async {
        guard entered == false else {
            return
        }
        await withCheckedContinuation {
            entryWaiters.append($0)
        }
    }

    func open() {
        isOpen = true
        let waiters = openWaiters
        openWaiters.removeAll()
        for waiter in waiters {
            waiter.resume()
        }
    }
}
