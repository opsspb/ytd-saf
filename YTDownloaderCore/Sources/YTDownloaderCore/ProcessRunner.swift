import Darwin
import Foundation

public struct ProcessRunResult: Sendable {
    public let stdout: String
    public let stderr: String
    public let status: Int32
    public let timedOut: Bool
    public let cancelled: Bool

    public init(stdout: String, stderr: String, status: Int32, timedOut: Bool, cancelled: Bool = false) {
        self.stdout = stdout
        self.stderr = stderr
        self.status = status
        self.timedOut = timedOut
        self.cancelled = cancelled
    }
}

public enum ProcessRunner {
    /// Runs a process off the caller's concerns about pipe deadlocks.
    /// stdout/stderr are written to temp files. `timeout` kills the process.
    public static func run(
        executable: String,
        arguments: [String],
        timeout: TimeInterval = 15,
        cancellation: ProcessCancellation? = nil,
        onOutput: (@Sendable (String) -> Void)? = nil,
        onTick: (@Sendable () -> Void)? = nil
    ) throws -> ProcessRunResult {
        return try runToFiles(
            executable: executable,
            arguments: arguments,
            timeout: timeout,
            cancellation: cancellation,
            onOutput: onOutput,
            onTick: onTick
        )
    }

    private static func runToFiles(
        executable: String,
        arguments: [String],
        timeout: TimeInterval,
        cancellation: ProcessCancellation?,
        onOutput: (@Sendable (String) -> Void)?,
        onTick: (@Sendable () -> Void)?
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

        let stop = tailFiles([outURL, errURL], onOutput: onOutput, onTick: onTick)
        let outcome = try wait(for: process, timeout: timeout, cancellation: cancellation)
        stop()
        try? outHandle.close()
        try? errHandle.close()
        return ProcessRunResult(
            stdout: (try? String(contentsOf: outURL, encoding: .utf8)) ?? "",
            stderr: (try? String(contentsOf: errURL, encoding: .utf8)) ?? "",
            status: process.terminationStatus,
            timedOut: outcome == .timedOut,
            cancelled: outcome == .cancelled
        )
    }

    private static func tailFiles(
        _ urls: [URL],
        onOutput: (@Sendable (String) -> Void)?,
        onTick: (@Sendable () -> Void)?
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
                onTick?()
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

    private enum WaitOutcome {
        case finished
        case timedOut
        case cancelled
    }

    private static func wait(
        for process: Process,
        timeout: TimeInterval,
        cancellation: ProcessCancellation?
    ) throws -> WaitOutcome {
        if cancellation?.isCancelled == true {
            return .cancelled
        }
        let group = DispatchGroup()
        group.enter()
        process.terminationHandler = { _ in group.leave() }
        try process.run()
        let pid = process.processIdentifier
        setpgid(pid, pid)
        cancellation?.attach(pid: pid)

        let deadline = Date().addingTimeInterval(timeout)
        while true {
            if cancellation?.isCancelled == true {
                ProcessCancellation.killTree(pid)
                _ = group.wait(timeout: .now() + 1)
                return .cancelled
            }
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 {
                if process.isRunning {
                    ProcessCancellation.killTree(pid)
                    _ = group.wait(timeout: .now() + 1)
                }
                return .timedOut
            }
            let slice = min(remaining, 0.2)
            if group.wait(timeout: .now() + slice) == .success {
                return cancellation?.isCancelled == true ? .cancelled : .finished
            }
        }
    }
}
