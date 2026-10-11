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
        return try runToFiles(
            executable: executable,
            arguments: arguments,
            timeout: timeout,
            onOutput: onOutput
        )
    }

    private static func runToFiles(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        onOutput: (@Sendable (String) -> Void)?
    ) throws -> ProcessRunResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        var environment = ProcessInfo.processInfo.environment
        environment["PYTHONUNBUFFERED"] = "1"
        process.environment = environment

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

        let stop = tailFiles([outURL, errURL], onOutput: onOutput)
        let timedOut = try wait(for: process, timeout: timeout)
        stop()
        try? outHandle.close()
        try? errHandle.close()
        return ProcessRunResult(
            stdout: (try? String(contentsOf: outURL, encoding: .utf8)) ?? "",
            stderr: (try? String(contentsOf: errURL, encoding: .utf8)) ?? "",
            status: process.terminationStatus,
            timedOut: timedOut
        )
    }

    private static func tailFiles(
        _ urls: [URL],
        onOutput: (@Sendable (String) -> Void)?
    ) -> () -> Void {
        guard let onOutput else { return {} }
        let lock = NSLock()
        var offsets = Array(repeating: 0, count: urls.count)
        var running = true
        let queue = DispatchQueue(label: "ytd.process-tail")
        func tick() {
            for (index, url) in urls.enumerated() {
                guard let handle = try? FileHandle(forReadingFrom: url) else { continue }
                defer { try? handle.close() }
                lock.lock()
                let offset = offsets[index]
                lock.unlock()
                _ = try? handle.seek(toOffset: UInt64(offset))
                let data = handle.readDataToEndOfFile()
                guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { continue }
                lock.lock()
                offsets[index] = offset + data.count
                lock.unlock()
                chunk.split(whereSeparator: \.isNewline).forEach { onOutput(String($0)) }
            }
        }
        queue.async {
            while true {
                lock.lock()
                let keep = running
                lock.unlock()
                if !keep { break }
                tick()
                Thread.sleep(forTimeInterval: 0.2)
            }
            tick()
        }
        return {
            lock.lock()
            running = false
            lock.unlock()
            queue.sync {}
        }
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
