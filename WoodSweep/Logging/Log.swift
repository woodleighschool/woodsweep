import OSLog

nonisolated enum Log {
    private static let subsystem = "au.edu.vic.woodleigh.WoodSweep"

    static let configuration = Logger(
        subsystem: subsystem,
        category: "configuration"
    )
    static let kopia = Logger(
        subsystem: subsystem,
        category: "kopia"
    )
}
