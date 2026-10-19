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

    /// One compact line per format (no URLs, no cookies).
    public static func formatTableLines(from formats: [VideoFormat]) -> [String] {
        formats.map { format in
            [
                format.formatId,
                format.ext,
                format.protocolName ?? "",
                format.vcodec ?? "null",
                format.acodec ?? "null",
                format.height.map(String.init) ?? "",
                format.fps.map { String($0) } ?? "",
                format.tbr.map { String($0) } ?? "",
                format.formatNote ?? ""
            ].joined(separator: "\t")
        }
    }

    /// When the separable picker fails: format table + which fallback spec will be used.
    /// Optionally writes a URL-stripped copy of the -J JSON next to the log (mode 0600).
    @discardableResult
    public static func writeFormatPickerFallbackLog(
        info: YTDLPInfo,
        fallbackSpec: String,
        reason: String = "no separable video+audio pair",
        saveInfoJSON: Bool = true,
        fileManager: FileManager = .default,
        date: Date = Date(),
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> URL? {
        let dir = logsDirectory(homeDirectory: homeDirectory, fileManager: fileManager)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss-SSS"
        let stamp = formatter.string(from: date)
        let fileURL = dir.appendingPathComponent("format-picker-\(stamp).log")

        var sections: [String] = []
        sections.append("=== format picker fallback ===")
        sections.append("id=\(info.id)")
        sections.append("title=\(info.title)")
        sections.append("reason=\(reason)")
        sections.append("fallbackSpec=\(fallbackSpec)")
        sections.append("formatCount=\(info.formats.count)")
        sections.append("")
        sections.append("=== formats (format_id, ext, protocol, vcodec, acodec, height, fps, tbr, format_note) ===")
        let table = formatTableLines(from: info.formats)
        if table.isEmpty {
            sections.append("(none)")
        } else {
            sections.append(contentsOf: table)
        }

        let logURL = writeLogBody(sections.joined(separator: "\n") + "\n", to: fileURL)

        if saveInfoJSON {
            let jsonURL = dir.appendingPathComponent("format-picker-\(stamp).json")
            if let data = try? strippedInfoJSON(info) {
                writeData(data, to: jsonURL, mode: 0o600, fileManager: fileManager)
            }
        }

        return logURL
    }

    /// Encode info without URL-bearing fields (webpage/original URLs and any accidental extras).
    public static func strippedInfoJSON(_ info: YTDLPInfo) throws -> Data {
        let formats: [[String: Any]] = info.formats.map { format in
            var row: [String: Any] = [
                "format_id": format.formatId,
                "ext": format.ext
            ]
            if let v = format.protocolName { row["protocol"] = v }
            if let v = format.vcodec { row["vcodec"] = v } else { row["vcodec"] = NSNull() }
            if let v = format.acodec { row["acodec"] = v } else { row["acodec"] = NSNull() }
            if let v = format.width { row["width"] = v }
            if let v = format.height { row["height"] = v }
            if let v = format.fps { row["fps"] = v }
            if let v = format.tbr { row["tbr"] = v }
            if let v = format.vbr { row["vbr"] = v }
            if let v = format.abr { row["abr"] = v }
            if let v = format.formatNote { row["format_note"] = v }
            if let v = format.resolution { row["resolution"] = v }
            if let v = format.language { row["language"] = v }
            if let v = format.languagePreference { row["language_preference"] = v }
            return row
        }
        let payload: [String: Any] = [
            "id": info.id,
            "title": info.title,
            "formats": formats
        ]
        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    @discardableResult
    private static func writeData(
        _ data: Data,
        to fileURL: URL,
        mode: Int,
        fileManager: FileManager
    ) -> URL? {
        do {
            try data.write(to: fileURL, options: .atomic)
            try fileManager.setAttributes(
                [.posixPermissions: NSNumber(value: Int16(mode))],
                ofItemAtPath: fileURL.path
            )
            return fileURL
        } catch {
            return nil
        }
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
