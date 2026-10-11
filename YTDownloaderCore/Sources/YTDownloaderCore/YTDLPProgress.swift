import Foundation

public enum YTDLPProgress {
    /// Parses yt-dlp `--newline` / `--progress-template` lines into 0...1.
    public static func parse(_ line: String) -> Double? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let patterns = [
            #"download:\s*([0-9]+(?:\.[0-9]+)?)\s*%"#,
            #"\[download\]\s+([0-9]+(?:\.[0-9]+)?)\s*%"#
        ]
        for pattern in patterns {
            if let percent = firstCapture(in: trimmed, pattern: pattern) {
                return min(max(percent / 100.0, 0), 1)
            }
        }
        return nil
    }

    private static func firstCapture(in text: String, pattern: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let match = regex.firstMatch(in: text, range: range),
              match.numberOfRanges > 1,
              let capture = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Double(text[capture])
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
