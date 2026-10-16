import Darwin
import Foundation

nonisolated struct ProcessResult: Equatable, Sendable {
    let terminationStatus: Int32
    let standardOutput: String
    let standardError: String
}

nonisolated protocol ProcessRunning: Sendable {
    func run(
        executable: URL,
        arguments: [String],
        timeout: Duration
    ) async throws -> ProcessResult
}

nonisolated struct ProcessRunner: ProcessRunning {
    enum Error: Swift.Error, LocalizedError {
        case timedOut

        var errorDescription: String? {
            "The process exceeded its time limit."
        }
    }

    private static let captureLimit = 256 * 1024
    private static let readSize = 64 * 1024

    func run(
        executable: URL,
        arguments: [String],
        timeout: Duration = .seconds(30)
    ) async throws -> ProcessResult {
        let process = Process()
        let standardOutput = Pipe()
        let standardError = Pipe()
        process.executableURL = executable
        process.arguments = arguments
        process.standardOutput = standardOutput
        process.standardError = standardError
        let (termination, continuation) = AsyncStream<Int32>.makeStream(bufferingPolicy: .bufferingNewest(1))
        process.terminationHandler = { process in
            continuation.yield(process.terminationStatus)
            continuation.finish()
        }
        defer {
            process.terminationHandler = nil
            continuation.finish()
        }

        return try await withTaskCancellationHandler {
            try Task.checkCancellation()
            try process.run()

            let timeoutTask = Task {
                do {
                    try await Task.sleep(for: timeout)
                } catch {
                    return false
                }
                guard process.isRunning else {
                    return false
                }
                process.terminate()
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled == false, process.isRunning {
                    kill(process.processIdentifier, SIGKILL)
                }
                return true
            }
            defer { timeoutTask.cancel() }

            async let output = Self.blocking {
                try Self.drain(standardOutput.fileHandleForReading)
            }
            async let error = Self.blocking {
                try Self.drain(standardError.fileHandleForReading)
            }

            if Task.isCancelled, process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }

            var iterator = termination.makeAsyncIterator()
            guard let terminationStatus = await iterator.next() else {
                throw CancellationError()
            }
            timeoutTask.cancel()
            let timedOut = await timeoutTask.value
            let (standardOutput, standardError) = try await (output, error)
            try Task.checkCancellation()
            if timedOut {
                throw Error.timedOut
            }

            return ProcessResult(
                terminationStatus: terminationStatus,
                standardOutput: String(decoding: standardOutput, as: UTF8.self),
                standardError: String(decoding: standardError, as: UTF8.self)
            )
        } onCancel: {
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
    }

    /// Pipe reads must not occupy Swift's cooperative worker threads.
    private static func blocking<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                continuation.resume(with: Result(catching: operation))
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
