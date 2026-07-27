import Foundation
import Testing
@testable import WoodSweep

@Suite("Office reset policy")
struct OfficeResetPolicyTests {
    @Test("the reset policy stays inside its reviewed user scope")
    func excludesForbiddenScope() {
        let forbiddenFragments = [
            "Licenses",
            "oneauth",
            "RMS-XPCService",
            "MicrosoftRegistrationDB.reg",
            "mip_policy",
            "com.microsoft.office.plist",
            "com.microsoft.shared.plist",
            "Keychains",
            "AutoUpdate",
            "OneDrive",
            "Teams",
            "Outlook",
            "OneNote",
        ]

        for application in OfficeApplication.allCases {
            for rule in OfficeResetPolicy.rules(for: application) {
                #expect(rule.relativePath.hasPrefix("/") == false)
                #expect(
                    rule.relativePath == "Library"
                        || rule.relativePath.hasPrefix("Library/")
                )
                #expect(
                    rule.relativePath.split(separator: "/")
                        .contains("..") == false
                )
                for fragment in forbiddenFragments {
                    #expect(
                        rule.relativePath.localizedCaseInsensitiveContains(
                            fragment
                        ) == false
                    )
                }
            }
        }
    }

    @Test(
        "each application includes its preferences, container, scripts, recent list, startup, and templates"
    )
    func includesApplicationResetSurfaces() {
        let sharedRules = [
            OfficeResetRule.removeItem(
                "Library/Group Containers/UBF8T346G9.Office/FontCache"
            ),
            .removeItem(
                "Library/Group Containers/UBF8T346G9.Office/ComRPC32"
            ),
            .removeItem(
                "Library/Group Containers/UBF8T346G9.Office/TemporaryItems"
            ),
            .removeFilesWithPrefix(
                directory:
                "Library/Group Containers/UBF8T346G9.Office",
                prefix: "Microsoft Office ACL"
            ),
        ]

        assertPolicy(
            for: .word,
            startsWith: [
                .removeItem(
                    "Library/Preferences/com.microsoft.Word.plist"
                ),
                .removeItem("Library/Containers/com.microsoft.Word"),
                .removeItem(
                    "Library/Application Scripts/com.microsoft.Word"
                ),
                .removeItem(
                    "Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/com.microsoft.Word.sfl3"
                ),
                .removeItem(
                    "Library/Group Containers/UBF8T346G9.Office/User Content.localized/Startup.localized/Word"
                ),
                .removeFiles(
                    directory:
                    "Library/Group Containers/UBF8T346G9.Office/User Content.localized/Templates.localized",
                    extensions: ["dot", "dotx", "dotm"]
                ),
            ],
            sharedRules: sharedRules
        )
        assertPolicy(
            for: .excel,
            startsWith: [
                .removeItem(
                    "Library/Preferences/com.microsoft.Excel.plist"
                ),
                .removeItem("Library/Containers/com.microsoft.Excel"),
                .removeItem(
                    "Library/Application Scripts/com.microsoft.Excel"
                ),
                .removeItem(
                    "Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/com.microsoft.Excel.sfl3"
                ),
                .removeItem(
                    "Library/Group Containers/UBF8T346G9.Office/User Content.localized/Startup.localized/Excel"
                ),
                .removeFiles(
                    directory:
                    "Library/Group Containers/UBF8T346G9.Office/User Content.localized/Templates.localized",
                    extensions: ["xlt", "xltx", "xltm"]
                ),
            ],
            sharedRules: sharedRules
        )
        assertPolicy(
            for: .powerPoint,
            startsWith: [
                .removeItem(
                    "Library/Preferences/com.microsoft.Powerpoint.plist"
                ),
                .removeItem(
                    "Library/Containers/com.microsoft.Powerpoint"
                ),
                .removeItem(
                    "Library/Application Scripts/com.microsoft.Powerpoint"
                ),
                .removeItem(
                    "Library/Application Support/com.apple.sharedfilelist/com.apple.LSSharedFileList.ApplicationRecentDocuments/com.microsoft.Powerpoint.sfl3"
                ),
                .removeItem(
                    "Library/Group Containers/UBF8T346G9.Office/User Content.localized/Startup.localized/PowerPoint"
                ),
                .removeFiles(
                    directory:
                    "Library/Group Containers/UBF8T346G9.Office/User Content.localized/Templates.localized",
                    extensions: ["pot", "potx", "potm"]
                ),
                .removeFiles(
                    directory:
                    "Library/Group Containers/UBF8T346G9.Office/User Content.localized/Add-Ins",
                    extensions: ["ppam"]
                ),
                .removeItem(
                    "Library/Group Containers/UBF8T346G9.Office/User Content.localized/Themes"
                ),
            ],
            sharedRules: sharedRules
        )
    }

    @Test("file rules remove only direct matching files and symlink leaves")
    func removesOnlyAllowedFileTypes() async throws {
        let fixture = try OfficeResetFixture()
        let templates = try fixture.directory(
            "Library/Group Containers/UBF8T346G9.Office/User Content.localized/Templates.localized"
        )
        let nested = try fixture.directory(
            "Library/Group Containers/UBF8T346G9.Office/User Content.localized/Templates.localized/Nested"
        )
        let matchingFile = templates.appending(path: "Exam.DOTX")
        let nonmatchingFile = templates.appending(path: "keep.docx")
        let nestedMatchingFile = nested.appending(path: "keep.dotm")
        let matchingDirectory = try fixture.directory(
            "Library/Group Containers/UBF8T346G9.Office/User Content.localized/Templates.localized/keep.dot"
        )
        let outsideFile = fixture.outside.appending(path: "keep.dot")
        let matchingLink = templates.appending(path: "linked.dotm")
        try Data("remove".utf8).write(to: matchingFile)
        try Data("keep".utf8).write(to: nonmatchingFile)
        try Data("keep".utf8).write(to: nestedMatchingFile)
        try Data("keep".utf8).write(to: outsideFile)
        try FileManager.default.createSymbolicLink(
            at: matchingLink,
            withDestinationURL: outsideFile
        )

        try await OfficeResetter().reset(.word, in: fixture.scope)

        #expect(FileManager.default.fileExists(atPath: matchingFile.path) == false)
        #expect(FileManager.default.fileExists(atPath: matchingLink.path) == false)
        #expect(FileManager.default.fileExists(atPath: nonmatchingFile.path))
        #expect(FileManager.default.fileExists(atPath: nestedMatchingFile.path))
        #expect(FileManager.default.fileExists(atPath: matchingDirectory.path))
        #expect(FileManager.default.fileExists(atPath: outsideFile.path))
    }

    @Test("prefix rules are exact and case-sensitive")
    func removesOnlyExactPrefixMatches() async throws {
        let fixture = try OfficeResetFixture()
        let groupContainer = try fixture.directory(
            "Library/Group Containers/UBF8T346G9.Office"
        )
        let matchingFile = groupContainer.appending(
            path: "Microsoft Office ACL Cache"
        )
        let matchingDirectory = try fixture.directory(
            "Library/Group Containers/UBF8T346G9.Office/Microsoft Office ACL Folder"
        )
        let lowercaseFile = groupContainer.appending(
            path: "microsoft Office ACL keep"
        )
        let embeddedFile = groupContainer.appending(
            path: "keep Microsoft Office ACL"
        )
        try Data().write(to: matchingFile)
        try Data().write(to: lowercaseFile)
        try Data().write(to: embeddedFile)

        try await OfficeResetter().reset(.excel, in: fixture.scope)

        #expect(FileManager.default.fileExists(atPath: matchingFile.path) == false)
        #expect(
            FileManager.default.fileExists(atPath: matchingDirectory.path)
                == false
        )
        #expect(FileManager.default.fileExists(atPath: lowercaseFile.path))
        #expect(FileManager.default.fileExists(atPath: embeddedFile.path))
    }

    @Test("missing reset paths succeed")
    func acceptsMissingPaths() async throws {
        let fixture = try OfficeResetFixture()

        try await OfficeResetter().reset(.powerPoint, in: fixture.scope)
    }

    @Test("reset stops at its first filesystem error")
    func stopsAtFirstError() async throws {
        let fixture = try OfficeResetFixture()
        _ = try fixture.directory("Library")
        let preferences = fixture.home.appending(path: "Library/Preferences")
        try FileManager.default.createSymbolicLink(
            at: preferences,
            withDestinationURL: fixture.outside
        )
        let laterCache = try fixture.directory(
            "Library/Group Containers/UBF8T346G9.Office/FontCache"
        )
        try Data().write(to: laterCache.appending(path: "keep"))

        await #expect(throws: HomeScope.Error.symlinkTraversal) {
            try await OfficeResetter().reset(.word, in: fixture.scope)
        }
        #expect(FileManager.default.fileExists(atPath: laterCache.path))
    }

    private func assertPolicy(
        for application: OfficeApplication,
        startsWith expectedApplicationRules: [OfficeResetRule],
        sharedRules: [OfficeResetRule]
    ) {
        #expect(
            OfficeResetPolicy.rules(for: application)
                == expectedApplicationRules + sharedRules
        )
    }
}

private final class OfficeResetFixture {
    let parent: URL
    let home: URL
    let outside: URL
    let scope: HomeScope

    init() throws {
        parent = FileManager.default.temporaryDirectory
            .appending(path: "OfficeResetTests-\(UUID().uuidString)")
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

    func directory(_ relativePath: String) throws -> URL {
        let directory = home.appending(path: relativePath)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
    }
}
