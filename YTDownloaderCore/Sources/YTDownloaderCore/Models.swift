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
    }
    
    public init(formatId: String, ext: String, resolution: String? = nil, width: Int? = nil, height: Int? = nil, fps: Double? = nil, vcodec: String? = nil, acodec: String? = nil, vbr: Double? = nil, abr: Double? = nil, tbr: Double? = nil, filesize: Int? = nil, filesizeApprox: Int? = nil, formatNote: String? = nil, language: String? = nil, languagePreference: Int? = nil) {
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
    public var outputPath: String?
    public var addedAt: Date
    public var completedAt: Date?
    
    public init(id: UUID = UUID(), videoId: String, url: String, title: String? = nil, status: DownloadStatus = .queued, progress: Double = 0, error: String? = nil, outputPath: String? = nil, addedAt: Date = Date(), completedAt: Date? = nil) {
        self.id = id
        self.videoId = videoId
        self.url = url
        self.title = title
        self.status = status
        self.progress = progress
        self.error = error
        self.outputPath = outputPath
        self.addedAt = addedAt
        self.completedAt = completedAt
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
    case unknown(String)
    
    public var errorDescription: String? {
        switch self {
        case .ytdlpNotFound:
            return "yt-dlp not found"
        case .ffmpegNotFound:
            return "ffmpeg not found"
        case .invalidURL:
            return "Invalid URL"
        case .fetchInfoFailed(let msg):
            return "Failed to fetch video info: \(msg)"
        case .noSuitableFormats:
            return "No suitable video formats found"
        case .downloadFailed(let msg):
            return "Download failed: \(msg)"
        case .mergeFailed(let msg):
            return "Failed to merge video and audio: \(msg)"
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
        case .networkError(let msg):
            return "Network error: \(msg)"
        case .bootstrapFailed(let msg):
            return "Could not install yt-dlp/ffmpeg: \(msg)"
        case .unknown(let msg):
            return "Unknown error: \(msg)"
        }
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
