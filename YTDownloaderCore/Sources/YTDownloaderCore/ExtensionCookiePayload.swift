import Foundation

/// Cookie object matching `browser.cookies.getAll` JSON fields we care about.
public struct BrowserCookie: Codable, Equatable, Sendable {
    public var name: String
    public var value: String
    public var domain: String
    public var path: String
    public var secure: Bool
    public var expirationDate: Double?
    public var httpOnly: Bool?
    public var session: Bool?
    public var hostOnly: Bool?

    public init(
        name: String,
        value: String,
        domain: String,
        path: String = "/",
        secure: Bool = true,
        expirationDate: Double? = nil,
        httpOnly: Bool? = nil,
        session: Bool? = nil,
        hostOnly: Bool? = nil
    ) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.secure = secure
        self.expirationDate = expirationDate
        self.httpOnly = httpOnly
        self.session = session
        self.hostOnly = hostOnly
    }
}

/// Encode/decode compact cookie payloads for `ytdownloader://` handoff (no App Groups).
public enum ExtensionCookiePayload {
    /// Soft cap so Launch Services / Apple Events stay reliable.
    public static let maxEncodedLength = 12_000

    /// Session cookies get this many seconds of synthetic lifetime (not 0).
    public static let sessionCookieLifetime: TimeInterval = 365 * 24 * 60 * 60

    /// High-value auth cookie names kept first when the payload must shrink.
    public static let priorityNames: Set<String> = [
        "LOGIN_INFO", "SID", "HSID", "SSID", "APISID", "SAPISID",
        "__Secure-1PSID", "__Secure-3PSID", "__Secure-1PSIDTS", "__Secure-3PSIDTS",
        "__Secure-1PAPISID", "__Secure-3PAPISID", "SIDCC",
        "__Secure-1PSIDCC", "__Secure-3PSIDCC",
        "VISITOR_INFO1_LIVE", "CONSENT", "SOCS", "PREF", "ACCOUNT_CHOOSER",
        "remixsid", "remixnsid", "remixstid", "remixlgck", "remixdmgr", "p",
        "remixpu", "remixuas", "remixdt"
    ]

    /// Build Netscape text: header, tabs, consistent domain/flag, future session expiry, deduped.
    public static func netscapeText(
        from cookies: [BrowserCookie],
        now: Date = Date()
    ) -> String {
        var lines: [String] = ["# Netscape HTTP Cookie File"]
        for cookie in deduplicate(cookies.map { normalize($0, now: now) }) {
            let domain = cookie.domain
            let includeSub = domain.hasPrefix(".") ? "TRUE" : "FALSE"
            let path = sanitizeField(cookie.path.isEmpty ? "/" : cookie.path)
            let secure = cookie.secure ? "TRUE" : "FALSE"
            let expiryValue = cookie.expirationDate ?? (now.timeIntervalSince1970 + sessionCookieLifetime)
            let expires = String(Int(expiryValue.rounded(.down)))
            let name = sanitizeField(cookie.name)
            let value = sanitizeField(cookie.value)
            lines.append(
                [domain, includeSub, path, secure, expires, name, value]
                    .joined(separator: "\t")
            )
        }
        return lines.joined(separator: "\n")
    }

    /// Re-parse and re-emit so legacy jars (expiry 0, inconsistent flags) become valid.
    public static func normalizeNetscapeText(_ text: String, now: Date = Date()) -> String {
        netscapeText(from: parseNetscapeText(text), now: now)
    }

    public static func parseNetscapeText(_ text: String) -> [BrowserCookie] {
        var result: [BrowserCookie] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            var line = String(rawLine)
            if line.isEmpty || line.hasPrefix("#") {
                // Support `#HttpOnly_.domain…` rows emitted by some exporters.
                if line.hasPrefix("#HttpOnly_") {
                    line = String(line.dropFirst("#HttpOnly_".count))
                } else {
                    continue
                }
            }
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 7 else { continue }
            let domain = parts[0]
            let includeSub = parts[1].uppercased() == "TRUE"
            let expires = Double(parts[4]) ?? 0
            var cookie = BrowserCookie(
                name: parts[5],
                value: parts[6],
                domain: domain,
                path: parts[2],
                secure: parts[3].uppercased() == "TRUE",
                expirationDate: expires > 0 ? expires : nil,
                session: expires == 0,
                hostOnly: domain.hasPrefix(".") ? false : !includeSub
            )
            // Repair inconsistent domain / includeSubdomains pairs on read.
            cookie = normalizeDomainFlags(cookie, includeSubdomains: includeSub)
            result.append(cookie)
        }
        return result
    }

    public static func encodeBase64URL(_ text: String) -> String {
        let data = Data(text.utf8)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .trimmingCharacters(in: CharacterSet(charactersIn: "="))
    }

    public static func decodeBase64URL(_ encoded: String) -> String? {
        var base64 = encoded
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        let remainder = base64.count % 4
        if remainder > 0 {
            base64.append(String(repeating: "=", count: 4 - remainder))
        }
        guard let data = Data(base64Encoded: base64),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    /// Prefer JSON array of browser cookies; fall back to treating the payload as Netscape text.
    /// Also accepts raw Netscape from the App Group handoff (not base64url).
    public static func netscapeText(fromURLPayload encoded: String, now: Date = Date()) -> String? {
        if looksLikeNetscape(encoded) {
            return normalizeNetscapeText(encoded, now: now)
        }
        guard let decoded = decodeBase64URL(encoded) else { return nil }
        if looksLikeNetscape(decoded) {
            return normalizeNetscapeText(decoded, now: now)
        }
        if let data = decoded.data(using: .utf8),
           let cookies = try? JSONDecoder().decode([BrowserCookie].self, from: data) {
            return netscapeText(from: cookies, now: now)
        }
        return nil
    }

    public static func looksLikeNetscape(_ text: String) -> Bool {
        if text.hasPrefix("# Netscape") { return true }
        return text.contains("\t") && (text.contains("\n") || text.split(separator: "\t").count >= 7)
    }

    /// Build a URL-safe payload, dropping lower-priority cookies if over the size cap.
    public static func encodeForURL(cookies: [BrowserCookie], now: Date = Date()) -> String? {
        guard !cookies.isEmpty else { return nil }
        let ordered = prioritize(cookies)
        if let full = encodeIfFits(ordered, now: now) {
            return full
        }
        var kept = ordered.filter { priorityNames.contains($0.name) }
        if kept.isEmpty {
            kept = Array(ordered.prefix(20))
        }
        while !kept.isEmpty {
            if let encoded = encodeIfFits(kept, now: now) {
                return encoded
            }
            kept.removeLast()
        }
        return nil
    }

    public static func encodeNetscapeForURL(_ netscape: String) -> String? {
        guard !netscape.isEmpty else { return nil }
        let encoded = encodeBase64URL(netscape)
        return encoded.count <= maxEncodedLength ? encoded : nil
    }

    /// Full Netscape for App Group / native messaging (no URL size cap).
    public static func encodeNetscapeFull(_ netscape: String) -> String {
        encodeBase64URL(netscape)
    }

    /// Write a private 0600 Netscape cookies file for one download attempt.
    public static func writeTempCookieFile(netscapeText: String) throws -> URL {
        let normalized = normalizeNetscapeText(netscapeText)
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytd-cookies-\(UUID().uuidString).txt")
        try Data(normalized.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
        return url
    }

    // MARK: - Normalization

    public static func normalize(_ cookie: BrowserCookie, now: Date = Date()) -> BrowserCookie {
        var copy = normalizeDomainFlags(cookie, includeSubdomains: nil)
        copy.name = sanitizeField(copy.name)
        copy.value = sanitizeField(copy.value)
        copy.path = sanitizeField(copy.path.isEmpty ? "/" : copy.path)

        let isSession = copy.session == true || copy.expirationDate == nil || (copy.expirationDate ?? 0) <= 0
        if isSession {
            copy.session = false
            copy.expirationDate = now.timeIntervalSince1970 + sessionCookieLifetime
        } else if let expiry = copy.expirationDate, expiry < now.timeIntervalSince1970 {
            // Keep past expiry as-is so callers can still inspect; yt-dlp may skip it.
            copy.expirationDate = expiry
        }
        return copy
    }

    /// Ensure leading-dot domain ↔ includeSubdomains TRUE/FALSE stay consistent.
    public static func normalizeDomainFlags(
        _ cookie: BrowserCookie,
        includeSubdomains: Bool?
    ) -> BrowserCookie {
        var copy = cookie
        var domain = copy.domain.trimmingCharacters(in: .whitespacesAndNewlines)
        let hostOnly = copy.hostOnly

        let wantSubdomains: Bool
        if let hostOnly {
            wantSubdomains = !hostOnly
        } else if let includeSubdomains {
            wantSubdomains = includeSubdomains
        } else {
            wantSubdomains = domain.hasPrefix(".")
        }

        if wantSubdomains {
            if !domain.hasPrefix(".") {
                domain = "." + domain
            }
        } else if domain.hasPrefix(".") {
            domain = String(domain.dropFirst())
        }

        copy.domain = domain
        copy.hostOnly = !wantSubdomains
        return copy
    }

    public static func deduplicate(_ cookies: [BrowserCookie]) -> [BrowserCookie] {
        var best: [String: BrowserCookie] = [:]
        var order: [String] = []
        for cookie in cookies {
            let key = "\(cookie.domain.lowercased())\n\(cookie.path)\n\(cookie.name)"
            if let existing = best[key] {
                let existingExpiry = existing.expirationDate ?? 0
                let newExpiry = cookie.expirationDate ?? 0
                if newExpiry > existingExpiry || (newExpiry == existingExpiry && cookie.value.count > existing.value.count) {
                    best[key] = cookie
                }
            } else {
                best[key] = cookie
                order.append(key)
            }
        }
        return order.compactMap { best[$0] }
    }

    private static func sanitizeField(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\r", with: "")
            .replacingOccurrences(of: "\n", with: "")
            .replacingOccurrences(of: "\t", with: " ")
    }

    private static func encodeIfFits(_ cookies: [BrowserCookie], now: Date) -> String? {
        let text = netscapeText(from: cookies, now: now)
        let encoded = encodeBase64URL(text)
        return encoded.count <= maxEncodedLength ? encoded : nil
    }

    private static func prioritize(_ cookies: [BrowserCookie]) -> [BrowserCookie] {
        cookies.sorted { a, b in
            let ap = priorityNames.contains(a.name)
            let bp = priorityNames.contains(b.name)
            if ap != bp { return ap && !bp }
            return a.name < b.name
        }
    }
}
