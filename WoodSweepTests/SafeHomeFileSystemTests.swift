import Foundation
import Testing
@testable import WoodSweep

@Suite("Safe home filesystem")
struct SafeHomeFileSystemTests {
    @Test("relative paths cannot escape the home")
    func rejectsEscape() throws {
        let fixture = try HomeFixture()
        let scope = try HomeScope(homeURL: fixture.home)

        #expect(throws: HomeScope.Error.outsideHome) {
            try scope.url(for: "../outside")
        }
        #expect(throws: HomeScope.Error.outsideHome) {
            try scope.url(for: "/tmp/outside")
        }
        #expect(throws: HomeScope.Error.outsideHome) {
            try scope.url(for: "")
        }
    }

    @Test("removing a symlink never removes its destination")
    func removesLinkWithoutTraversal() throws {
        let fixture = try HomeFixture()
        let outsideFile = fixture.outside.appending(path: "keep.txt")
        try Data("keep".utf8).write(to: outsideFile)
        let link = fixture.home.appending(path: "Desktop-link")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: fixture.outside
        )
        let scope = try HomeScope(homeURL: fixture.home)

        try scope.removeItem(at: link)

        #expect(FileManager.default.fileExists(atPath: link.path) == false)
        #expect(FileManager.default.fileExists(atPath: outsideFile.path))
    }

    @Test("destructive access cannot traverse a symlink")
    func rejectsIntermediateSymlink() throws {
        let fixture = try HomeFixture()
        let outsideFile = fixture.outside.appending(path: "keep.txt")
        try Data("keep".utf8).write(to: outsideFile)
        let link = fixture.home.appending(path: "escape")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: fixture.outside
        )
        let scope = try HomeScope(homeURL: fixture.home)
        let escapedFile = try scope.url(for: "escape/keep.txt")

        #expect(throws: HomeScope.Error.symlinkTraversal) {
            try scope.removeItem(at: escapedFile)
        }
        #expect(FileManager.default.fileExists(atPath: outsideFile.path))
    }

    @Test("the home root cannot be a symlink")
    func rejectsSymlinkHome() throws {
        let fixture = try HomeFixture()
        let link = fixture.parent.appending(path: "linked-home")
        try FileManager.default.createSymbolicLink(
            at: link,
            withDestinationURL: fixture.home
        )

        #expect(throws: HomeScope.Error.symlinkTraversal) {
            try HomeScope(homeURL: link)
        }
    }

    @Test("unsafe home roots are rejected")
    func rejectsUnsafeHomeRoots() throws {
        let fixture = try HomeFixture()
        let regularFile = fixture.parent.appending(path: "not-a-home")
        try Data().write(to: regularFile)

        #expect(throws: HomeScope.Error.outsideHome) {
            try HomeScope(homeURL: URL(filePath: "/"))
        }
        #expect(throws: HomeScope.Error.outsideHome) {
            try HomeScope(homeURL: URL(filePath: "/Users"))
        }
        #expect(throws: HomeScope.Error.unavailable) {
            try HomeScope(homeURL: fixture.parent.appending(path: "missing-home"))
        }
        #expect(throws: HomeScope.Error.notDirectory) {
            try HomeScope(homeURL: regularFile)
        }
    }

    @Test("missing paths are harmless")
    func acceptsMissingPaths() throws {
        let fixture = try HomeFixture()
        let scope = try HomeScope(homeURL: fixture.home)
        let missing = try scope.url(for: "missing")

        try scope.removeItem(at: missing)

        #expect(try scope.children(of: missing).isEmpty)
    }

    @Test("normal directories are removed")
    func removesDirectory() throws {
        let fixture = try HomeFixture()
        let directory = fixture.home.appending(path: "Documents")
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        try Data("exam".utf8).write(to: directory.appending(path: "exam.txt"))
        let scope = try HomeScope(homeURL: fixture.home)

        try scope.removeItem(at: directory)

        #expect(FileManager.default.fileExists(atPath: directory.path) == false)
    }

    @Test("ensuring a directory replaces a symlink and applies its mode")
    func ensuresRealDirectory() throws {
        let fixture = try HomeFixture()
        let outsideFile = fixture.outside.appending(path: "keep.txt")
        try Data("keep".utf8).write(to: outsideFile)
        let publicDirectory = fixture.home.appending(path: "Public")
        try FileManager.default.createSymbolicLink(
            at: publicDirectory,
            withDestinationURL: fixture.outside
        )
        let scope = try HomeScope(homeURL: fixture.home)

        try scope.ensureDirectory(at: publicDirectory, permissions: 0o755)

        let values = try publicDirectory.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        let attributes = try FileManager.default.attributesOfItem(
            atPath: publicDirectory.path
        )
        #expect(values.isDirectory == true)
        #expect(values.isSymbolicLink == false)
        #expect(attributes[.posixPermissions] as? Int == 0o755)
        #expect(FileManager.default.fileExists(atPath: outsideFile.path))
    }

    @Test("emptying a directory removes only its direct contents")
    func emptiesDirectoryWithoutFollowingLinks() throws {
        let fixture = try HomeFixture()
        let desktop = fixture.home.appending(path: "Desktop")
        try FileManager.default.createDirectory(
            at: desktop,
            withIntermediateDirectories: false
        )
        try Data("exam".utf8).write(to: desktop.appending(path: "exam.txt"))
        try FileManager.default.createSymbolicLink(
            at: desktop.appending(path: "outside-link"),
            withDestinationURL: fixture.outside
        )
        let outsideFile = fixture.outside.appending(path: "keep.txt")
        try Data("keep".utf8).write(to: outsideFile)
        let scope = try HomeScope(homeURL: fixture.home)

        try scope.emptyDirectory(at: desktop)

        #expect(FileManager.default.fileExists(atPath: desktop.path))
        #expect(try scope.children(of: desktop).isEmpty)
        #expect(FileManager.default.fileExists(atPath: outsideFile.path))
    }
}

private final class HomeFixture {
    let parent: URL
    let home: URL
    let outside: URL

    init() throws {
        parent = FileManager.default.temporaryDirectory
            .appending(path: "WoodSweepTests-\(UUID().uuidString)")
        home = parent.appending(path: "home")
        outside = parent.appending(path: "outside")

        try FileManager.default.createDirectory(
            at: parent,
            withIntermediateDirectories: false
        )
        try FileManager.default.createDirectory(
            at: home,
            withIntermediateDirectories: false
        )
        try FileManager.default.createDirectory(
            at: outside,
            withIntermediateDirectories: false
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: parent)
    }
}
