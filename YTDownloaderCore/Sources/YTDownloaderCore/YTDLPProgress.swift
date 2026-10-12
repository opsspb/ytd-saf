import Foundation

public enum DownloadStage: String, Codable, Sendable, Equatable {
    case fetching
    case formatChosen
    case downloadingVideo
    case downloadingAudio
    case merging
    case retrying
    case completed
    case failed
    case cancelled
}

public struct TransferProgress: Equatable, Sendable {
    public var fraction: Double?
    public var speed: String?
    public var eta: String?
    public var sizeText: String?
    public var expectedBytes: Int64?
    public var downloadedBytes: Int64?
    public var stream: StreamKind

    public enum StreamKind: String, Sendable, Equatable {
        case video
        case audio
        case unknown
    }

    public init(
        fraction: Double? = nil,
        speed: String? = nil,
        eta: String? = nil,
        sizeText: String? = nil,
        expectedBytes: Int64? = nil,
        downloadedBytes: Int64? = nil,
        stream: StreamKind = .unknown
    ) {
        self.fraction = fraction
        self.speed = speed
        self.eta = eta
        self.sizeText = sizeText
        self.expectedBytes = expectedBytes
        self.downloadedBytes = downloadedBytes
        self.stream = stream
    }
}

/// Tracks per-stream monotonic progress and stage transitions from yt-dlp / aria2c output.
public struct DownloadProgressSession: Equatable, Sendable {
    public var stream: TransferProgress.StreamKind = .unknown
    public var fraction: Double = 0

    public init(stream: TransferProgress.StreamKind = .unknown, fraction: Double = 0) {
        self.stream = stream
        self.fraction = fraction
    }

    /// Events to emit for one stdout/stderr line (completed prior stream, updates, merge-ready 100%).
    public mutating func events(for line: String) -> (transfers: [TransferProgress], merging: Bool) {
        var transfers: [TransferProgress] = []
        if let kind = YTDLPProgress.streamKind(fromDestination: line), kind != .unknown {
            if let done = completeStreamIfNeeded(switchingTo: kind) {
                transfers.append(done)
            }
            if stream != kind {
                stream = kind
                fraction = 0
                transfers.append(TransferProgress(fraction: 0, stream: kind))
            }
        }
        if var transfer = YTDLPProgress.parseTransfer(line) {
            if transfer.stream != .unknown, transfer.stream != stream {
                if let done = completeStreamIfNeeded(switchingTo: transfer.stream) {
                    transfers.append(done)
                }
                stream = transfer.stream
                fraction = 0
            } else if transfer.stream == .unknown {
                transfer.stream = stream
            }
            if let value = transfer.fraction {
                fraction = max(fraction, min(max(value, 0), 1))
            }
            transfer.fraction = fraction
            transfer.stream = stream == .unknown ? transfer.stream : stream
            transfers.append(transfer)
        }
        let merging = YTDLPProgress.isMergeLine(line)
        if merging, let done = finishCurrentStream() {
            transfers.append(done)
        }
        return (transfers, merging)
    }

    public mutating func finishCurrentStream() -> TransferProgress? {
        guard stream != .unknown else { return nil }
        if fraction >= 1 { return nil }
        fraction = 1
        return TransferProgress(fraction: 1, stream: stream)
    }

    public mutating func noteTransfer(_ transfer: TransferProgress) -> TransferProgress {
        var updated = transfer
        if updated.stream != .unknown, updated.stream != stream {
            stream = updated.stream
            fraction = 0
        } else if updated.stream == .unknown {
            updated.stream = stream
        }
        if let value = updated.fraction {
            fraction = max(fraction, min(max(value, 0), 1))
        }
        updated.fraction = fraction
        updated.stream = stream == .unknown ? updated.stream : stream
        return updated
    }

    private mutating func completeStreamIfNeeded(switchingTo kind: TransferProgress.StreamKind) -> TransferProgress? {
        guard stream != .unknown, stream != kind, fraction < 1 else { return nil }
        fraction = 1
        return TransferProgress(fraction: 1, stream: stream)
    }
}

public enum YTDLPProgress {
    public static let progPrefix = "YTD_PROG:"

    /// yt-dlp `--progress-template` value. Leading `download:` selects the
    /// download channel; the emitted line starts with `YTD_PROG:`.
    public static func progressTemplate() -> String {
        "download:\(progPrefix)%(progress._percent_str)s|%(progress.downloaded_bytes)s|%(progress.total_bytes,progress.total_bytes_estimate)s|%(progress.speed)s|%(progress.eta)s|%(progress.filename)s"
    }

    public static var progressCLIArgs: [String] {
        [
            "--newline",
            "--progress",
            "--progress-delta", "0.2",
            "--progress-template", progressTemplate()
        ]
    }

    /// Parses yt-dlp `--newline` / `--progress-template` lines into 0...1.
    public static func parse(_ line: String) -> Double? {
        parseTransfer(line)?.fraction
    }

    public static func parseTransfer(_ line: String) -> TransferProgress? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let machine = parseMachine(trimmed) {
            return machine
        }
        if let aria = parseAria2(trimmed) {
            return aria
        }

        let patterns = [
            #"download:\s*([0-9]+(?:\.[0-9]+)?)\s*%"#,
            #"\[download\]\s+([0-9]+(?:\.[0-9]+)?)\s*% of\s+(\S+)\s+at\s+(\S+)\s+ETA\s+(\S+)"#,
            #"\[download\]\s+([0-9]+(?:\.[0-9]+)?)\s*%"#,
            #"^\s*([0-9]+(?:\.[0-9]+)?)\s*%\s*$"#
        ]
        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)
            guard let match = regex.firstMatch(in: trimmed, range: range),
                  match.numberOfRanges > 1,
                  let capture = Range(match.range(at: 1), in: trimmed),
                  let percent = Double(trimmed[capture]) else {
                continue
            }
            var info = TransferProgress(fraction: min(max(percent / 100.0, 0), 1))
            if index == 1, match.numberOfRanges >= 5 {
                if let size = Range(match.range(at: 2), in: trimmed) { info.sizeText = String(trimmed[size]) }
                if let speed = Range(match.range(at: 3), in: trimmed) { info.speed = String(trimmed[speed]) }
                if let eta = Range(match.range(at: 4), in: trimmed) { info.eta = String(trimmed[eta]) }
            }
            return info
        }
        return nil
    }

    /// `YTD_PROG: 12.3%|downloaded|total|speed|eta|filename`
    public static func parseMachine(_ line: String) -> TransferProgress? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix(progPrefix) else { return nil }
        let payload = String(trimmed.dropFirst(progPrefix.count))
        let parts = payload.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
        guard let percentPart = parts.first else { return nil }
        let percentText = percentPart.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "%", with: "")
        guard let percent = Double(percentText) else { return nil }

        var info = TransferProgress(fraction: min(max(percent / 100.0, 0), 1))
        if parts.count > 1, let downloaded = Int64(parts[1]), downloaded >= 0 {
            info.downloadedBytes = downloaded
        }
        if parts.count > 2 {
            let totalText = parts[2]
            if totalText != "NA", let total = Int64(totalText), total > 0 {
                info.expectedBytes = total
                if let got = info.downloadedBytes {
                    info.sizeText = "\(formatBytes(got))/\(formatBytes(total))"
                }
            }
        }
        if parts.count > 3 {
            let speed = parts[3]
            if speed != "NA", let rate = Double(speed), rate > 0 {
                info.speed = formatBytesPerSecond(rate)
            } else if speed != "NA", !speed.isEmpty {
                info.speed = speed
            }
        }
        if parts.count > 4 {
            let eta = parts[4]
            if eta != "NA", !eta.isEmpty {
                info.eta = formatETA(eta)
            }
        }
        if parts.count > 5 {
            let filename = parts[5]
            if let kind = streamKind(fromPath: filename) {
                info.stream = kind
            }
        }
        return info
    }

    public static func streamKind(fromDestination line: String) -> TransferProgress.StreamKind? {
        let lower = line.lowercased()
        let isDestination = lower.contains("destination") || lower.contains("[download]")
        guard isDestination || lower.contains(progPrefix.lowercased()) else { return nil }
        return streamKind(fromPath: lower)
    }

    public static func streamKind(fromPath path: String) -> TransferProgress.StreamKind? {
        let lower = path.lowercased()
        if lower.contains(".m4a")
            || lower.contains(".opus")
            || lower.contains("audio")
            || lower.contains("dash_sep")
            || lower.contains(".f14")
            || lower.contains(".f139")
            || lower.contains(".f140")
            || lower.contains(".f251") {
            return .audio
        }
        if lower.contains(".webm")
            || lower.contains(".mp4")
            || lower.contains(".mkv")
            || lower.contains("fdash")
            || lower.contains("dash_webm")
            || lower.contains("video") {
            return .video
        }
        return nil
    }

    public static func isMergeLine(_ line: String) -> Bool {
        line.contains("[Merger]") || line.contains("[Fixup]") || line.contains("[Remux]")
    }

    public static func parseAria2(_ line: String) -> TransferProgress? {
        // [#2c3f5a 12MiB/5.4GiB(2%) CN:16 DL:3.5MiB ETA:25m12s]
        // Also: [#2c3f5a 12MiB/5.4GiB(2%) CN:16 SD:3.5MiB]
        let patterns = [
            #"\[#[0-9a-fA-F]+\s+([0-9.]+\s*[KMGT]?i?B)/([0-9.]+\s*[KMGT]?i?B)\(([0-9.]+)%\).*?DL:(\S+)\s+ETA:(\S+)"#,
            #"\[#[0-9a-fA-F]+\s+([0-9.]+\s*[KMGT]?i?B)/([0-9.]+\s*[KMGT]?i?B)\(([0-9.]+)%\).*?DL:(\S+)"#,
            #"\[#[0-9a-fA-F]+\s+([0-9.]+\s*[KMGT]?i?B)/([0-9.]+\s*[KMGT]?i?B)\(([0-9.]+)%\)"#
        ]
        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
                  match.numberOfRanges >= 4,
                  let gotR = Range(match.range(at: 1), in: line),
                  let totR = Range(match.range(at: 2), in: line),
                  let pctR = Range(match.range(at: 3), in: line),
                  let percent = Double(line[pctR]) else {
                continue
            }
            let got = String(line[gotR]).replacingOccurrences(of: " ", with: "")
            let tot = String(line[totR]).replacingOccurrences(of: " ", with: "")
            var speed: String?
            var eta: String?
            if index <= 1, match.numberOfRanges >= 5, let dlR = Range(match.range(at: 4), in: line) {
                speed = String(line[dlR])
            }
            if index == 0, match.numberOfRanges >= 6, let etaR = Range(match.range(at: 5), in: line) {
                eta = String(line[etaR]).trimmingCharacters(in: CharacterSet(charactersIn: "]"))
            }
            return TransferProgress(
                fraction: min(max(percent / 100.0, 0), 1),
                speed: speed,
                eta: eta,
                sizeText: "\(got)/\(tot)",
                expectedBytes: byteCount(tot),
                downloadedBytes: byteCount(got)
            )
        }
        return nil
    }

    public static func byteCount(_ text: String) -> Int64? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern = #"^([0-9]*\.?[0-9]+)\s*([KMGT]?)i?B?$"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive),
              let match = regex.firstMatch(in: trimmed, range: NSRange(trimmed.startIndex..<trimmed.endIndex, in: trimmed)),
              let numR = Range(match.range(at: 1), in: trimmed),
              let value = Double(trimmed[numR]) else {
            return nil
        }
        var unit = ""
        if match.numberOfRanges > 2, let unitR = Range(match.range(at: 2), in: trimmed) {
            unit = String(trimmed[unitR]).uppercased()
        }
        let multipliers: [String: Double] = ["": 1, "K": 1024, "M": 1024 * 1024, "G": 1024 * 1024 * 1024, "T": 1024 * 1024 * 1024 * 1024]
        guard let mul = multipliers[unit] else { return nil }
        return Int64(value * mul)
    }

    public static func allocatedBytes(in directory: String) -> Int64 {
        inProgressMedia(in: directory).reduce(0) { $0 + fileAllocatedBytes($1) }
    }

    public static func activeStream(in directory: String) -> TransferProgress.StreamKind {
        let names = inProgressMedia(in: directory).map { $0.lastPathComponent.lowercased() }
        if names.contains(where: { $0.contains(".m4a") || $0.contains("audio") || $0.contains(".opus") }) {
            return .audio
        }
        if names.contains(where: { $0.contains(".webm") || $0.contains(".mp4") || $0.contains("fdash") || $0.contains("video") }) {
            return .video
        }
        return .unknown
    }

    /// Files that still have an `.aria2` sidecar (the stream currently being written).
    /// Falls back to every media file when aria2c is not in use.
    public static func inProgressMedia(in directory: String) -> [URL] {
        let url = URL(fileURLWithPath: directory)
        guard let items = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: nil) else {
            return []
        }
        let media = items.filter { !$0.lastPathComponent.hasSuffix(".aria2") }
        let active = media.filter { FileManager.default.fileExists(atPath: $0.path + ".aria2") }
        return active.isEmpty ? media : active
    }

    public static func fileAllocatedBytes(_ item: URL) -> Int64 {
        guard let values = try? item.resourceValues(forKeys: [.totalFileAllocatedSizeKey, .fileSizeKey]) else {
            return 0
        }
        return Int64(values.totalFileAllocatedSize ?? values.fileSize ?? 0)
    }

    private static func formatBytes(_ value: Int64) -> String {
        let units = ["B", "KiB", "MiB", "GiB", "TiB"]
        var size = Double(value)
        var index = 0
        while size >= 1024, index < units.count - 1 {
            size /= 1024
            index += 1
        }
        if index == 0 {
            return "\(Int(size))\(units[index])"
        }
        return String(format: "%.1f%@", size, units[index])
    }

    private static func formatBytesPerSecond(_ rate: Double) -> String {
        "\(formatBytes(Int64(rate)))/s"
    }

    private static func formatETA(_ raw: String) -> String {
        if let seconds = Double(raw), seconds.isFinite, seconds >= 0 {
            let total = Int(seconds.rounded())
            let h = total / 3600
            let m = (total % 3600) / 60
            let s = total % 60
            if h > 0 { return "\(h)h\(String(format: "%02dm%02ds", m, s))" }
            if m > 0 { return "\(m)m\(String(format: "%02ds", s))" }
            return "\(s)s"
        }
        return raw
    }
}

public enum OutputFilename {
    public static func make(title: String, videoId: String) -> String {
        "\(sanitize(title))_\(videoId).mkv"
    }

    public static func sanitize(_ title: String) -> String {
        let invalid = CharacterSet(charactersIn: "/\\:?%*|\"<>")
            .union(.newlines)
            .union(.controlCharacters)
        let mapped = title.unicodeScalars.map { invalid.contains($0) ? " " : String($0) }.joined()
        let collapsed = mapped.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = String(collapsed.prefix(80))
        return clipped.isEmpty ? "video" : clipped
    }
}
