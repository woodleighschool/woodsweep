import Foundation
import Testing
@testable import WoodSweep

@Suite("Home reconciliation")
struct HomeReconcilerTests {
    @Test("restores the documented home shape")
    func restoresDocumentedShape() async throws {
        let fixture = try HomeReconciliationFixture()
        try fixture.populateDocumentedShape()
        let recorder = OperationRecorder()

        try await HomeReconciler().reconcile(fixture.scope) { operation in
            await recorder.record(operation)
        }

        try expectStandardDirectories(in: fixture.home)
        try expectDropBox(in: fixture.home)
        #expect(
            try topLevelNames(in: fixture.home) == Set([
                ".CFUserTextEncoding",
                ".Trash",
                "Desktop",
                "Documents",
                "Downloads",
                "Library",
                "Movies",
                "Music",
                "Pictures",
                "Public",
            ])
        )
        #expect(
            FileManager.default.fileExists(
                atPath: fixture.home.appending(path: "Library/keep.txt").path
            )
        )
        #expect(
            FileManager.default.fileExists(
                atPath: fixture.home.appending(path: ".CFUserTextEncoding").path
            )
        )
        #expect(
            FileManager.default.fileExists(
                atPath: fixture.outside.appending(path: "keep.txt").path
            )
        )
        #expect(
            await recorder.values == [
                .clearing("Desktop"),
                .clearing("Documents"),
                .clearing("Downloads"),
                .clearing("Movies"),
                .clearing("Music"),
                .clearing("Pictures"),
                .clearing("Public"),
                .clearing(".Trash"),
                .removing(".zsh_history"),
                .removing("outside-link"),
                .removing("unexpected"),
            ]
        )
    }

    @Test("replaces unsafe standard entries without creating preserved files")
    func replacesStandardEntries() async throws {
        let fixture = try HomeReconciliationFixture()
        try Data("not a directory".utf8).write(
            to: fixture.home.appending(path: "Downloads")
        )
        try FileManager.default.createSymbolicLink(
            at: fixture.home.appending(path: "Public"),
            withDestinationURL: fixture.outside
        )
        try Data("remove".utf8).write(
            to: fixture.home.appending(path: ".zsh_history")
        )
        try Data("keep".utf8).write(
            to: fixture.outside.appending(path: "keep.txt")
        )

        try await HomeReconciler().reconcile(fixture.scope) { _ in }

        try expectStandardDirectories(in: fixture.home)
        try expectDropBox(in: fixture.home)
        #expect(
            try topLevelNames(in: fixture.home)
                == Set(standardDirectoryPermissions.map(\.name))
        )
        #expect(
            FileManager.default.fileExists(
                atPath: fixture.home.appending(path: ".CFUserTextEncoding").path
            ) == false
        )
        #expect(
            FileManager.default.fileExists(
                atPath: fixture.outside.appending(path: "keep.txt").path
            )
        )
    }
}

private let standardDirectoryPermissions: [(name: String, permissions: Int)] = [
    ("Desktop", 0o700),
    ("Documents", 0o700),
    ("Downloads", 0o700),
    ("Movies", 0o700),
    ("Music", 0o700),
    ("Pictures", 0o700),
    ("Public", 0o755),
    (".Trash", 0o700),
]

private func expectStandardDirectories(in home: URL) throws {
    for directory in standardDirectoryPermissions {
        let url = home.appending(path: directory.name)
        let values = try url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
        ])
        let attributes = try FileManager.default.attributesOfItem(
            atPath: url.path
        )

        #expect(values.isDirectory == true)
        #expect(values.isSymbolicLink == false)
        let expectedContents = directory.name == "Public" ? ["Drop Box"] : []
        #expect(
            try FileManager.default.contentsOfDirectory(atPath: url.path)
                == expectedContents
        )
        #expect(
            attributes[.posixPermissions] as? Int == directory.permissions
        )
    }
}

private func expectDropBox(in home: URL) throws {
    let dropBox = home.appending(path: "Public/Drop Box")
    let values = try dropBox.resourceValues(forKeys: [
        .isDirectoryKey,
        .isSymbolicLinkKey,
    ])
    let attributes = try FileManager.default.attributesOfItem(
        atPath: dropBox.path
    )

    #expect(values.isDirectory == true)
    #expect(values.isSymbolicLink == false)
    #expect(
        try FileManager.default.contentsOfDirectory(atPath: dropBox.path)
            .isEmpty
    )
    #expect(attributes[.posixPermissions] as? Int == 0o733)
}

private func topLevelNames(in home: URL) throws -> Set<String> {
    try Set(FileManager.default.contentsOfDirectory(atPath: home.path))
}

private actor OperationRecorder {
    private(set) var values: [HomeResetOperation] = []

    func record(_ operation: HomeResetOperation) {
        values.append(operation)
    }
}

private final class HomeReconciliationFixture {
    let parent: URL
    let home: URL
    let outside: URL
    let scope: HomeScope

    init() throws {
        parent = FileManager.default.temporaryDirectory
            .appending(path: "HomeReconcilerTests-\(UUID().uuidString)")
        home = parent.appending(path: "home")
        outside = parent.appending(path: "outside")

        try FileManager.default.createDirectory(
            at: home,
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: outside,
            withIntermediateDirectories: false
        )
        scope = try HomeScope(homeURL: home)
    }

    deinit {
        try? FileManager.default.removeItem(at: parent)
    }

    func populateDocumentedShape() throws {
        let contents = [
            ("Desktop", "student.txt"),
            ("Documents", "exam.docx"),
            ("Downloads", "archive.zip"),
            ("Movies", "movie.mov"),
            ("Music", "audio.m4a"),
            ("Pictures", "image.png"),
            ("Public", "shared.txt"),
            (".Trash", "deleted.txt"),
        ]
        for (directory, file) in contents {
            let directoryURL = home.appending(path: directory)
            try FileManager.default.createDirectory(
                at: directoryURL,
                withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o777]
            )
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o777],
                ofItemAtPath: directoryURL.path
            )
            try Data("remove".utf8).write(
                to: directoryURL.appending(path: file)
            )
        }

        let dropBox = home.appending(path: "Public/Drop Box")
        try FileManager.default.createDirectory(
            at: dropBox,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o777]
        )
        try Data("remove".utf8).write(
            to: dropBox.appending(path: "deleted.txt")
        )

        let library = home.appending(path: "Library")
        try FileManager.default.createDirectory(
            at: library,
            withIntermediateDirectories: false
        )
        try Data("keep".utf8).write(to: library.appending(path: "keep.txt"))
        try Data("keep".utf8).write(
            to: home.appending(path: ".CFUserTextEncoding")
        )
        try Data("remove".utf8).write(
            to: home.appending(path: ".zsh_history")
        )

        let unexpected = home.appending(path: "unexpected")
        try FileManager.default.createDirectory(
            at: unexpected,
            withIntermediateDirectories: false
        )
        try Data("remove".utf8).write(
            to: unexpected.appending(path: "nested.txt")
        )
        try Data("keep".utf8).write(
            to: outside.appending(path: "keep.txt")
        )
        try FileManager.default.createSymbolicLink(
            at: home.appending(path: "outside-link"),
            withDestinationURL: outside
        )
    }
}
