import Foundation

/// App Group handoff for Netscape cookies written by the Safari appex and read by the host app.
public enum SharedCookieStore {
    public static let appGroupID = "group.com.ytdownloader.shared"
    public static let directoryName = "ExtensionCookies"

    /// Security-scoped App Group container, or `nil` when unsigned / unavailable (CI).
    public static func containerURL(fileManager: FileManager = .default) -> URL? {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    public static func cookiesDirectory(
        containerURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> URL? {
        let root = containerURL ?? Self.containerURL(fileManager: fileManager)
        guard let root else { return nil }
        return root.appendingPathComponent(directoryName, isDirectory: true)
    }

    /// Persist Netscape text; returns an opaque `cookieRef` for `ytdownloader://…&cookieRef=`.
    public static func writeNetscape(
        videoId: String,
        netscapeText: String,
        containerURL: URL? = nil,
        fileManager: FileManager = .default
    ) throws -> String {
        guard let dir = cookiesDirectory(containerURL: containerURL, fileManager: fileManager) else {
            throw SharedCookieStoreError.containerUnavailable
        }
        try fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        let safeID = sanitize(videoId)
        let ref = "\(safeID)-\(UUID().uuidString)"
        let fileURL = dir.appendingPathComponent("\(ref).txt")
        try Data(netscapeText.utf8).write(to: fileURL, options: .atomic)
        try fileManager.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: fileURL.path
        )
        return ref
    }

    public static func readNetscape(
        cookieRef: String,
        containerURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> String? {
        guard let dir = cookiesDirectory(containerURL: containerURL, fileManager: fileManager) else {
            return nil
        }
        let safe = sanitize(cookieRef)
        guard safe == cookieRef, !safe.isEmpty else { return nil }
        let fileURL = dir.appendingPathComponent("\(safe).txt")
        guard let data = try? Data(contentsOf: fileURL),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    /// Prefer App Group file; fall back to base64url URL payload (legacy / unsigned).
    public static func resolveNetscapePayload(
        cookieRef: String?,
        cookiesURLPayload: String?,
        containerURL: URL? = nil,
        fileManager: FileManager = .default
    ) -> String? {
        if let cookieRef, !cookieRef.isEmpty,
           let text = readNetscape(
            cookieRef: cookieRef,
            containerURL: containerURL,
            fileManager: fileManager
           ) {
            return text
        }
        if let cookiesURLPayload, !cookiesURLPayload.isEmpty {
            return ExtensionCookiePayload.netscapeText(fromURLPayload: cookiesURLPayload)
        }
        return nil
    }

    public static func remove(
        cookieRef: String,
        containerURL: URL? = nil,
        fileManager: FileManager = .default
    ) {
        guard let dir = cookiesDirectory(containerURL: containerURL, fileManager: fileManager) else {
            return
        }
        let safe = sanitize(cookieRef)
        guard safe == cookieRef else { return }
        try? fileManager.removeItem(at: dir.appendingPathComponent("\(safe).txt"))
    }

    private static func sanitize(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return String(value.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
    }
}

public enum SharedCookieStoreError: Error, Equatable, Sendable {
    case containerUnavailable
}
