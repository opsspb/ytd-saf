import Darwin
import Foundation

/// Cancels a process and its descendants (yt-dlp → aria2c / ffmpeg).
public final class ProcessCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelledFlag = false
    private var pids: [pid_t] = []

    public init() {}

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelledFlag
    }

    func attach(pid: pid_t) {
        lock.lock()
        pids.append(pid)
        let shouldKill = cancelledFlag
        lock.unlock()
        if shouldKill {
            Self.killTree(pid)
        }
    }

    public func cancel() {
        lock.lock()
        cancelledFlag = true
        let copy = pids
        lock.unlock()
        for pid in copy {
            Self.killTree(pid)
        }
    }

    public static func killTree(_ root: pid_t) {
        guard root > 1 else { return }
        var seen = Set<pid_t>()
        var stack = [root]
        var all: [pid_t] = []
        while let pid = stack.popLast() {
            if seen.contains(pid) { continue }
            seen.insert(pid)
            all.append(pid)
            stack.append(contentsOf: children(of: pid))
        }
        for pid in all {
            kill(-pid, SIGTERM)
            kill(pid, SIGTERM)
        }
        usleep(200_000)
        for pid in all {
            kill(-pid, SIGKILL)
            kill(pid, SIGKILL)
        }
    }

    private static func children(of pid: pid_t) -> [pid_t] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
        process.arguments = ["-P", "\(pid)"]
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return []
        }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        let text = String(data: data, encoding: .utf8) ?? ""
        return text.split(whereSeparator: \.isNewline).compactMap { pid_t($0) }
    }
}
