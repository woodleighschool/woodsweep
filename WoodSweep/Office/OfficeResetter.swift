import Darwin
import Foundation
import OSLog

protocol OfficeResetting: Sendable {
    // periphery:ignore
    func reset(
        _ application: OfficeApplication,
        in scope: HomeScope
    ) async throws
}

nonisolated struct OfficeResetter: OfficeResetting {
    func reset(
        _ application: OfficeApplication,
        in scope: HomeScope
    ) async throws {
        Log.office.info(
            "Starting reset for \(application.displayName, privacy: .public)"
        )

        for rule in OfficeResetPolicy.rules(for: application) {
            try apply(rule, in: scope)
        }

        Log.office.info(
            "Completed reset for \(application.displayName, privacy: .public)"
        )
    }

    private func apply(
        _ rule: OfficeResetRule,
        in scope: HomeScope
    ) throws {
        switch rule {
        case let .removeItem(relativePath):
            try scope.removeItem(at: scope.url(for: relativePath))
        case let .removeFiles(directory, extensions):
            let directoryURL = try scope.url(for: directory)
            for child in try scope.children(of: directoryURL) {
                let child = try revalidate(child, in: scope)
                guard extensions.contains(child.pathExtension.lowercased()),
                      try isRegularFileOrSymbolicLink(at: child)
                else {
                    continue
                }
                try scope.unlinkRegularFileOrSymbolicLink(at: child)
            }
        case let .removeFilesWithPrefix(directory, prefix):
            let directoryURL = try scope.url(for: directory)
            for child in try scope.children(of: directoryURL) {
                let child = try revalidate(child, in: scope)
                guard child.lastPathComponent.hasPrefix(prefix) else {
                    continue
                }
                try scope.removeItem(at: child)
            }
        }
    }

    private func revalidate(
        _ child: URL,
        in scope: HomeScope
    ) throws -> URL {
        let homePath = scope.canonicalHomeURL.path
        guard child.path.hasPrefix(homePath + "/") else {
            throw HomeScope.Error.outsideHome
        }
        let relativePath = String(
            child.path.dropFirst(homePath.count + 1)
        )
        return try scope.url(for: relativePath)
    }

    private func isRegularFileOrSymbolicLink(at item: URL) throws -> Bool {
        var info = stat()
        guard Darwin.lstat(item.path, &info) == 0 else {
            if errno == ENOENT {
                return false
            }
            throw HomeScope.Error.unavailable
        }

        let kind = info.st_mode & S_IFMT
        return kind == S_IFREG || kind == S_IFLNK
    }
}
