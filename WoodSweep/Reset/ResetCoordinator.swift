import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class ResetCoordinator {
    private(set) var state: ResetState = .checking

    var allowsTermination: Bool {
        switch state {
        case .backingUp, .resetting:
            false
        case .checking,
             .backupUnavailable,
             .confirmation,
             .closingApps,
             .failed,
             .restartRequired:
            true
        }
    }

    private let configurationLoader: any ConfigurationLoading
    private let targetAccountResolver: any TargetAccountResolving
    private let kopia: any KopiaServicing
    private let officeApplications: any OfficeApplicationManaging
    private let officeResetter: any OfficeResetting
    private let homeReconciler: any HomeReconciling
    private let restartRequester: any RestartRequesting

    private var context: KopiaContext?
    private var homeScope: HomeScope?
    private var confirmed = false
    private var snapshotSucceeded = false
    private var isWaitingForApplications = false
    private var currentHomeOperation: ResetOperation?

    init(
        configurationLoader: any ConfigurationLoading,
        targetAccountResolver: any TargetAccountResolving,
        kopia: any KopiaServicing,
        officeApplications: any OfficeApplicationManaging,
        officeResetter: any OfficeResetting,
        homeReconciler: any HomeReconciling,
        restartRequester: any RestartRequesting
    ) {
        self.configurationLoader = configurationLoader
        self.targetAccountResolver = targetAccountResolver
        self.kopia = kopia
        self.officeApplications = officeApplications
        self.officeResetter = officeResetter
        self.homeReconciler = homeReconciler
        self.restartRequester = restartRequester
    }

    func start() async {
        guard state == .checking else {
            return
        }

        Log.reset.info("Checking reset prerequisites")
        confirmed = false
        snapshotSucceeded = false
        context = nil
        homeScope = nil

        do {
            let configuration = try configurationLoader.load()
            let targetAccount = try targetAccountResolver.resolve(
                username: configuration.targetUsername
            )
            let scope = try HomeScope(homeURL: targetAccount.homeURL)
            let context = try KopiaContext(
                configuration: configuration,
                targetAccount: targetAccount
            )

            homeScope = scope
            self.context = context
            try await kopia.prepare(context)

            Log.reset.info("Reset prerequisites are available")
            state = .confirmation(username: targetAccount.username)
        } catch {
            Log.reset.error(
                "Reset prerequisites are unavailable: \(error.localizedDescription, privacy: .private)"
            )
            state = .backupUnavailable(error.localizedDescription)
        }
    }

    func retry() async {
        switch state {
        case .backupUnavailable:
            state = .checking
            await start()
        case let .failed(failure)
            where failure.operation == .backingUp
            && failure.canRetry
            && confirmed:
            guard let context else {
                preconditionFailure(
                    "Confirmed backup retry requires a repository context"
                )
            }

            snapshotSucceeded = false
            state = .checking
            do {
                Log.reset.info("Preparing repository for backup retry")
                try await kopia.prepare(context)
            } catch {
                fail(
                    operation: .backingUp,
                    error: error,
                    canRetry: true
                )
                return
            }
            await continueAfterConfirmation()
        case .checking,
             .confirmation,
             .closingApps,
             .backingUp,
             .resetting,
             .failed,
             .restartRequired:
            return
        }
    }

    func confirmReset() async {
        guard case .confirmation = state else {
            return
        }

        Log.reset.info("Reset confirmed")
        confirmed = true
        await continueAfterConfirmation()
    }

    func quitApps() async {
        guard case .closingApps = state,
              confirmed,
              isWaitingForApplications == false
        else {
            return
        }

        isWaitingForApplications = true
        officeApplications.requestTerminationOfRunningApplications()
        Log.reset.info("Waiting for supported Office applications to close")

        await officeApplications.waitForAllApplicationsToClose {
            [weak self] statuses in
            self?.state = .closingApps(statuses)
        }

        isWaitingForApplications = false
        let statuses = officeApplications.runningStatuses()
        guard statuses.isEmpty else {
            Log.reset.info(
                "A supported Office application is running before backup"
            )
            state = .closingApps(statuses)
            return
        }

        await performBackup()
    }

    func requestRestart() {
        guard state == .restartRequired else {
            return
        }

        do {
            try restartRequester.requestRestart()
        } catch {
            Log.reset.error(
                "Restart request failed: \(error.localizedDescription, privacy: .private)"
            )
        }
    }

    private func continueAfterConfirmation() async {
        guard confirmed else {
            preconditionFailure("Backup requires explicit confirmation")
        }

        let statuses = officeApplications.runningStatuses()
        guard statuses.isEmpty else {
            state = .closingApps(statuses)
            return
        }

        await performBackup()
    }

    private func performBackup() async {
        guard confirmed else {
            preconditionFailure("Backup requires explicit confirmation")
        }
        guard let context, let homeScope else {
            preconditionFailure("Backup requires validated reset context")
        }

        snapshotSucceeded = false
        state = .backingUp
        Log.reset.info("Starting backup")

        do {
            try await kopia.validate(context)
            try await kopia.snapshot(
                homeURL: homeScope.canonicalHomeURL,
                context: context
            )
            snapshotSucceeded = true
            Log.reset.info("Backup completed")
        } catch {
            fail(
                operation: .backingUp,
                error: error,
                canRetry: true
            )
            return
        }

        await performCleanup(in: homeScope)
    }

    private func performCleanup(in scope: HomeScope) async {
        guard snapshotSucceeded else {
            preconditionFailure("Cleanup requires a successful snapshot")
        }

        guard await reset(.word, operation: .resettingWord, in: scope) else {
            return
        }
        guard await reset(.excel, operation: .resettingExcel, in: scope) else {
            return
        }
        guard await reset(
            .powerPoint,
            operation: .resettingPowerPoint,
            in: scope
        ) else {
            return
        }
        guard await reconcileHome(scope) else {
            return
        }

        Log.reset.info("Reset completed")
        state = .restartRequired
    }

    private func reset(
        _ application: OfficeApplication,
        operation: ResetOperation,
        in scope: HomeScope
    ) async -> Bool {
        state = .resetting(operation)
        Log.reset.info(
            "Starting \(application.displayName, privacy: .public) reset"
        )

        do {
            try await officeResetter.reset(application, in: scope)
            return true
        } catch {
            fail(operation: operation, error: error, canRetry: false)
            return false
        }
    }

    private func reconcileHome(_ scope: HomeScope) async -> Bool {
        currentHomeOperation = nil

        do {
            try await homeReconciler.reconcile(scope) {
                [weak self] operation in
                let resetOperation = switch operation {
                case let .clearing(name):
                    ResetOperation.clearing(name)
                case let .removing(name):
                    ResetOperation.removing(name)
                }
                await self?.setHomeOperation(resetOperation)
            }
            currentHomeOperation = nil
            return true
        } catch {
            guard let currentHomeOperation else {
                preconditionFailure(
                    "Home reconciliation must report progress before failing"
                )
            }
            fail(
                operation: currentHomeOperation,
                error: error,
                canRetry: false
            )
            self.currentHomeOperation = nil
            return false
        }
    }

    private func setHomeOperation(_ operation: ResetOperation) {
        currentHomeOperation = operation
        state = .resetting(operation)
    }

    private func fail(
        operation: ResetOperation,
        error: any Swift.Error,
        canRetry: Bool
    ) {
        Log.reset.error(
            "Reset failed at \(String(describing: operation), privacy: .private): \(error.localizedDescription, privacy: .private)"
        )
        state = .failed(ResetFailure(
            operation: operation,
            message: error.localizedDescription,
            canRetry: canRetry
        ))
    }
}
