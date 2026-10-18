import Foundation

/// Commands accepted by the `ytdownloader://` URL scheme.
public enum AppURLCommand: Equatable, Sendable {
    /// `cookies` is base64url of Netscape cookies.txt or JSON cookie array from the extension.
    case download(videoId: String, url: String, cookies: String? = nil)
    case showQueue
    case showSettings
}

/// Parses `ytdownloader://` handoff URLs from the Safari extension and debug links.
public enum AppURL {
    public static func parse(_ raw: String) -> AppURLCommand? {
        guard let url = URL(string: raw) else { return nil }
        return parse(url)
    }

    public static func parse(_ url: URL) -> AppURLCommand? {
        guard let scheme = url.scheme,
              scheme.caseInsensitiveCompare("ytdownloader") == .orderedSame else {
            return nil
        }

        let host = (url.host ?? "").lowercased()
        let path = url.path.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        let command = host.isEmpty ? path : host

        switch command {
        case "show-queue", "queue":
            return .showQueue
        case "settings", "show-settings":
            return .showSettings
        case "download", "":
            return parseDownload(url)
        default:
            if path == "download" {
                return parseDownload(url)
            }
            return nil
        }
    }

    /// Build a compact download URL (optional cookies payload already base64url-encoded).
    public static func downloadURL(videoId: String, url: String, cookies: String? = nil) -> URL? {
        var components = URLComponents()
        components.scheme = "ytdownloader"
        components.host = "download"
        var items = [
            URLQueryItem(name: "videoId", value: videoId),
            URLQueryItem(name: "url", value: url)
        ]
        if let cookies, !cookies.isEmpty {
            items.append(URLQueryItem(name: "cookies", value: cookies))
        }
        components.queryItems = items
        return components.url
    }

    private static func parseDownload(_ url: URL) -> AppURLCommand? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let videoId = items.first(where: { $0.name == "videoId" })?.value
        let videoURL = items.first(where: { $0.name == "url" })?.value
        let cookies = items.first(where: { $0.name == "cookies" })?.value
        guard let videoId, let videoURL, !videoId.isEmpty, !videoURL.isEmpty else {
            return nil
        }
        let payload = (cookies?.isEmpty == false) ? cookies : nil
        return .download(videoId: videoId, url: videoURL, cookies: payload)
    }
}
