import Foundation

public struct ParsedFormatChoice: Equatable, Sendable {
    public let extractor: String
    public let id: String
    public let title: String
    public let formatId: String
    public let resolution: String?
    public let fps: Double?
    public let videoFormatId: String
    public let audioFormatId: String?
    public let vcodec: String?
    public let acodec: String?
    public let vbr: Double?
    public let abr: Double?

    public init(
        extractor: String,
        id: String,
        title: String,
        formatId: String,
        resolution: String? = nil,
        fps: Double? = nil,
        vcodec: String? = nil,
        acodec: String? = nil,
        vbr: Double? = nil,
        abr: Double? = nil
    ) {
        self.extractor = extractor
        self.id = id
        self.title = title
        self.formatId = formatId
        self.resolution = resolution
        self.fps = fps
        self.vcodec = vcodec
        self.acodec = acodec
        self.vbr = vbr
        self.abr = abr
        let parts = YTDLPOutputParser.splitFormatPair(formatId)
        self.videoFormatId = parts.video
        self.audioFormatId = parts.audio
    }

    public var summary: String {
        var parts: [String] = []
        if let resolution, !resolution.isEmpty, resolution != "NAxNA" {
            parts.append(resolution)
        }
        if let fps, fps > 0 {
            parts.append("\(Int(fps.rounded()))fps")
        }
        if let vcodec, !vcodec.isEmpty, vcodec != "none" {
            parts.append(YTDLPOutputParser.shortCodec(vcodec))
        }
        if let acodec, !acodec.isEmpty, acodec != "none" {
            let name = YTDLPOutputParser.shortCodec(acodec)
            if let abr, abr > 0 {
                parts.append("+ \(name) \(Int(abr.rounded()))k")
            } else {
                parts.append("+ \(name)")
            }
        }
        if parts.isEmpty {
            return formatId
        }
        return parts.joined(separator: " ")
    }
}

public enum YTDLPOutputParser {
    public static let metaPrefix = "YTD_META:"

    public static func metaPrintTemplate() -> String {
        "\(metaPrefix)%(extractor)s|||%(id)s|||%(title)s|||%(format_id)s|||%(width)sx%(height)s|||%(fps)s|||%(vcodec)s|||%(acodec)s|||%(vbr)s|||%(abr)s"
    }

    public static func parseMeta(from output: String) -> ParsedFormatChoice? {
        for rawLine in output.split(whereSeparator: \.isNewline) {
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix(metaPrefix) else { continue }
            let payload = String(line.dropFirst(metaPrefix.count))
            let parts = payload.split(separator: "|", omittingEmptySubsequences: false).map(String.init)
            // template uses ||| so split on | yields empties between fields
            let fields = parts.filter { !$0.isEmpty }
            guard fields.count >= 4 else { continue }
            let extractor = fields[0]
            let id = fields[1]
            let title = fields[2]
            let formatId = fields[3]
            let resolution = fields.count > 4 ? fields[4] : nil
            let fps = fields.count > 5 ? Double(fields[5]) : nil
            let vcodec = fields.count > 6 ? fields[6] : nil
            let acodec = fields.count > 7 ? fields[7] : nil
            let vbr = fields.count > 8 ? Double(fields[8]) : nil
            let abr = fields.count > 9 ? Double(fields[9]) : nil
            guard !id.isEmpty, !formatId.isEmpty else { continue }
            return ParsedFormatChoice(
                extractor: extractor,
                id: id,
                title: title,
                formatId: formatId,
                resolution: resolution == "NAxNA" ? nil : resolution,
                fps: fps,
                vcodec: vcodec,
                acodec: acodec,
                vbr: vbr,
                abr: abr
            )
        }
        if let fallback = parseChosenFormatLine(from: output) {
            return ParsedFormatChoice(extractor: "vk", id: "", title: "", formatId: fallback)
        }
        return nil
    }

    public static func parseChosenFormatLine(from output: String) -> String? {
        let pattern = #"Downloading 1 format\(s\):\s+(\S+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let ns = output as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: output, range: range),
              match.numberOfRanges >= 2 else {
            return nil
        }
        return ns.substring(with: match.range(at: 1))
    }

    public static func splitFormatPair(_ spec: String) -> (video: String, audio: String?) {
        let parts = spec.split(separator: "+", omittingEmptySubsequences: true).map(String.init)
        guard let first = parts.first else { return (spec, nil) }
        if parts.count >= 2 {
            return (first, parts[1])
        }
        return (first, nil)
    }

    public static func shortCodec(_ raw: String) -> String {
        let lower = raw.lowercased()
        if lower.hasPrefix("vp09") || lower.hasPrefix("vp9") { return "VP9" }
        if lower.hasPrefix("av01") || lower.hasPrefix("av1") { return "AV1" }
        if lower.hasPrefix("avc") || lower.hasPrefix("h264") { return "AVC" }
        if lower.hasPrefix("hev") || lower.hasPrefix("h265") || lower.hasPrefix("hevc") { return "HEVC" }
        if lower.hasPrefix("mp4a") || lower.contains("aac") { return "AAC" }
        if lower.hasPrefix("opus") { return "Opus" }
        if let base = raw.split(separator: ".").first {
            return String(base)
        }
        return raw
    }
}
