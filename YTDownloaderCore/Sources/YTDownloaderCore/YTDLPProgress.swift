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

public enum YTDLPProgress {
    /// Parses yt-dlp `--newline` / `--progress-template` lines into 0...1.
    public static func parse(_ line: String) -> Double? {
        parseTransfer(line)?.fraction
    }

    public static func parseTransfer(_ line: String) -> TransferProgress? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

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

    public static func streamKind(fromDestination line: String) -> TransferProgress.StreamKind? {
        let lower = line.lowercased()
        guard lower.contains("destination") || lower.contains("[download]") else { return nil }
        if lower.contains(".m4a") || lower.contains("audio") || lower.contains("dash_sep-1") && lower.contains(".m4a") {
            return .audio
        }
        if lower.contains(".m4a") || lower.contains("audio only") {
            return .audio
        }
        if lower.contains("fdash") || lower.contains(".webm") || lower.contains(".mp4") || lower.contains("video") {
            return .video
        }
        return nil
    }

    public static func parseAria2(_ line: String) -> TransferProgress? {
        // [#2c3f5a 12MiB/5.4GiB(2%) CN:16 DL:3.5MiB ETA:25m12s]
        let pattern = #"\[#[0-9a-fA-F]+\s+([0-9.]+\s*[KMGT]?i?B)/([0-9.]+\s*[KMGT]?i?B)\(([0-9.]+)%\).*?DL:(\S+)\s+ETA:(\S+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..<line.endIndex, in: line)),
              match.numberOfRanges >= 6,
              let gotR = Range(match.range(at: 1), in: line),
              let totR = Range(match.range(at: 2), in: line),
              let pctR = Range(match.range(at: 3), in: line),
              let dlR = Range(match.range(at: 4), in: line),
              let etaR = Range(match.range(at: 5), in: line),
              let percent = Double(line[pctR]) else {
            return nil
        }
        let got = String(line[gotR]).replacingOccurrences(of: " ", with: "")
        let tot = String(line[totR]).replacingOccurrences(of: " ", with: "")
        return TransferProgress(
            fraction: min(max(percent / 100.0, 0), 1),
            speed: String(line[dlR]),
            eta: String(line[etaR]).trimmingCharacters(in: CharacterSet(charactersIn: "]")),
            sizeText: "\(got)/\(tot)",
            expectedBytes: byteCount(tot),
            downloadedBytes: byteCount(got)
        )
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
