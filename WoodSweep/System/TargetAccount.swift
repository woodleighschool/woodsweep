import Darwin
import Foundation
import SystemConfiguration

nonisolated struct TargetAccount: Equatable, Sendable {
    let username: String
    let homeURL: URL
}

nonisolated protocol TargetAccountResolving: Sendable {
    func resolve() throws -> TargetAccount
}

nonisolated struct SystemTargetAccountResolver: TargetAccountResolving {
    enum Error: Swift.Error, Equatable, LocalizedError {
        case accountUnavailable
        case notEffectiveUser
        case notConsoleUser
        case homeUnavailable

        var errorDescription: String? {
            switch self {
            case .accountUnavailable:
                "The current account is unavailable."
            case .notEffectiveUser:
                "Run as a non-root login user."
            case .notConsoleUser:
                "The current account is not the active console user."
            case .homeUnavailable:
                "The current home directory is unavailable."
            }
        }
    }

    func resolve() throws -> TargetAccount {
        guard let effectiveAccount = getpwuid(geteuid()),
              let effectiveName = effectiveAccount.pointee.pw_name
        else {
            throw Error.accountUnavailable
        }
        let username = String(cString: effectiveName)

        guard username != "root"
        else {
            throw Error.notEffectiveUser
        }

        guard let accountHome = FileManager.default.homeDirectory(
            forUser: username
        ) else {
            throw Error.homeUnavailable
        }

        var userID: uid_t = 0
        var groupID: gid_t = 0
        guard let consoleUser = SCDynamicStoreCopyConsoleUser(
            nil,
            &userID,
            &groupID
        ) as String?,
            consoleUser == username
        else {
            throw Error.notConsoleUser
        }

        guard accountHome.path.hasPrefix("/") else {
            throw Error.homeUnavailable
        }

        let standardizedHome = accountHome.standardizedFileURL
        guard standardizedHome.path != "/",
              standardizedHome.path != "/Users",
              try isRealDirectory(standardizedHome)
        else {
            throw Error.homeUnavailable
        }

        let canonicalHome = standardizedHome
            .resolvingSymlinksInPath()
            .standardizedFileURL
        let usersURL = URL(
            filePath: "/Users",
            directoryHint: .isDirectory
        ).standardizedFileURL
        guard canonicalHome.path != "/",
              canonicalHome.path != "/Users",
              canonicalHome.deletingLastPathComponent() == usersURL
        else {
            throw Error.homeUnavailable
        }

        let libraryURL = canonicalHome.appending(
            path: "Library",
            directoryHint: .isDirectory
        )
        guard try isRealDirectory(libraryURL) else {
            throw Error.homeUnavailable
        }

        do {
            _ = try FileManager.default.contentsOfDirectory(
                at: canonicalHome,
                includingPropertiesForKeys: nil,
                options: []
            )
            _ = try FileManager.default.contentsOfDirectory(
                at: libraryURL,
                includingPropertiesForKeys: nil,
                options: []
            )
        } catch {
            throw Error.homeUnavailable
        }

        return TargetAccount(username: username, homeURL: canonicalHome)
    }

    private func isRealDirectory(_ url: URL) throws -> Bool {
        var info = stat()
        guard Darwin.lstat(url.path, &info) == 0 else {
            return false
        }
        guard info.st_mode & S_IFMT != S_IFLNK else {
            return false
        }
        return info.st_mode & S_IFMT == S_IFDIR
    }
}
