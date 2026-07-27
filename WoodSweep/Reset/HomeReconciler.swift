import Foundation
import OSLog

nonisolated enum HomeResetOperation: Equatable, Sendable {
    case clearing(String)
    case removing(String)
}

protocol HomeReconciling: Sendable {
    // periphery:ignore
    func reconcile(
        _ scope: HomeScope,
        progress: @Sendable (HomeResetOperation) async -> Void
    ) async throws
}

nonisolated struct HomeReconciler: HomeReconciling {
    private let standardDirectories: [(name: String, permissions: Int)] = [
        ("Desktop", 0o700),
        ("Documents", 0o700),
        ("Downloads", 0o700),
        ("Movies", 0o700),
        ("Music", 0o700),
        ("Pictures", 0o700),
        ("Public", 0o755),
        (".Trash", 0o700),
    ]

    private let preserved = Set(["Library", ".CFUserTextEncoding"])

    func reconcile(
        _ scope: HomeScope,
        progress: @Sendable (HomeResetOperation) async -> Void
    ) async throws {
        Log.home.info("Starting home reconciliation")

        for directory in standardDirectories {
            let operation = HomeResetOperation.clearing(directory.name)
            await progress(operation)

            do {
                let directoryURL = try scope.url(for: directory.name)
                try scope.ensureDirectory(
                    at: directoryURL,
                    permissions: directory.permissions
                )
                try scope.emptyDirectory(at: directoryURL)
            } catch {
                logFailure(operation, error: error)
                throw error
            }
        }

        let topLevelNames: [String]
        do {
            topLevelNames = try FileManager.default
                .contentsOfDirectory(atPath: scope.canonicalHomeURL.path)
                .sorted()
        } catch {
            Log.home.error(
                "Home reconciliation failed while enumerating the home root: \(error.localizedDescription, privacy: .private)"
            )
            throw HomeScope.Error.unavailable
        }

        let standardNames = Set(standardDirectories.map(\.name))
        for name in topLevelNames
            where standardNames.contains(name) == false
            && preserved.contains(name) == false
        {
            let operation = HomeResetOperation.removing(name)
            await progress(operation)

            do {
                try scope.removeItem(at: scope.url(for: name))
            } catch {
                logFailure(operation, error: error)
                throw error
            }
        }

        Log.home.info("Completed home reconciliation")
    }

    private func logFailure(
        _ operation: HomeResetOperation,
        error: any Swift.Error
    ) {
        let name = switch operation {
        case let .clearing(name), let .removing(name):
            name
        }
        Log.home.error(
            "Home reconciliation failed for \(name, privacy: .private): \(error.localizedDescription, privacy: .private)"
        )
    }
}
