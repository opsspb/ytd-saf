import Foundation

public struct VideoFormat: Codable, Equatable, Sendable {
    public let formatId: String
    public let ext: String
    public let resolution: String?
    public let width: Int?
    public let height: Int?
    public let fps: Double?
    public let vcodec: String?
    public let acodec: String?
    public let vbr: Double?
    public let abr: Double?
    public let tbr: Double?
    public let filesize: Int?
    public let filesizeApprox: Int?
    public let formatNote: String?
    public let language: String?
    public let languagePreference: Int?
    public let protocolName: String?
    
    enum CodingKeys: String, CodingKey {
        case formatId = "format_id"
        case ext
        case resolution
        case width
        case height
        case fps
        case vcodec
        case acodec
        case vbr
        case abr
        case tbr
        case filesize
        case filesizeApprox = "filesize_approx"
        case formatNote = "format_note"
        case language
        case languagePreference = "language_preference"
        case protocolName = "protocol"
    }
    
    public init(formatId: String, ext: String, resolution: String? = nil, width: Int? = nil, height: Int? = nil, fps: Double? = nil, vcodec: String? = nil, acodec: String? = nil, vbr: Double? = nil, abr: Double? = nil, tbr: Double? = nil, filesize: Int? = nil, filesizeApprox: Int? = nil, formatNote: String? = nil, language: String? = nil, languagePreference: Int? = nil, protocolName: String? = nil) {
        self.formatId = formatId
        self.ext = ext
        self.resolution = resolution
        self.width = width
        self.height = height
        self.fps = fps
        self.vcodec = vcodec
        self.acodec = acodec
        self.vbr = vbr
        self.abr = abr
        self.tbr = tbr
        self.filesize = filesize
        self.filesizeApprox = filesizeApprox
        self.formatNote = formatNote
        self.language = language
        self.languagePreference = languagePreference
        self.protocolName = protocolName
    }
    
    public var isVideoOnly: Bool {
        guard let acodec = acodec else { return false }
        return acodec == "none" || acodec.isEmpty
    }
    
    public var isAudioOnly: Bool {
        guard let vcodec = vcodec else { return false }
        return vcodec == "none" || vcodec.isEmpty
    }
    
    public var hasVideo: Bool {
        guard let vcodec = vcodec else { return false }
        return vcodec != "none" && !vcodec.isEmpty
    }
    
    public var hasAudio: Bool {
        guard let acodec = acodec else { return false }
        return acodec != "none" && !acodec.isEmpty
    }
}

public struct YTDLPInfo: Codable, Sendable {
    public let id: String
    public let title: String
    public let formats: [VideoFormat]
    public let originalUrl: String?
    public let webpageUrl: String?
    
    enum CodingKeys: String, CodingKey {
        case id
        case title
        case formats
        case originalUrl = "original_url"
        case webpageUrl = "webpage_url"
    }
    
    public init(id: String, title: String, formats: [VideoFormat], originalUrl: String? = nil, webpageUrl: String? = nil) {
        self.id = id
        self.title = title
        self.formats = formats
        self.originalUrl = originalUrl
        self.webpageUrl = webpageUrl
    }
}

public struct SelectedFormats: Equatable, Sendable {
    public let video: VideoFormat
    public let audio: VideoFormat
    
    public init(video: VideoFormat, audio: VideoFormat) {
        self.video = video
        self.audio = audio
    }
}

public enum DownloadStatus: String, Codable {
    case queued
    case retrying
    case downloading
    case merging
    case completed
    case failed
}

public struct DownloadItem: Codable, Identifiable, Equatable, Hashable {
    public let id: UUID
    public let videoId: String
    public let url: String
    public var title: String?
    public var status: DownloadStatus
    public var progress: Double
    public var error: String?
    public var log: String?
    public var retryNote: String?
    public var outputPath: String?
    public var addedAt: Date
    public var completedAt: Date?
    
    public init(
        id: UUID = UUID(),
        videoId: String,
        url: String,
        title: String? = nil,
        status: DownloadStatus = .queued,
        progress: Double = 0,
        error: String? = nil,
        log: String? = nil,
        retryNote: String? = nil,
        outputPath: String? = nil,
        addedAt: Date = Date(),
        completedAt: Date? = nil
    ) {
        self.id = id
        self.videoId = videoId
        self.url = url
        self.title = title
        self.status = status
        self.progress = progress
        self.error = error
        self.log = log
        self.retryNote = retryNote
        self.outputPath = outputPath
        self.addedAt = addedAt
        self.completedAt = completedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, videoId, url, title, status, progress, error, log, retryNote, outputPath, addedAt, completedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        videoId = try container.decode(String.self, forKey: .videoId)
        url = try container.decode(String.self, forKey: .url)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        status = try container.decode(DownloadStatus.self, forKey: .status)
        progress = try container.decode(Double.self, forKey: .progress)
        error = try container.decodeIfPresent(String.self, forKey: .error)
        log = try container.decodeIfPresent(String.self, forKey: .log)
        retryNote = try container.decodeIfPresent(String.self, forKey: .retryNote)
        outputPath = try container.decodeIfPresent(String.self, forKey: .outputPath)
        addedAt = try container.decode(Date.self, forKey: .addedAt)
        completedAt = try container.decodeIfPresent(Date.self, forKey: .completedAt)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(videoId, forKey: .videoId)
        try container.encode(url, forKey: .url)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encode(status, forKey: .status)
        try container.encode(progress, forKey: .progress)
        try container.encodeIfPresent(error, forKey: .error)
        try container.encodeIfPresent(log, forKey: .log)
        try container.encodeIfPresent(retryNote, forKey: .retryNote)
        try container.encodeIfPresent(outputPath, forKey: .outputPath)
        try container.encode(addedAt, forKey: .addedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
    }

    /// Red Error UI is only for a terminal failure.
    public var showsFailureUI: Bool {
        status == .failed && !(error ?? "").isEmpty
    }

    public var listStatusText: String {
        switch status {
        case .queued:
            return "Queued"
        case .retrying:
            return retryNote ?? "Retrying"
        case .downloading:
            return String(format: "Downloading %.0f%%", progress * 100)
        case .merging:
            return "Merging..."
        case .completed:
            return "Completed"
        case .failed:
            if let error, !error.isEmpty {
                return "Failed: \(DownloadError.shortDisplayLine(from: error))"
            }
            return "Failed"
        }
    }

    public static func retryStatusLine(delay: TimeInterval, attempt: Int, maxAttempts: Int) -> String {
        "Retrying in \(Int(delay.rounded()))s, attempt \(attempt)/\(maxAttempts)"
    }

    public mutating func applyStatus(
        _ status: DownloadStatus,
        progress: Double? = nil,
        error: String? = nil,
        outputPath: String? = nil,
        retryNote: String? = nil,
        appendLog: String? = nil
    ) {
        self.status = status
        if let progress {
            self.progress = progress
        }
        if let outputPath {
            self.outputPath = outputPath
        }
        if let appendLog, !appendLog.isEmpty {
            if let existing = log, !existing.isEmpty {
                log = existing + "\n" + appendLog
            } else {
                log = appendLog
            }
        }

        switch status {
        case .completed:
            if let leftover = self.error, !leftover.isEmpty {
                appendToLog(leftover)
            }
            self.error = nil
            self.retryNote = nil
            completedAt = Date()
        case .failed:
            if let error {
                self.error = error
            }
            self.retryNote = nil
            completedAt = Date()
        case .retrying:
            self.error = nil
            if let retryNote {
                self.retryNote = retryNote
            }
        case .queued, .downloading, .merging:
            if let retryNote {
                self.retryNote = retryNote
            }
            if status == .downloading || status == .merging {
                self.retryNote = nil
            }
        }
    }

    /// Launch recovery: leftover interrupt text is not a red error; success clears it.
    public mutating func sanitizeAfterLoad() {
        if status == .completed {
            if let error, !error.isEmpty {
                appendToLog(error)
            }
            error = nil
            retryNote = nil
            return
        }
        if status == .downloading || status == .merging || status == .retrying {
            if let error, !error.isEmpty {
                appendToLog(error)
            } else {
                appendToLog("Interrupted; retrying")
            }
            status = .queued
            progress = 0
            error = nil
            retryNote = nil
        }
    }

    private mutating func appendToLog(_ line: String) {
        if let existing = log, !existing.isEmpty {
            log = existing + "\n" + line
        } else {
            log = line
        }
    }
}

public enum DownloadError: Error, LocalizedError, Equatable {
    case ytdlpNotFound
    case ffmpegNotFound
    case invalidURL
    case fetchInfoFailed(String)
    case noSuitableFormats
    case downloadFailed(String)
    case mergeFailed(String)
    case cookiesRequired
    case ageRestricted
    case membersOnly
    case captchaRequired
    case forbidden
    case tooManyRequests
    case networkError(String)
    case bootstrapFailed(String)
    case unsupportedMedia
    case unknown(String)
    
    public var shortMessage: String {
        switch self {
        case .ytdlpNotFound:
            return "yt-dlp not found"
        case .ffmpegNotFound:
            return "ffmpeg not found"
        case .invalidURL:
            return "Invalid URL"
        case .fetchInfoFailed:
            return "Failed to fetch video info"
        case .noSuitableFormats:
            return "No suitable video formats found"
        case .downloadFailed:
            return "Download failed"
        case .mergeFailed:
            return "Failed to merge video and audio"
        case .cookiesRequired:
            return "Cookies required (sign-in needed)"
        case .ageRestricted:
            return "Age-restricted video (cookies required)"
        case .membersOnly:
            return "Members-only video (cookies required)"
        case .captchaRequired:
            return "CAPTCHA required (cookies needed)"
        case .forbidden:
            return "Access forbidden (403)"
        case .tooManyRequests:
            return "Too many requests (429)"
        case .networkError:
            return "Network error"
        case .bootstrapFailed:
            return "Could not install yt-dlp/ffmpeg"
        case .unsupportedMedia:
            return "This page is not supported (live, playlist, or embed)"
        case .unknown:
            return "Download failed"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .ytdlpNotFound, .ffmpegNotFound, .invalidURL, .noSuitableFormats,
             .cookiesRequired, .ageRestricted, .membersOnly, .captchaRequired,
             .forbidden, .tooManyRequests, .unsupportedMedia:
            return shortMessage
        case .fetchInfoFailed(let msg):
            return "Failed to fetch video info: \(msg)"
        case .downloadFailed(let msg):
            return "Download failed: \(msg)"
        case .mergeFailed(let msg):
            return "Failed to merge video and audio: \(msg)"
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .bootstrapFailed(let msg):
            return "Could not install yt-dlp/ffmpeg: \(msg)"
        case .unknown(let msg):
            return "Unknown error: \(msg)"
        }
    }

    /// First-line summary for the queue list; full `errorDescription` stays in the detail disclosure.
    public static func shortDisplayLine(from stored: String?) -> String {
        guard let stored, !stored.isEmpty else { return "Failed" }
        let firstLine = stored.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
            .first
            .map { String($0).trimmingCharacters(in: .whitespaces) } ?? stored

        let known = [
            "Failed to merge video and audio",
            "Failed to fetch video info",
            "No suitable video formats found",
            "yt-dlp not found",
            "ffmpeg not found",
            "Invalid URL",
            "Cookies required (sign-in needed)",
            "Age-restricted video (cookies required)",
            "Members-only video (cookies required)",
            "CAPTCHA required (cookies needed)",
            "Access forbidden (403)",
            "Too many requests (429)",
            "Network error",
            "Could not install yt-dlp/ffmpeg",
            "This page is not supported (live, playlist, or embed)",
            "Download failed",
        ]
        for prefix in known where firstLine.hasPrefix(prefix) || stored.hasPrefix(prefix) {
            return prefix
        }

        if stored.hasPrefix("Unknown error") {
            if let inner = lastErrorLine(in: stored) {
                return truncate(stripErrorPrefix(inner), 120)
            }
            if let colon = stored.range(of: ": ") {
                return truncate(stripErrorPrefix(String(stored[colon.upperBound...])), 120)
            }
            return "Download failed"
        }

        if let inner = lastErrorLine(in: stored), firstLine.count > 80 {
            return truncate(stripErrorPrefix(inner), 120)
        }
        return truncate(firstLine, 120)
    }

    public static func hasTechnicalDetails(_ stored: String?) -> Bool {
        guard let stored, !stored.isEmpty else { return false }
        return stored != shortDisplayLine(from: stored)
    }

    private static func lastErrorLine(in stored: String) -> String? {
        let lines = stored.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        for line in lines.reversed() {
            if let range = line.range(of: "ERROR:", options: [.caseInsensitive, .backwards]) {
                return String(line[range.lowerBound...])
            }
        }
        return nil
    }

    private static func stripErrorPrefix(_ line: String) -> String {
        var text = line
        if let range = text.range(of: "ERROR:", options: .caseInsensitive),
           range.lowerBound == text.startIndex {
            text = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        return text
    }

    private static func truncate(_ text: String, _ limit: Int) -> String {
        if text.count <= limit { return text }
        return String(text.prefix(limit - 1)) + "…"
    }
    
    public var requiresCookies: Bool {
        switch self {
        case .cookiesRequired, .ageRestricted, .membersOnly, .captchaRequired:
            return true
        default:
            return false
        }
    }
    
    public var isTransient: Bool {
        switch self {
        case .forbidden, .tooManyRequests, .networkError:
            return true
        default:
            return false
        }
    }
}

public enum CookieMode: String, Codable, Sendable {
    case none
    case safari
    case file
}

public struct DownloadSettings: Codable, Equatable {
    public var downloadDirectory: String
    public var cookieMode: CookieMode
    public var cookieFilePath: String?
    public var maxConcurrentDownloads: Int
    
    public init(downloadDirectory: String = "~/Downloads", cookieMode: CookieMode = .none, cookieFilePath: String? = nil, maxConcurrentDownloads: Int = 1) {
        self.downloadDirectory = downloadDirectory
        self.cookieMode = cookieMode
        self.cookieFilePath = cookieFilePath
        self.maxConcurrentDownloads = maxConcurrentDownloads
    }
}
