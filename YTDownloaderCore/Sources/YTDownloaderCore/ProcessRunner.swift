import Foundation

public struct ProcessRunResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let status: Int32
    public let timedOut: Bool
}

public enum ProcessRunner {
    /// Runs a process off the caller's concerns about pipe deadlocks.
    /// stdout/stderr are written to temp files. `timeout` kills the process.
    public static func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval = 15,
        onOutput: (@Sendable (String) -> Void)? = nil
    ) throws -> ProcessRunResult {
        if let onOutput {
            return try runStreaming(executable: executable, arguments: arguments, timeout: timeout, onOutput: onOutput)
        }
        return try runToFiles(executable: executable, arguments: arguments, timeout: timeout)
    }

    private static func runToFiles(
        executable: String,
        arguments: [String],
        timeout: TimeInterval
    ) throws -> ProcessRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outURL = FileManager.default.temporaryDirectory.appendingPathComponent("ytd-out-\(UUID().uuidString)")
        let errURL = FileManager.default.temporaryDirectory.appendingPathComponent("ytd-err-\(UUID().uuidString)")
        FileManager.default.createFile(atPath: outURL.path, contents: nil)
        FileManager.default.createFile(atPath: errURL.path, contents: nil)
        defer {
            try? FileManager.default.removeItem(at: outURL)
            try? FileManager.default.removeItem(at: errURL)
        }

        let outHandle = try FileHandle(forWritingTo: outURL)
        let errHandle = try FileHandle(forWritingTo: errURL)
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outHandle
        process.standardError = errHandle

        let timedOut = try wait(for: process, timeout: timeout)
        try? outHandle.close()
        try? errHandle.close()
        return ProcessRunResult(
            stdout: (try? String(contentsOf: outURL, encoding: .utf8)) ?? "",
            stderr: (try? String(contentsOf: errURL, encoding: .utf8)) ?? "",
            status: process.terminationStatus,
            timedOut: timedOut
        )
    }

    private static func runStreaming(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        onOutput: @escaping @Sendable (String) -> Void
    ) throws -> ProcessRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments

        let outPipe = Pipe()
        let errPipe = Pipe()
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = outPipe
        process.standardError = errPipe

        let lock = NSLock()
        var stdout = ""
        var stderr = ""

        let consume: (FileHandle, Bool) -> Void = { handle, isErr in
            while true {
                let data = handle.availableData
                if data.isEmpty { break }
                guard let chunk = String(data: data, encoding: .utf8), !chunk.isEmpty else { continue }
                lock.lock()
                if isErr { stderr += chunk } else { stdout += chunk }
                lock.unlock()
                chunk.split(whereSeparator: \.isNewline).forEach { onOutput(String($0)) }
            }
        }

        outPipe.fileHandleForReading.readabilityHandler = { handle in
            consume(handle, false)
        }
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            consume(handle, true)
        }

        let timedOut = try wait(for: process, timeout: timeout)
        outPipe.fileHandleForReading.readabilityHandler = nil
        errPipe.fileHandleForReading.readabilityHandler = nil
        consume(outPipe.fileHandleForReading, false)
        consume(errPipe.fileHandleForReading, true)

        lock.lock()
        let out = stdout
        let err = stderr
        lock.unlock()
        return ProcessRunResult(stdout: out, stderr: err, status: process.terminationStatus, timedOut: timedOut)
    }

    private static func wait(for process: Process, timeout: TimeInterval) throws -> Bool {
        let group = DispatchGroup()
        group.enter()
        process.terminationHandler = { _ in group.leave() }
        try process.run()
        let result = group.wait(timeout: .now() + timeout)
        if result == .timedOut {
            if process.isRunning {
                process.terminate()
                _ = group.wait(timeout: .now() + 1)
                if process.isRunning {
                    process.interrupt()
                    kill(process.processIdentifier, SIGKILL)
                }
            }
            return true
        }
        return false
    }
}
