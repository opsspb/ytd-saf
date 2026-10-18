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

/// User-facing copy for queue status + NSAlert (no cookie values).
public struct CookieFailureGuidance: Equatable, Sendable {
    public let kind: CookieFailureKind
    public let statusText: String
    public let alertTitle: String
    public let alertMessage: String
    public let showsOpenSettings: Bool

    public init(kind: CookieFailureKind) {
        self.kind = kind
        switch kind {
        case .fullDiskAccessRequired:
            statusText = "Allow Full Disk Access for Safari cookies (Settings → Privacy)"
            alertTitle = "Full Disk Access Required"
            alertMessage = """
            This video needs sign-in cookies. YTDownloader could not read Safari’s cookie store because Full Disk Access is not granted (the cookie database is TCC-protected).

            Prefer: use the Safari extension — when prompted, allow cookie access for YouTube/VK, then click YD again while signed in.

            Fallback: System Settings → Privacy & Security → Full Disk Access → enable YTDownloader, then restart the app.
            """
            showsOpenSettings = true
        case .extensionCookiesUnavailable:
            statusText = "Allow Safari cookie access for the extension, then retry while signed in"
            alertTitle = "Cookies Required"
            alertMessage = """
            This video needs you to be signed in. The Safari extension should send cookies with the download (Safari will ask for cookie permission).

            Make sure you are signed in to YouTube or VK in Safari, allow cookie access when prompted, then click YD again.

            Alternatively enable Cookie Mode → Safari and grant Full Disk Access in System Settings.
            """
            showsOpenSettings = true
        case .cookiesInsufficient:
            statusText = "Sign in to the site in Safari, allow extension cookies, then retry"
            alertTitle = "Sign-In Still Required"
            alertMessage = """
            Cookies were provided but the download still needs a signed-in session (or the cookies were incomplete).

            Sign in to YouTube or VK in Safari, confirm the extension may access cookies, then click YD again.
            """
            showsOpenSettings = false
        }
    }
}

public enum CookieAccessDiagnoser {
    public static let fullDiskAccessSettingsURL =
        "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"

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
        safariStoreReadable: Bool? = nil
    ) -> CookieFailureGuidance {
        CookieFailureGuidance(
            kind: classify(
                hadExtensionCookies: hadExtensionCookies,
                cookieMode: cookieMode,
                usedCookies: usedCookies,
                lastError: lastError,
                stderr: stderr,
                safariStoreReadable: safariStoreReadable
            )
        )
    }
}
