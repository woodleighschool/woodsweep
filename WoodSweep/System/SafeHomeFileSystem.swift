import Darwin
import Foundation

nonisolated struct HomeScope: Equatable, Sendable {
    enum Error: Swift.Error, Equatable, LocalizedError {
        case outsideHome
        case unavailable
        case notDirectory
        case symlinkTraversal

        var errorDescription: String? {
            switch self {
            case .outsideHome:
                "The requested path is outside the target home."
            case .unavailable:
                "The requested home path is unavailable."
            case .notDirectory:
                "The requested home path is not a directory."
            case .symlinkTraversal:
                "The requested home path would traverse a symbolic link."
            }
        }
    }

    private let homeURL: URL

    init(homeURL: URL) throws {
        guard homeURL.isFileURL else {
            throw Error.outsideHome
        }

        let standardizedHome = homeURL.standardizedFileURL
        guard standardizedHome.path != "/",
              standardizedHome.path != "/Users"
        else {
            throw Error.outsideHome
        }

        switch try Self.nodeKind(at: standardizedHome) {
        case .symbolicLink:
            throw Error.symlinkTraversal
        case .directory:
            break
        case .other:
            throw Error.notDirectory
        case nil:
            throw Error.unavailable
        }

        let canonicalHome = standardizedHome
            .resolvingSymlinksInPath()
            .standardizedFileURL
        guard canonicalHome.path != "/",
              canonicalHome.path != "/Users"
        else {
            throw Error.outsideHome
        }
        self.homeURL = canonicalHome
    }

    func url(for relativePath: String) throws -> URL {
        guard relativePath.hasPrefix("/") == false else {
            throw Error.outsideHome
        }
        let candidate = homeURL.appending(path: relativePath).standardizedFileURL
        return try contained(candidate)
    }

    func children(of directory: URL) throws -> [URL] {
        let directory = try contained(directory)
        try rejectSymlinkAncestors(of: directory)

        switch try Self.nodeKind(at: directory) {
        case .symbolicLink:
            throw Error.symlinkTraversal
        case .directory:
            break
        case .other:
            throw Error.notDirectory
        case nil:
            return []
        }

        do {
            return try FileManager.default
                .contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil,
                    options: []
                )
                .map(contained)
        } catch let error as Error {
            throw error
        } catch {
            throw Error.unavailable
        }
    }

    func removeItem(at item: URL) throws {
        let item = try contained(item)
        try rejectSymlinkAncestors(of: item)

        switch try Self.nodeKind(at: item) {
        case .directory:
            for child in try children(of: item) {
                try removeItem(at: child)
            }
            guard Darwin.rmdir(item.path) == 0 else {
                throw Error.unavailable
            }
        case .symbolicLink, .other:
            guard Darwin.unlink(item.path) == 0 else {
                throw Error.unavailable
            }
        case nil:
            return
        }
    }

    func ensureDirectory(
        at directory: URL,
        permissions: Int
    ) throws {
        let directory = try contained(directory)
        try rejectSymlinkAncestors(of: directory)

        switch try Self.nodeKind(at: directory) {
        case .directory:
            break
        case .symbolicLink, .other:
            try removeItem(at: directory)
            try createDirectory(at: directory, permissions: permissions)
        case nil:
            try createDirectory(at: directory, permissions: permissions)
        }

        do {
            try FileManager.default.setAttributes(
                [.posixPermissions: permissions],
                ofItemAtPath: directory.path
            )
        } catch {
            throw Error.unavailable
        }
    }

    func emptyDirectory(at directory: URL) throws {
        for child in try children(of: directory) {
            try removeItem(at: child)
        }
    }

    private func contained(_ candidate: URL) throws -> URL {
        guard candidate.isFileURL else {
            throw Error.outsideHome
        }

        let candidate = candidate.standardizedFileURL
        guard candidate != homeURL,
              candidate.path.hasPrefix(homeURL.path + "/")
        else {
            throw Error.outsideHome
        }
        return candidate
    }

    private func rejectSymlinkAncestors(of item: URL) throws {
        let relativePath = String(item.path.dropFirst(homeURL.path.count + 1))
        let components = relativePath.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count > 1 else {
            return
        }

        var ancestor = homeURL
        for component in components.dropLast() {
            ancestor.append(path: String(component))
            switch try Self.nodeKind(at: ancestor) {
            case .symbolicLink:
                throw Error.symlinkTraversal
            case .directory:
                continue
            case .other:
                throw Error.notDirectory
            case nil:
                return
            }
        }
    }

    private func createDirectory(
        at directory: URL,
        permissions: Int
    ) throws {
        do {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: permissions]
            )
        } catch {
            throw Error.unavailable
        }
    }

    private enum NodeKind {
        case directory
        case symbolicLink
        case other
    }

    private static func nodeKind(at url: URL) throws -> NodeKind? {
        var info = stat()
        guard Darwin.lstat(url.path, &info) == 0 else {
            if errno == ENOENT {
                return nil
            }
            throw Error.unavailable
        }

        switch info.st_mode & S_IFMT {
        case S_IFDIR:
            return .directory
        case S_IFLNK:
            return .symbolicLink
        default:
            return .other
        }
    }
}
