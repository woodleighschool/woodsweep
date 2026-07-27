nonisolated enum OfficeResetRule: Equatable, Sendable {
    case removeItem(String)
    case removeFiles(directory: String, extensions: Set<String>)
    case removeFilesWithPrefix(directory: String, prefix: String)

    var relativePath: String {
        switch self {
        case let .removeItem(path):
            path
        case let .removeFiles(directory, _):
            directory
        case let .removeFilesWithPrefix(directory, _):
            directory
        }
    }
}

/// Paths based on https://github.com/dan-snelson/Microsoft-365-Reset
nonisolated enum OfficeResetPolicy {
    static func rules(
        for application: OfficeApplication
    ) -> [OfficeResetRule] {
        applicationRules(for: application) + sharedRules
    }

    private static func applicationRules(
        for application: OfficeApplication
    ) -> [OfficeResetRule] {
        switch application {
        case .word:
            [
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
            ]
        case .excel:
            [
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
            ]
        case .powerPoint:
            [
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
            ]
        }
    }

    private static let sharedRules: [OfficeResetRule] = [
        .removeItem(
            "Library/Group Containers/UBF8T346G9.Office/FontCache"
        ),
        .removeItem(
            "Library/Group Containers/UBF8T346G9.Office/ComRPC32"
        ),
        .removeItem(
            "Library/Group Containers/UBF8T346G9.Office/TemporaryItems"
        ),
        .removeFilesWithPrefix(
            directory: "Library/Group Containers/UBF8T346G9.Office",
            prefix: "Microsoft Office ACL"
        ),
    ]
}
