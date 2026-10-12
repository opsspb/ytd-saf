import Foundation

/// Commands accepted by the `ytdownloader://` URL scheme.
public enum AppURLCommand: Equatable, Sendable {
    case download(videoId: String, url: String)
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

    private static func parseDownload(_ url: URL) -> AppURLCommand? {
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let videoId = items.first(where: { $0.name == "videoId" })?.value
        let videoURL = items.first(where: { $0.name == "url" })?.value
        guard let videoId, let videoURL, !videoId.isEmpty, !videoURL.isEmpty else {
            return nil
        }
        return .download(videoId: videoId, url: videoURL)
    }
}
