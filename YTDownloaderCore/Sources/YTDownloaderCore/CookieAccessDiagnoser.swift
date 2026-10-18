import Foundation

/// Why a sign-in/age-gated download cannot proceed with cookies.
public enum CookieFailureKind: Equatable, Sendable {
    /// No extension cookie payload and cookie mode cannot supply cookies.
    case extensionCookiesUnavailable
    /// Safari cookie DB is TCC-blocked (Full Disk Access missing).
    case fullDiskAccessRequired
    /// Cookies were tried but yt-dlp still needs a signed-in session.
    case cookiesInsufficient
}

/// Primary button action for the native cookie-failure alert.
public enum CookieFailurePrimaryAction: Equatable, Sendable {
    case none
    case openSafariExtensionSettings
    case openFullDiskAccessSettings
}

/// User-facing copy for queue status + NSAlert (no cookie values).
public struct CookieFailureGuidance: Equatable, Sendable {
    public let kind: CookieFailureKind
    public let statusText: String
    public let alertTitle: String
    public let alertMessage: String
    public let primaryButtonTitle: String?
    public let primaryAction: CookieFailurePrimaryAction

    /// True when the alert offers a settings deep-link (plus Cancel).
    public var showsOpenSettings: Bool {
        primaryAction != .none
    }

    public init(
        kind: CookieFailureKind,
        missingAuthCookies: [String] = [],
        lastErrorLine: String? = nil
    ) {
        self.kind = kind
        switch kind {
        case .fullDiskAccessRequired:
            statusText = "Allow Full Disk Access for Safari cookies (Settings → Privacy)"
            alertTitle = "Full Disk Access Required"
            alertMessage = """
            This video needs sign-in cookies. YTDownloader could not read Safari’s cookie store because Full Disk Access is not granted.

            Prefer: click YD in Safari, allow cookie access when prompted, then retry while signed in.

            Fallback: System Settings → Privacy & Security → Full Disk Access → enable YTDownloader, then restart the app.
            """
            primaryButtonTitle = "Open Privacy Settings"
            primaryAction = .openFullDiskAccessSettings
        case .extensionCookiesUnavailable:
            statusText = "Allow Safari cookie access for the extension, then retry while signed in"
            alertTitle = "Allow Cookie Access in Safari"
            alertMessage = """
            This video needs you to be signed in. Click YD again on the video page — Safari should ask for access to YouTube, Google, or VK cookies. Choose Allow, then click YD once more while signed in.

            If Safari never prompts: open Safari Extension Settings, select YTDownloader, allow youtube.com (and google.com for YouTube), then click YD again.
            """
            primaryButtonTitle = "Open Safari Extension Settings"
            primaryAction = .openSafariExtensionSettings
        case .cookiesInsufficient:
            let detail = Self.insufficientDetail(
                missingAuthCookies: missingAuthCookies,
                lastErrorLine: lastErrorLine
            )
            statusText = detail.status
            alertTitle = "Sign-In Still Required"
            alertMessage = detail.alert
            primaryButtonTitle = nil
            primaryAction = .none
        }
    }

    private static func insufficientDetail(
        missingAuthCookies: [String],
        lastErrorLine: String?
    ) -> (status: String, alert: String) {
        var statusParts: [String] = []
        var alertParts: [String] = []

        if !missingAuthCookies.isEmpty {
            let list = missingAuthCookies.joined(separator: ", ")
            statusParts.append("Missing auth cookies: \(list)")
            alertParts.append(
                "The cookie jar from Safari is missing key auth cookies (\(list)). Sign in to YouTube in Safari, click YD, allow cookie access if prompted, then retry."
            )
        }

        if let lastErrorLine, !lastErrorLine.isEmpty {
            statusParts.append(lastErrorLine)
            alertParts.append("yt-dlp reported:\n\(lastErrorLine)")
        }

        if statusParts.isEmpty {
            statusParts.append("Sign in to the site in Safari, allow extension cookies, then retry")
            alertParts.append(
                """
                Cookies were provided but the download still needs a signed-in session (or the cookies were incomplete).

                Sign in to YouTube or VK in Safari, click YD, allow cookie access if prompted, then retry.
                """
            )
        } else if missingAuthCookies.isEmpty {
            alertParts.append(
                "Cookies were provided but yt-dlp still rejected the session. Sign in to the site in Safari, click YD again, then retry."
            )
        }

        return (statusParts.joined(separator: "\n"), alertParts.joined(separator: "\n\n"))
    }
}

public enum CookieAccessDiagnoser {
    public static let fullDiskAccessSettingsURL =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

    /// Opens Safari’s Extensions pane when supported.
    public static let safariExtensionSettingsURL =
        "x-apple.systempreferences:com.apple.Safari-Settings.extension"

    /// Candidate Safari cookie DB paths (Containers store is TCC-protected).
    public static var safariCookieDatabasePaths: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return [
            home.appendingPathComponent(
                "Library/Containers/com.apple.Safari/Data/Library/Cookies/Cookies.binarycookies"
            ),
            home.appendingPathComponent("Library/Cookies/Cookies.binarycookies")
        ]
    }

    /// True when at least one Safari cookie DB is readable (FDA granted or legacy path).
    public static func canReadSafariCookieStore(
        fileManager: FileManager = .default
    ) -> Bool {
        for path in safariCookieDatabasePaths {
            if fileManager.isReadableFile(atPath: path.path) {
                return true
            }
            // Probe open: isReadableFile can be wrong under some TCC states.
            if let handle = try? FileHandle(forReadingFrom: path) {
                try? handle.close()
                return true
            }
        }
        return false
    }

    /// True when stderr looks like a TCC / permission failure reading browser cookies.
    public static func looksLikeCookieStorePermissionError(_ output: String) -> Bool {
        let lower = output.lowercased()
        let needles = [
            "operation not permitted",
            "permission denied",
            "cookies.binarycookies",
            "could not copy chrome cookie",
            "failed to load cookies",
            "could not find cookie file",
            "unable to read cookies",
            "errno 1",
            "eperm"
        ]
        return needles.contains { lower.contains($0) }
    }

    public static func classify(
        hadExtensionCookies: Bool,
        cookieMode: CookieMode,
        usedCookies: Bool,
        lastError: DownloadError?,
        stderr: String? = nil,
        safariStoreReadable: Bool? = nil
    ) -> CookieFailureKind {
        let readable = safariStoreReadable ?? canReadSafariCookieStore()
        let permissionHint = stderr.map(looksLikeCookieStorePermissionError) ?? false

        if usedCookies, hadExtensionCookies {
            return .cookiesInsufficient
        }

        if cookieMode == .safari, (!readable || permissionHint) {
            return .fullDiskAccessRequired
        }

        if let stderr, looksLikeCookieStorePermissionError(stderr) {
            return .fullDiskAccessRequired
        }

        if hadExtensionCookies == false, cookieMode == .none {
            return .extensionCookiesUnavailable
        }

        if usedCookies {
            return .cookiesInsufficient
        }

        if cookieMode == .safari {
            return readable ? .cookiesInsufficient : .fullDiskAccessRequired
        }

        if cookieMode == .file {
            return .cookiesInsufficient
        }

        return .extensionCookiesUnavailable
    }

    public static func guidance(
        hadExtensionCookies: Bool,
        cookieMode: CookieMode,
        usedCookies: Bool,
        lastError: DownloadError?,
        stderr: String? = nil,
        safariStoreReadable: Bool? = nil,
        netscapeText: String? = nil
    ) -> CookieFailureGuidance {
        let kind = classify(
            hadExtensionCookies: hadExtensionCookies,
            cookieMode: cookieMode,
            usedCookies: usedCookies,
            lastError: lastError,
            stderr: stderr,
            safariStoreReadable: safariStoreReadable
        )
        let missing: [String]
        if let netscapeText {
            missing = YTDLPDiagnostics.missingAuthCookieNames(inNetscape: netscapeText)
        } else {
            missing = []
        }
        let errorLine = stderr.flatMap { YTDLPDiagnostics.lastErrorLine(in: $0) }
            ?? lastError.flatMap { error in
                error.errorDescription.flatMap { YTDLPDiagnostics.lastErrorLine(in: $0) }
            }
        return CookieFailureGuidance(
            kind: kind,
            missingAuthCookies: kind == .cookiesInsufficient ? missing : [],
            lastErrorLine: kind == .cookiesInsufficient ? errorLine : nil
        )
    }
}
