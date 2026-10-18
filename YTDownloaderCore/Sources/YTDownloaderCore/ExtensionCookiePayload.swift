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

    public init(
        name: String,
        value: String,
        domain: String,
        path: String = "/",
        secure: Bool = true,
        expirationDate: Double? = nil,
        httpOnly: Bool? = nil,
        session: Bool? = nil
    ) {
        self.name = name
        self.value = value
        self.domain = domain
        self.path = path
        self.secure = secure
        self.expirationDate = expirationDate
        self.httpOnly = httpOnly
        self.session = session
    }
}

/// Encode/decode compact cookie payloads for `ytdownloader://` handoff (no App Groups).
public enum ExtensionCookiePayload {
    /// Soft cap so Launch Services / Apple Events stay reliable.
    public static let maxEncodedLength = 12_000

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

    public static func netscapeText(from cookies: [BrowserCookie]) -> String {
        var lines: [String] = ["# Netscape HTTP Cookie File"]
        for cookie in cookies {
            let domain = cookie.domain
            let includeSub = domain.hasPrefix(".") ? "TRUE" : "FALSE"
            let path = cookie.path.isEmpty ? "/" : cookie.path
            let secure = cookie.secure ? "TRUE" : "FALSE"
            let expires: String
            if cookie.session == true || cookie.expirationDate == nil {
                expires = "0"
            } else {
                expires = String(Int(cookie.expirationDate!.rounded(.down)))
            }
            // Never log values; only write to the returned string for yt-dlp.
            lines.append(
                [domain, includeSub, path, secure, expires, cookie.name, cookie.value]
                    .joined(separator: "\t")
            )
        }
        return lines.joined(separator: "\n")
    }

    public static func parseNetscapeText(_ text: String) -> [BrowserCookie] {
        var result: [BrowserCookie] = []
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = String(rawLine)
            if line.isEmpty || line.hasPrefix("#") { continue }
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
            guard parts.count >= 7 else { continue }
            let expires = Double(parts[4]) ?? 0
            result.append(
                BrowserCookie(
                    name: parts[5],
                    value: parts[6],
                    domain: parts[0],
                    path: parts[2],
                    secure: parts[3].uppercased() == "TRUE",
                    expirationDate: expires > 0 ? expires : nil,
                    session: expires == 0
                )
            )
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
    public static func netscapeText(fromURLPayload encoded: String) -> String? {
        guard let decoded = decodeBase64URL(encoded) else { return nil }
        if decoded.contains("\t"), decoded.contains("\n") || decoded.hasPrefix("#") {
            return decoded
        }
        if let data = decoded.data(using: .utf8),
           let cookies = try? JSONDecoder().decode([BrowserCookie].self, from: data) {
            return netscapeText(from: cookies)
        }
        // Raw Netscape without tabs check edge case
        if decoded.contains("\t") {
            return decoded
        }
        return nil
    }

    /// Build a URL-safe payload, dropping lower-priority cookies if over the size cap.
    public static func encodeForURL(cookies: [BrowserCookie]) -> String? {
        guard !cookies.isEmpty else { return nil }
        let ordered = prioritize(cookies)
        if let full = encodeIfFits(ordered) {
            return full
        }
        var kept = ordered.filter { priorityNames.contains($0.name) }
        if kept.isEmpty {
            kept = Array(ordered.prefix(20))
        }
        while !kept.isEmpty {
            if let encoded = encodeIfFits(kept) {
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

    /// Write a private 0600 Netscape cookies file for one download attempt.
    public static func writeTempCookieFile(netscapeText: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytd-cookies-\(UUID().uuidString).txt")
        try Data(netscapeText.utf8).write(to: url, options: .atomic)
        try FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: Int16(0o600))],
            ofItemAtPath: url.path
        )
        return url
    }

    private static func encodeIfFits(_ cookies: [BrowserCookie]) -> String? {
        let text = netscapeText(from: cookies)
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
