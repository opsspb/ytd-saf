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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatId = try container.decode(String.self, forKey: .formatId)
        ext = try container.decode(String.self, forKey: .ext)
        resolution = try container.decodeIfPresent(String.self, forKey: .resolution)
        width = try Self.decodeFlexibleInt(container, forKey: .width)
        height = try Self.decodeFlexibleInt(container, forKey: .height)
        fps = try Self.decodeFlexibleDouble(container, forKey: .fps)
        vcodec = try container.decodeIfPresent(String.self, forKey: .vcodec)
        acodec = try container.decodeIfPresent(String.self, forKey: .acodec)
        vbr = try Self.decodeFlexibleDouble(container, forKey: .vbr)
        abr = try Self.decodeFlexibleDouble(container, forKey: .abr)
        tbr = try Self.decodeFlexibleDouble(container, forKey: .tbr)
        filesize = try Self.decodeFlexibleInt(container, forKey: .filesize)
        filesizeApprox = try Self.decodeFlexibleInt(container, forKey: .filesizeApprox)
        formatNote = try container.decodeIfPresent(String.self, forKey: .formatNote)
        language = try container.decodeIfPresent(String.self, forKey: .language)
        languagePreference = try Self.decodeFlexibleInt(container, forKey: .languagePreference)
        protocolName = try container.decodeIfPresent(String.self, forKey: .protocolName)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(formatId, forKey: .formatId)
        try container.encode(ext, forKey: .ext)
        try container.encodeIfPresent(resolution, forKey: .resolution)
        try container.encodeIfPresent(width, forKey: .width)
        try container.encodeIfPresent(height, forKey: .height)
        try container.encodeIfPresent(fps, forKey: .fps)
        try container.encodeIfPresent(vcodec, forKey: .vcodec)
        try container.encodeIfPresent(acodec, forKey: .acodec)
        try container.encodeIfPresent(vbr, forKey: .vbr)
        try container.encodeIfPresent(abr, forKey: .abr)
        try container.encodeIfPresent(tbr, forKey: .tbr)
        try container.encodeIfPresent(filesize, forKey: .filesize)
        try container.encodeIfPresent(filesizeApprox, forKey: .filesizeApprox)
        try container.encodeIfPresent(formatNote, forKey: .formatNote)
        try container.encodeIfPresent(language, forKey: .language)
        try container.encodeIfPresent(languagePreference, forKey: .languagePreference)
        try container.encodeIfPresent(protocolName, forKey: .protocolName)
    }

    /// yt-dlp sometimes emits ints as floats (or vice versa); accept both.
    private static func decodeFlexibleInt(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Int? {
        if container.contains(key), try container.decodeNil(forKey: key) {
            return nil
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return Int(value.rounded())
        }
        return nil
    }

    private static func decodeFlexibleDouble(
        _ container: KeyedDecodingContainer<CodingKeys>,
        forKey key: CodingKeys
    ) throws -> Double? {
        if container.contains(key), try container.decodeNil(forKey: key) {
            return nil
        }
        if let value = try? container.decodeIfPresent(Double.self, forKey: key) {
            return value
        }
        if let value = try? container.decodeIfPresent(Int.self, forKey: key) {
            return Double(value)
        }
        return nil
    }

    /// Missing codec fields are treated like yt-dlp's `"none"`.
    private var normalizedVcodec: String { vcodec ?? "none" }
    private var normalizedAcodec: String { acodec ?? "none" }

    /// True when resolution/note mark this as an audio-only stream (HLS 233/234 omit `acodec`).
    public var isAudioOnlyByMeta: Bool {
        let resolutionText = (resolution ?? "").lowercased()
        if resolutionText == "audio only" || resolutionText.hasPrefix("audio") {
            return true
        }
        let note = (formatNote ?? "").lowercased()
        return note == "audio only" || note.hasPrefix("audio only")
    }
    
    public var isVideoOnly: Bool {
        let a = normalizedAcodec
        return a == "none" || a.isEmpty
    }
    
    public var isAudioOnly: Bool {
        let v = normalizedVcodec
        return v == "none" || v.isEmpty
    }
    
    public var hasVideo: Bool {
        let v = normalizedVcodec
        return v != "none" && !v.isEmpty
    }
    
    public var hasAudio: Bool {
        let a = normalizedAcodec
        if a != "none" && !a.isEmpty {
            return true
        }
        // Age-restricted / web_safari HLS audio rows often have vcodec=none and null acodec.
        return isAudioOnly && isAudioOnlyByMeta
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

    public var formatSummary: String {
        let resolution: String?
        if let resolutionText = video.resolution, !resolutionText.isEmpty {
            resolution = resolutionText
        } else if let width = video.width, let height = video.height {
            resolution = "\(width)x\(height)"
        } else {
            resolution = nil
        }
        return ParsedFormatChoice(
            extractor: "youtube",
            id: "",
            title: "",
            formatId: "\(video.formatId)+\(audio.formatId)",
            resolution: resolution,
            fps: video.fps,
            vcodec: video.vcodec,
            acodec: audio.acodec,
            vbr: video.vbr,
            abr: audio.abr
        ).summary
    }
}

public enum DownloadStatus: String, Codable {
    case queued
    case retrying
    case downloading
    case merging
    case completed
    case failed
    case cancelled
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
    public var stage: DownloadStage?
    public var formatSummary: String?
    public var speedText: String?
    public var etaText: String?
    public var sizeText: String?
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
        stage: DownloadStage? = nil,
        formatSummary: String? = nil,
        speedText: String? = nil,
        etaText: String? = nil,
        sizeText: String? = nil,
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
        self.stage = stage
        self.formatSummary = formatSummary
        self.speedText = speedText
        self.etaText = etaText
        self.sizeText = sizeText
        self.addedAt = addedAt
        self.completedAt = completedAt
    }

    enum CodingKeys: String, CodingKey {
        case id, videoId, url, title, status, progress, error, log, retryNote, outputPath
        case stage, formatSummary, speedText, etaText, sizeText, addedAt, completedAt
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
        stage = try container.decodeIfPresent(DownloadStage.self, forKey: .stage)
        formatSummary = try container.decodeIfPresent(String.self, forKey: .formatSummary)
        speedText = try container.decodeIfPresent(String.self, forKey: .speedText)
        etaText = try container.decodeIfPresent(String.self, forKey: .etaText)
        sizeText = try container.decodeIfPresent(String.self, forKey: .sizeText)
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
        try container.encodeIfPresent(stage, forKey: .stage)
        try container.encodeIfPresent(formatSummary, forKey: .formatSummary)
        try container.encodeIfPresent(speedText, forKey: .speedText)
        try container.encodeIfPresent(etaText, forKey: .etaText)
        try container.encodeIfPresent(sizeText, forKey: .sizeText)
        try container.encode(addedAt, forKey: .addedAt)
        try container.encodeIfPresent(completedAt, forKey: .completedAt)
    }

    /// Red Error UI is only for a terminal failure.
    public var showsFailureUI: Bool {
        status == .failed && !(error ?? "").isEmpty
    }

    public var displayTitle: String {
        if let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return title
        }
        return AppSupport.fetchingTitle(for: url)
    }

    public var listStatusText: String {
        switch status {
        case .queued:
            return stage == .fetching ? "Fetching info" : "Queued"
        case .retrying:
            return retryNote ?? "Retrying"
        case .downloading:
            return liveTransferLine()
        case .merging:
            return "Merging"
        case .completed:
            return "Done"
        case .cancelled:
            return "Cancelled"
        case .failed:
            if let error, !error.isEmpty {
                return "Failed: \(DownloadError.shortDisplayLine(from: error))"
            }
            return "Failed"
        }
    }

    public var stageSteps: [String] {
        let current = resolvedStage
        let names: [(DownloadStage, String)] = [
            (.fetching, "Fetching info"),
            (.formatChosen, formatSummary.map { "Format chosen: \($0)" } ?? "Format chosen"),
            (.downloadingVideo, "Downloading video"),
            (.downloadingAudio, "Downloading audio"),
            (.merging, "Merging"),
            (.completed, "Done")
        ]
        if status == .failed {
            return names.map(\.1) + ["Failed"]
        }
        if status == .cancelled {
            return names.map(\.1) + ["Cancelled"]
        }
        if status == .retrying {
            return names.map(\.1) + [retryNote ?? "Retrying"]
        }
        var seen = false
        return names.map { stage, label in
            if stage == current { seen = true }
            if stage == current { return "→ \(label)" }
            if !seen { return "✓ \(label)" }
            return label
        }
    }

    private var resolvedStage: DownloadStage {
        if let stage { return stage }
        switch status {
        case .queued: return .fetching
        case .downloading: return .downloadingVideo
        case .merging: return .merging
        case .completed: return .completed
        case .failed: return .failed
        case .retrying: return .retrying
        case .cancelled: return .cancelled
        }
    }

    private func liveTransferLine() -> String {
        switch resolvedStage {
        case .fetching:
            return "Fetching info"
        case .formatChosen:
            if let formatSummary, !formatSummary.isEmpty {
                return "Format chosen: \(formatSummary)"
            }
            return "Format chosen"
        case .downloadingAudio:
            return transferLine(prefix: "Downloading audio")
        case .merging:
            return "Merging"
        default:
            return transferLine(prefix: "Downloading video")
        }
    }

    private func transferLine(prefix: String) -> String {
        var parts = [String(format: "%@ %.0f%%", prefix, progress * 100)]
        if let speedText, !speedText.isEmpty { parts.append(speedText) }
        if let etaText, !etaText.isEmpty { parts.append("ETA \(etaText)") }
        if let sizeText, !sizeText.isEmpty { parts.append(sizeText) }
        return parts.joined(separator: " · ")
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
            self.stage = .completed
            completedAt = Date()
        case .failed:
            if let error {
                self.error = error
            }
            self.retryNote = nil
            self.stage = .failed
            completedAt = Date()
        case .retrying:
            self.error = nil
            if let retryNote {
                self.retryNote = retryNote
            }
        case .cancelled:
            self.error = nil
            self.retryNote = nil
            self.stage = .cancelled
            completedAt = Date()
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
    /// Associated string is yt-dlp stderr (or last ERROR line) for queue details.
    case cookiesRequired(String)
    case ageRestricted
    case membersOnly
    case captchaRequired
    case fullDiskAccessRequired
    case forbidden
    case tooManyRequests
    case networkError(String)
    case bootstrapFailed(String)
    case unsupportedMedia
    case cancelled
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
        case .fullDiskAccessRequired:
            return "Full Disk Access required for Safari cookies"
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
        case .cancelled:
            return "Cancelled"
        case .unknown:
            return "Download failed"
        }
    }

    public var errorDescription: String? {
        switch self {
        case .ytdlpNotFound, .ffmpegNotFound, .invalidURL, .noSuitableFormats,
             .ageRestricted, .membersOnly, .captchaRequired,
             .fullDiskAccessRequired,
             .forbidden, .tooManyRequests, .unsupportedMedia, .cancelled:
            return shortMessage
        case .cookiesRequired(let detail):
            if detail.isEmpty { return shortMessage }
            if let line = YTDLPDiagnostics.lastErrorLine(in: detail) {
                return "\(shortMessage)\n\(line)"
            }
            return "\(shortMessage)\n\(detail)"
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

    /// Raw yt-dlp stderr / detail when the error carried one.
    public var technicalDetail: String? {
        switch self {
        case .cookiesRequired(let detail) where !detail.isEmpty:
            return detail
        case .fetchInfoFailed(let msg), .downloadFailed(let msg), .mergeFailed(let msg),
             .networkError(let msg), .bootstrapFailed(let msg), .unknown(let msg):
            return msg
        default:
            return nil
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
            "Full Disk Access required for Safari cookies",
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
        case .cookiesRequired, .ageRestricted, .membersOnly, .captchaRequired,
             .fullDiskAccessRequired:
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
    public var showWindowOnDownloadStart: Bool
    public var launchAtLogin: Bool

    public init(
        downloadDirectory: String = "~/Downloads",
        cookieMode: CookieMode = .none,
        cookieFilePath: String? = nil,
        maxConcurrentDownloads: Int = 1,
        showWindowOnDownloadStart: Bool = false,
        launchAtLogin: Bool = false
    ) {
        self.downloadDirectory = downloadDirectory
        self.cookieMode = cookieMode
        self.cookieFilePath = cookieFilePath
        self.maxConcurrentDownloads = maxConcurrentDownloads
        self.showWindowOnDownloadStart = showWindowOnDownloadStart
        self.launchAtLogin = launchAtLogin
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        downloadDirectory = try container.decodeIfPresent(String.self, forKey: .downloadDirectory) ?? "~/Downloads"
        cookieMode = try container.decodeIfPresent(CookieMode.self, forKey: .cookieMode) ?? .none
        cookieFilePath = try container.decodeIfPresent(String.self, forKey: .cookieFilePath)
        maxConcurrentDownloads = try container.decodeIfPresent(Int.self, forKey: .maxConcurrentDownloads) ?? 1
        showWindowOnDownloadStart = try container.decodeIfPresent(Bool.self, forKey: .showWindowOnDownloadStart) ?? false
        launchAtLogin = try container.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? false
    }
}
