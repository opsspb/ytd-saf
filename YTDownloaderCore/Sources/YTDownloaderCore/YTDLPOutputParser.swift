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

    public init(
        extractor: String,
        id: String,
        title: String,
        formatId: String,
        resolution: String? = nil,
        fps: Double? = nil
    ) {
        self.extractor = extractor
        self.id = id
        self.title = title
        self.formatId = formatId
        self.resolution = resolution
        self.fps = fps
        let parts = YTDLPOutputParser.splitFormatPair(formatId)
        self.videoFormatId = parts.video
        self.audioFormatId = parts.audio
    }
}

public enum YTDLPOutputParser {
    public static let metaPrefix = "YTD_META:"

    public static func metaPrintTemplate() -> String {
        "\(metaPrefix)%(extractor)s|||%(id)s|||%(title)s|||%(format_id)s|||%(width)sx%(height)s|||%(fps)s"
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
            guard !id.isEmpty, !formatId.isEmpty else { continue }
            return ParsedFormatChoice(
                extractor: extractor,
                id: id,
                title: title,
                formatId: formatId,
                resolution: resolution == "NAxNA" ? nil : resolution,
                fps: fps
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
}
