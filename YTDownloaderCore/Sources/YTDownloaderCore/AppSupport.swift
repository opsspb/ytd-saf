import Foundation

/// Queue and settings live here. Binaries stay in the real Application Support folder.
public enum AppSupport {
    public static let environmentKey = "YTD_APP_SUPPORT"
    public static let argumentName = "--app-support"

    public static func directory(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        arguments: [String] = ProcessInfo.processInfo.arguments
    ) -> URL {
        if let override = environment[environmentKey]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !override.isEmpty {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        if let idx = arguments.firstIndex(of: argumentName), idx + 1 < arguments.count {
            let path = arguments[idx + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                return URL(fileURLWithPath: path, isDirectory: true)
            }
        }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("YTDownloader", isDirectory: true)
    }

    public static func queueFile(in directory: URL? = nil) -> URL {
        (directory ?? Self.directory()).appendingPathComponent("queue.json")
    }

    public static func settingsFile(in directory: URL? = nil) -> URL {
        (directory ?? Self.directory()).appendingPathComponent("settings.json")
    }

    public static func siteName(for url: String) -> String {
        guard let ref = SiteURL.resolve(url) else { return "Video" }
        switch ref.site {
        case .youtube: return "YouTube"
        case .vk: return "VK"
        }
    }

    public static func fetchingTitle(for url: String) -> String {
        "Fetching info… · \(siteName(for: url))"
    }
}
