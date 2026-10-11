import Foundation

public enum SiteKind: String, Codable, Sendable, Equatable {
    case youtube
    case vk
}

public enum MediaKind: String, Codable, Sendable, Equatable {
    case video
    case clip
    case live
    case playlist
    case unsupported
}

public struct MediaRef: Equatable, Sendable {
    public let site: SiteKind
    public let id: String
    public let kind: MediaKind
    public let url: String

    public init(site: SiteKind, id: String, kind: MediaKind, url: String) {
        self.site = site
        self.id = id
        self.kind = kind
        self.url = url
    }

    public var isDownloadable: Bool {
        kind == .video || kind == .clip
    }
}

public enum SiteURL {
    public static func resolve(_ raw: String) -> MediaRef? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if let youtube = resolveYouTube(trimmed) { return youtube }
        if let vk = resolveVK(trimmed) { return vk }
        return nil
    }

    public static func resolveYouTube(_ raw: String) -> MediaRef? {
        guard let parsed = URL(string: raw) ?? URL(string: raw, relativeTo: URL(string: "https://www.youtube.com")) else {
            return extractYouTubeQuery(raw)
        }
        let host = (parsed.host ?? "").lowercased()
        guard host.contains("youtube.com") || host == "youtu.be" else {
            return extractYouTubeQuery(raw)
        }
        if host == "youtu.be", let id = parsed.path.split(separator: "/").first, !id.isEmpty {
            let videoId = String(id)
            return MediaRef(site: .youtube, id: videoId, kind: .video, url: "https://www.youtube.com/watch?v=\(videoId)")
        }
        if let id = parsed.query?.split(separator: "&").compactMap({ pair -> String? in
            let parts = pair.split(separator: "=", maxSplits: 1)
            return parts.first == "v" ? parts.dropFirst().first.map(String.init) : nil
        }).first, !id.isEmpty {
            return MediaRef(site: .youtube, id: id, kind: .video, url: "https://www.youtube.com/watch?v=\(id)")
        }
        if parsed.path.contains("/shorts/"), let id = parsed.path.split(separator: "/").last {
            return MediaRef(site: .youtube, id: String(id), kind: .video, url: "https://www.youtube.com/watch?v=\(id)")
        }
        return extractYouTubeQuery(raw)
    }

    public static func resolveVK(_ raw: String) -> MediaRef? {
        guard let parsed = URL(string: raw) ?? URL(string: raw, relativeTo: URL(string: "https://vkvideo.ru")) else {
            return extractVK(from: raw, hostHint: nil)
        }
        let host = (parsed.host ?? "").lowercased()
        if host == "live.vkvideo.ru" || host.hasSuffix(".live.vkvideo.ru") {
            return MediaRef(site: .vk, id: "", kind: .unsupported, url: raw)
        }
        let vkHost = host == "vkvideo.ru" || host.hasSuffix(".vkvideo.ru")
            || host == "vk.com" || host.hasSuffix(".vk.com")
            || host == "vk.ru" || host.hasSuffix(".vk.ru")
        guard vkHost else { return extractVK(from: raw, hostHint: host) }

        let path = parsed.path
        if path.contains("/live-") || path.contains("/playlist/") {
            let kind: MediaKind = path.contains("/live-") ? .live : .playlist
            return MediaRef(site: .vk, id: "", kind: kind, url: raw)
        }
        if let z = URLComponents(url: parsed, resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "z" })?.value,
           let extracted = extractVK(from: z, hostHint: host) {
            return extracted
        }
        if path.contains("video_ext.php") {
            return MediaRef(site: .vk, id: "", kind: .unsupported, url: raw)
        }
        return extractVK(from: path + "?" + (parsed.query ?? ""), hostHint: host)
    }

    private static func extractYouTubeQuery(_ raw: String) -> MediaRef? {
        guard let match = raw.range(of: #"[?&]v=([^&]+)"#, options: .regularExpression) else { return nil }
        let query = String(raw[match]).split(separator: "=").last.map(String.init) ?? ""
        guard !query.isEmpty else { return nil }
        return MediaRef(site: .youtube, id: query, kind: .video, url: "https://www.youtube.com/watch?v=\(query)")
    }

    private static func extractVK(from raw: String, hostHint _: String?) -> MediaRef? {
        let pattern = #"(?:^|[/?=&])(video|clip)(-?\d+)_(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = raw as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let match = regex.firstMatch(in: raw, range: range), match.numberOfRanges >= 4,
              let kindRange = Range(match.range(at: 1), in: raw),
              let oidRange = Range(match.range(at: 2), in: raw),
              let idRange = Range(match.range(at: 3), in: raw) else {
            return nil
        }
        let kindRaw = String(raw[kindRange])
        let oid = String(raw[oidRange])
        let vid = String(raw[idRange])
        let id = "\(oid)_\(vid)"
        let kind: MediaKind = kindRaw == "clip" ? .clip : .video
        let canonical = "https://vkvideo.ru/\(kindRaw)\(oid)_\(vid)"
        return MediaRef(site: .vk, id: id, kind: kind, url: canonical)
    }
}

public struct SiteAdapterInfo: Equatable, Sendable {
    public let site: SiteKind
    public let formatSpec: String?
    public let formatSort: String?
    public let extraArgs: [String]
    public let concurrentFragments: Int?
    public let wantsExternalDownloader: Bool
    public let externalDownloaderArgs: String?

    public init(
        site: SiteKind,
        formatSpec: String? = nil,
        formatSort: String? = nil,
        extraArgs: [String] = [],
        concurrentFragments: Int? = nil,
        wantsExternalDownloader: Bool = false,
        externalDownloaderArgs: String? = nil
    ) {
        self.site = site
        self.formatSpec = formatSpec
        self.formatSort = formatSort
        self.extraArgs = extraArgs
        self.concurrentFragments = concurrentFragments
        self.wantsExternalDownloader = wantsExternalDownloader
        self.externalDownloaderArgs = externalDownloaderArgs
    }

    /// Speed-only flags. Never includes `-f` / `-S` — format choice stays on the sorter.
    public func downloadArgs(aria2cPath: String?) -> [String] {
        var args = extraArgs
        if let concurrentFragments {
            args += ["--concurrent-fragments", "\(concurrentFragments)"]
        }
        if wantsExternalDownloader, let aria2cPath, !aria2cPath.isEmpty {
            args += ["--external-downloader", aria2cPath]
            if let externalDownloaderArgs {
                args += ["--external-downloader-args", "aria2c:\(externalDownloaderArgs)"]
            }
        }
        return args
    }
}

public enum SiteAdapterRegistry {
    public static let aria2cArgs = "-j 16 -s 16 -x 16 -k 1M --file-allocation=none --summary-interval=1 --console-log-level=notice"

    public static let youtube = SiteAdapterInfo(site: .youtube)
    public static let vk = SiteAdapterInfo(
        site: .vk,
        formatSpec: "bv*+ba/b",
        formatSort: "res,fps,vbr,abr,proto:https",
        extraArgs: ["--no-write-subs", "--retries", "3", "--fragment-retries", "5"],
        concurrentFragments: 16,
        wantsExternalDownloader: true,
        externalDownloaderArgs: aria2cArgs
    )

    public static func adapter(for url: String) -> SiteAdapterInfo {
        guard let ref = SiteURL.resolve(url), ref.site == .vk else {
            return youtube
        }
        return vk
    }
}
