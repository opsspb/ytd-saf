import Foundation

/// Diagnostics for cookie handoff + yt-dlp runs. Never logs cookie values.
public enum YTDLPDiagnostics {
    public static let keyAuthCookieNames: [String] = [
        "LOGIN_INFO",
        "__Secure-3PSID",
        "__Secure-1PSID",
        "SID",
        "SAPISID",
        "SSID",
        "HSID"
    ]

    /// `~/Library/Logs/YTDownloader/` under the current user's home.
    public static func logsDirectory(
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        fileManager: FileManager = .default
    ) -> URL {
        let dir = homeDirectory.appendingPathComponent("Library/Logs/YTDownloader", isDirectory: true)
        try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Metadata-only cookie listing: name, domain, path, secure, httpOnly, expiry. No values.
    public static func cookieFlagLines(from cookies: [BrowserCookie]) -> [String] {
        cookies.map { cookie in
            let expiry: String
            if let date = cookie.expirationDate, date > 0 {
                expiry = String(Int(date.rounded(.down)))
            } else {
                expiry = "session"
            }
            let httpOnly = cookie.httpOnly == true ? "true" : "false"
            return [
                "name=\(cookie.name)",
                "domain=\(cookie.domain)",
                "path=\(cookie.path.isEmpty ? "/" : cookie.path)",
                "secure=\(cookie.secure)",
                "httpOnly=\(httpOnly)",
                "expiry=\(expiry)"
            ].joined(separator: " ")
        }
    }

    public static func cookieFlagLines(fromNetscape text: String) -> [String] {
        cookieFlagLines(from: ExtensionCookiePayload.parseNetscapeText(text))
    }

    /// Key auth cookies that are absent from the Netscape jar (by name, any domain).
    public static func missingAuthCookieNames(in cookies: [BrowserCookie]) -> [String] {
        let present = Set(cookies.map(\.name))
        return keyAuthCookieNames.filter { !present.contains($0) }
    }

    public static func missingAuthCookieNames(inNetscape text: String) -> [String] {
        missingAuthCookieNames(in: ExtensionCookiePayload.parseNetscapeText(text))
    }

    /// Last line containing `ERROR:` (case-insensitive), or nil.
    public static func lastErrorLine(in output: String) -> String? {
        let lines = output.split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        for line in lines.reversed() {
            if line.range(of: "ERROR:", options: .caseInsensitive) != nil {
                return line
            }
        }
        return nil
    }

    /// Shell-safe command line with cookie file path retained; never expands cookie contents.
    public static func commandLine(executable: String, arguments: [String]) -> String {
        ([executable] + arguments).map(shellEscape).joined(separator: " ")
    }

    /// Append a diagnostics record for one yt-dlp invocation.
    @discardableResult
    public static func writeRunLog(
        executable: String,
        arguments: [String],
        stderr: String,
        cookieFilePath: String?,
        netscapeText: String? = nil,
        exitCode: Int32? = nil,
        stdoutByteCount: Int? = nil,
        fileManager: FileManager = .default,
        date: Date = Date(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        let dir = logsDirectory(homeDirectory: homeDirectory, fileManager: fileManager)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let fileURL = dir.appendingPathComponent("ytdlp-\(formatter.string(from: date)).log")

        var sections: [String] = []
        sections.append("=== yt-dlp command ===")
        sections.append(commandLine(executable: executable, arguments: arguments))
        if let cookieFilePath, !cookieFilePath.isEmpty {
            sections.append("cookieFile=\(cookieFilePath)")
        } else {
            sections.append("cookieFile=(none)")
        }
        if let exitCode {
            sections.append("exitCode=\(exitCode)")
        }
        if let stdoutByteCount {
            sections.append("stdoutBytes=\(stdoutByteCount)")
        }

        sections.append("")
        sections.append("=== yt-dlp stderr ===")
        sections.append(stderr.isEmpty ? "(empty)" : stderr)

        if let netscapeText {
            sections.append("")
            sections.append("=== cookie flags (no values) ===")
            let flags = cookieFlagLines(fromNetscape: netscapeText)
            if flags.isEmpty {
                sections.append("(no cookies)")
            } else {
                sections.append(contentsOf: flags)
            }
            let missing = missingAuthCookieNames(inNetscape: netscapeText)
            sections.append("")
            sections.append("=== key auth cookies ===")
            if missing.isEmpty {
                sections.append("all present: \(keyAuthCookieNames.joined(separator: ", "))")
            } else {
                sections.append("missing: \(missing.joined(separator: ", "))")
                let present = Set(ExtensionCookiePayload.parseNetscapeText(netscapeText).map(\.name))
                let found = keyAuthCookieNames.filter { present.contains($0) }
                if !found.isEmpty {
                    sections.append("present: \(found.joined(separator: ", "))")
                }
            }
        }

        return writeLogBody(sections.joined(separator: "\n") + "\n", to: fileURL)
    }

    /// Log the real error after a cookie retry (type + description). Never logs cookie values.
    @discardableResult
    public static func writePostRetryErrorLog(
        error: Error,
        fileManager: FileManager = .default,
        date: Date = Date(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        let dir = logsDirectory(homeDirectory: homeDirectory, fileManager: fileManager)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let fileURL = dir.appendingPathComponent("post-retry-\(formatter.string(from: date)).log")

        let typeName = String(describing: type(of: error))
        let description: String
        if let downloadError = error as? DownloadError {
            description = downloadError.errorDescription ?? downloadError.shortMessage
        } else if let localized = error as? LocalizedError, let text = localized.errorDescription {
            description = text
        } else {
            description = String(describing: error)
        }

        var sections: [String] = []
        sections.append("=== post-cookie-retry error ===")
        sections.append("type=\(typeName)")
        if let downloadError = error as? DownloadError {
            sections.append("downloadError=\(String(describing: downloadError))")
            sections.append("requiresCookies=\(downloadError.requiresCookies)")
        }
        sections.append("description=\(description)")
        return writeLogBody(sections.joined(separator: "\n") + "\n", to: fileURL)
    }

    private static func writeLogBody(_ body: String, to fileURL: URL) -> URL? {
        do {
            try Data(body.utf8).write(to: fileURL, options: .atomic)
            return fileURL
        } catch {
            return nil
        }
    }

    private static func shellEscape(_ value: String) -> String {
        if value.isEmpty { return "''" }
        if value.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_./:@+=%,")).contains($0) }) {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
