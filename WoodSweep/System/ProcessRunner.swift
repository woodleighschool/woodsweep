import Foundation

nonisolated struct ProcessResult: Equatable, Sendable {
    let terminationStatus: Int32
    let standardOutput: String
    let standardError: String
}

nonisolated protocol ProcessRunning: Sendable {
    func run(
        executable: URL,
        arguments: [String]
    ) async throws -> ProcessResult
}

nonisolated struct ProcessRunner: ProcessRunning {
    private static let captureLimit = 256 * 1024
    private static let readSize = 64 * 1024

    func run(
        executable: URL,
        arguments: [String]
    ) async throws -> ProcessResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try process.run()

            let outputTask = Task.detached {
                try Self.drain(standardOutput.fileHandleForReading)
            }
            let errorTask = Task.detached {
                try Self.drain(standardError.fileHandleForReading)
            }
            let terminationTask = Task.detached {
                process.waitUntilExit()
                return process.terminationStatus
            }

            if Task.isCancelled, process.isRunning {
                process.terminate()
            }

            let terminationStatus = await terminationTask.value
            let output = try await outputTask.value
            let error = try await errorTask.value
            try Task.checkCancellation()

            return ProcessResult(
                terminationStatus: terminationStatus,
                standardOutput: String(decoding: output, as: UTF8.self),
                standardError: String(decoding: error, as: UTF8.self)
            )
        } onCancel: {
            if process.isRunning {
                process.terminate()
            }
        }
    }

    private static func drain(_ handle: FileHandle) throws -> Data {
        var captured = Data()

        while let chunk = try handle.read(upToCount: readSize),
              chunk.isEmpty == false
        {
            if chunk.count >= captureLimit {
                captured = Data(chunk.suffix(captureLimit))
                continue
            }

            captured.append(chunk)
            if captured.count > captureLimit {
                captured.removeFirst(captured.count - captureLimit)
            }
        }

        return captured
    }
}
