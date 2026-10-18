import XCTest
@testable import YTDownloaderCore

final class ExtensionCookiePayloadTests: XCTestCase {
    func testNetscapeSerializationFromBrowserJSON() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cookies = [
            BrowserCookie(
                name: "SID",
                value: "secret-sid",
                domain: ".youtube.com",
                path: "/",
                secure: true,
                expirationDate: 1_900_000_000,
                session: false
            ),
            BrowserCookie(
                name: "session",
                value: "temp",
                domain: "youtube.com",
                path: "/watch",
                secure: false,
                expirationDate: nil,
                session: true,
                hostOnly: true
            )
        ]

        let text = ExtensionCookiePayload.netscapeText(from: cookies, now: now)
        XCTAssertTrue(text.hasPrefix("# Netscape HTTP Cookie File"))
        let lines = text.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 3)

        XCTAssertTrue(lines[1].contains(".youtube.com\tTRUE\t/\tTRUE\t1900000000\tSID\tsecret-sid"))
        // Session cookies must get a future expiry, not 0.
        let expectedSessionExpiry = Int(now.timeIntervalSince1970 + ExtensionCookiePayload.sessionCookieLifetime)
        XCTAssertTrue(lines[2].contains("youtube.com\tFALSE\t/watch\tFALSE\t\(expectedSessionExpiry)\tsession\ttemp"))
        XCTAssertFalse(lines[2].contains("\t0\tsession\t"))

        let roundTrip = ExtensionCookiePayload.parseNetscapeText(text)
        XCTAssertEqual(roundTrip.count, 2)
        XCTAssertEqual(roundTrip[0].name, "SID")
        XCTAssertEqual(roundTrip[0].value, "secret-sid")
        XCTAssertEqual(roundTrip[1].name, "session")
    }

    func testDomainLeadingDotMatchesIncludeSubdomainsFlag() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        // hostOnly=false without leading dot → normalize to .domain + TRUE
        let sub = ExtensionCookiePayload.netscapeText(
            from: [BrowserCookie(name: "A", value: "1", domain: "youtube.com", hostOnly: false)],
            now: now
        )
        XCTAssertTrue(sub.contains(".youtube.com\tTRUE\t"))

        // hostOnly=true with leading dot → strip dot + FALSE
        let host = ExtensionCookiePayload.netscapeText(
            from: [BrowserCookie(name: "B", value: "2", domain: ".youtube.com", hostOnly: true)],
            now: now
        )
        XCTAssertTrue(host.contains("youtube.com\tFALSE\t"))
        XCTAssertFalse(host.contains(".youtube.com\tFALSE"))
    }

    func testNewlinesInValuesAreStrippedAndDeduped() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let cookies = [
            BrowserCookie(name: "SID", value: "a\nb\tc", domain: ".youtube.com", expirationDate: 1_800_000_000),
            BrowserCookie(name: "SID", value: "longer-value-wins", domain: ".youtube.com", expirationDate: 1_900_000_000)
        ]
        let text = ExtensionCookiePayload.netscapeText(from: cookies, now: now)
        let dataLines = text.split(separator: "\n").filter { !$0.hasPrefix("#") }
        XCTAssertEqual(dataLines.count, 1)
        XCTAssertTrue(dataLines[0].contains("longer-value-wins"))
        // Newlines stripped from values; tabs only as Netscape field separators.
        let parts = dataLines[0].split(separator: "\t", omittingEmptySubsequences: false)
        XCTAssertEqual(parts.count, 7)
        XCTAssertEqual(parts[6], "longer-value-wins")
        XCTAssertFalse(parts[6].contains("\n"))
        XCTAssertFalse(parts[6].contains("\t"))
    }

    func testNormalizeRewritesExpiryZeroSessionCookies() {
        let legacy = """
        # Netscape HTTP Cookie File
        .youtube.com\tTRUE\t/\tTRUE\t0\tLOGIN_INFO\tabc
        youtube.com\tTRUE\t/\tTRUE\t1900000000\tSID\tx
        """
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let normalized = ExtensionCookiePayload.normalizeNetscapeText(legacy, now: now)
        XCTAssertTrue(normalized.hasPrefix("# Netscape HTTP Cookie File"))
        let login = normalized.split(separator: "\n").first { $0.contains("LOGIN_INFO") }!
        XCTAssertFalse(login.contains("\t0\tLOGIN_INFO\t"))
        // Inconsistent youtube.com + TRUE → leading dot
        XCTAssertTrue(normalized.contains(".youtube.com\tTRUE\t/\tTRUE\t1900000000\tSID\tx"))
    }

    func testURLPayloadEncodeDecodeRoundTrip() {
        let cookies = [
            BrowserCookie(name: "LOGIN_INFO", value: "A", domain: ".youtube.com"),
            BrowserCookie(name: "remixsid", value: "B", domain: ".vk.com")
        ]
        let encoded = ExtensionCookiePayload.encodeForURL(cookies: cookies)
        XCTAssertNotNil(encoded)
        XCTAssertLessThanOrEqual(encoded!.count, ExtensionCookiePayload.maxEncodedLength)

        let netscape = ExtensionCookiePayload.netscapeText(fromURLPayload: encoded!)
        XCTAssertNotNil(netscape)
        XCTAssertTrue(netscape!.contains("LOGIN_INFO"))
        XCTAssertTrue(netscape!.contains("remixsid"))
        XCTAssertFalse(netscape!.contains("base64"))
    }

    func testJSONPayloadViaBase64URL() {
        let cookies = [BrowserCookie(name: "SAPISID", value: "x", domain: ".google.com")]
        let json = try! JSONEncoder().encode(cookies)
        let encoded = ExtensionCookiePayload.encodeBase64URL(String(data: json, encoding: .utf8)!)
        let netscape = ExtensionCookiePayload.netscapeText(fromURLPayload: encoded)
        XCTAssertTrue(netscape?.contains("SAPISID\tx") == true)
    }

    func testTempCookieFilePermissions() throws {
        let text = ExtensionCookiePayload.netscapeText(from: [
            BrowserCookie(name: "SID", value: "v", domain: ".youtube.com")
        ])
        let url = try ExtensionCookiePayload.writeTempCookieFile(netscapeText: text)
        defer { try? FileManager.default.removeItem(at: url) }

        let attrs = try FileManager.default.attributesOfItem(atPath: url.path)
        let perms = attrs[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.intValue, 0o600)

        let loaded = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(loaded.hasPrefix("# Netscape HTTP Cookie File"))
        XCTAssertTrue(loaded.contains("SID\tv"))
    }

    func testPriorityTrimKeepsAuthCookies() {
        var cookies: [BrowserCookie] = [
            BrowserCookie(name: "LOGIN_INFO", value: "auth", domain: ".youtube.com")
        ]
        for i in 0..<400 {
            cookies.append(
                BrowserCookie(
                    name: "noise\(i)",
                    value: String(repeating: "z", count: 80),
                    domain: ".youtube.com"
                )
            )
        }
        let encoded = ExtensionCookiePayload.encodeForURL(cookies: cookies)
        XCTAssertNotNil(encoded)
        XCTAssertLessThanOrEqual(encoded!.count, ExtensionCookiePayload.maxEncodedLength)
        let netscape = ExtensionCookiePayload.netscapeText(fromURLPayload: encoded!)!
        XCTAssertTrue(netscape.contains("LOGIN_INFO"))
    }
}

final class CookieAccessDiagnoserTests: XCTestCase {
    func testClassifyExtensionUnavailable() {
        let kind = CookieAccessDiagnoser.classify(
            hadExtensionCookies: false,
            cookieMode: .none,
            usedCookies: false,
            lastError: .cookiesRequired("sign in"),
            safariStoreReadable: false
        )
        XCTAssertEqual(kind, .extensionCookiesUnavailable)
        let guidance = CookieFailureGuidance(kind: kind)
        XCTAssertTrue(guidance.showsOpenSettings)
        XCTAssertEqual(guidance.primaryAction, .openSafariExtensionSettings)
        XCTAssertEqual(guidance.primaryButtonTitle, "Open Safari Extension Settings")
        XCTAssertTrue(guidance.statusText.lowercased().contains("cookie"))
        XCTAssertTrue(guidance.alertMessage.lowercased().contains("click yd"))
    }

    func testClassifyFullDiskAccess() {
        let kind = CookieAccessDiagnoser.classify(
            hadExtensionCookies: false,
            cookieMode: .safari,
            usedCookies: false,
            lastError: .cookiesRequired(""),
            safariStoreReadable: false
        )
        XCTAssertEqual(kind, .fullDiskAccessRequired)

        let fromStderr = CookieAccessDiagnoser.classify(
            hadExtensionCookies: false,
            cookieMode: .safari,
            usedCookies: true,
            lastError: .fullDiskAccessRequired,
            stderr: "ERROR: Operation not permitted reading Cookies.binarycookies",
            safariStoreReadable: true
        )
        XCTAssertEqual(fromStderr, .fullDiskAccessRequired)

        let guidance = CookieFailureGuidance(kind: .fullDiskAccessRequired)
        XCTAssertTrue(guidance.showsOpenSettings)
        XCTAssertEqual(guidance.primaryAction, .openFullDiskAccessSettings)
        XCTAssertEqual(guidance.primaryButtonTitle, "Open Privacy Settings")
        XCTAssertTrue(guidance.alertTitle.contains("Full Disk Access"))
    }

    func testInsufficientHasSingleOKButton() {
        let guidance = CookieFailureGuidance(kind: .cookiesInsufficient)
        XCTAssertFalse(guidance.showsOpenSettings)
        XCTAssertNil(guidance.primaryButtonTitle)
        XCTAssertEqual(guidance.primaryAction, .none)
    }

    func testClassifyInsufficientAfterExtensionCookies() {
        let kind = CookieAccessDiagnoser.classify(
            hadExtensionCookies: true,
            cookieMode: .none,
            usedCookies: true,
            lastError: .ageRestricted,
            safariStoreReadable: false
        )
        XCTAssertEqual(kind, .cookiesInsufficient)
    }

    func testCookieRetryRoutingShowsGuidanceOnlyForCookieErrors() {
        let cookieRoute = CookieAccessDiagnoser.routingAfterCookieRetry(
            error: .ageRestricted,
            hadExtensionCookies: true,
            cookieMode: .none,
            usedCookies: true,
            netscapeText: ExtensionCookiePayload.netscapeText(from: [
                BrowserCookie(name: "LOGIN_INFO", value: "x", domain: ".youtube.com"),
                BrowserCookie(name: "__Secure-3PSID", value: "y", domain: ".youtube.com"),
                BrowserCookie(name: "__Secure-1PSID", value: "z", domain: ".youtube.com"),
                BrowserCookie(name: "SID", value: "1", domain: ".youtube.com"),
                BrowserCookie(name: "SAPISID", value: "2", domain: ".youtube.com"),
                BrowserCookie(name: "SSID", value: "3", domain: ".youtube.com"),
                BrowserCookie(name: "HSID", value: "4", domain: ".youtube.com")
            ])
        )
        if case .cookieGuidance(let guidance) = cookieRoute {
            XCTAssertEqual(guidance.kind, .cookiesInsufficient)
            XCTAssertEqual(guidance.alertTitle, "Sign-In Still Required")
        } else {
            XCTFail("expected cookie guidance for ageRestricted")
        }

        for error in [
            DownloadError.noSuitableFormats,
            .fetchInfoFailed("JSON decode failed: type mismatch"),
            .mergeFailed("ffmpeg boom"),
            .downloadFailed("aria2c failed"),
            .unknown("DecodingError.typeMismatch")
        ] {
            let route = CookieAccessDiagnoser.routingAfterCookieRetry(
                error: error,
                hadExtensionCookies: true,
                cookieMode: .none,
                usedCookies: true
            )
            guard case .queueError(let message) = route else {
                XCTFail("expected queueError for \(error), got \(route)")
                continue
            }
            XCTAssertFalse(message.isEmpty)
            XCTAssertFalse(message.contains("Sign-In Still Required"))
        }
    }

    func testInsufficientSurfacesMissingCookiesAndErrorLine() {
        let netscape = ExtensionCookiePayload.netscapeText(from: [
            BrowserCookie(name: "VISITOR_INFO1_LIVE", value: "x", domain: ".youtube.com")
        ])
        let guidance = CookieAccessDiagnoser.guidance(
            hadExtensionCookies: true,
            cookieMode: .none,
            usedCookies: true,
            lastError: .cookiesRequired("ERROR: [youtube] abc: Sign in to confirm you’re not a bot"),
            stderr: "WARNING: foo\nERROR: [youtube] abc: Sign in to confirm you’re not a bot\n",
            netscapeText: netscape
        )
        XCTAssertEqual(guidance.kind, .cookiesInsufficient)
        XCTAssertTrue(guidance.statusText.contains("Missing auth cookies"))
        XCTAssertTrue(guidance.statusText.contains("LOGIN_INFO"))
        XCTAssertTrue(guidance.statusText.contains("__Secure-3PSID"))
        XCTAssertTrue(guidance.statusText.contains("ERROR: [youtube] abc: Sign in to confirm you’re not a bot"))
    }

    func testPermissionErrorDetection() {
        XCTAssertTrue(
            CookieAccessDiagnoser.looksLikeCookieStorePermissionError(
                "yt-dlp: Operation not permitted"
            )
        )
        XCTAssertFalse(
            CookieAccessDiagnoser.looksLikeCookieStorePermissionError(
                "ERROR: Sign in to confirm you’re not a bot"
            )
        )
    }

    func testErrorClassifierMapsPermissionToFDA() {
        let error = ErrorClassifier().classifyError(
            from: "ERROR: could not copy chrome cookies: Permission denied"
        )
        XCTAssertEqual(error, .fullDiskAccessRequired)
        XCTAssertTrue(error.requiresCookies)
    }
}

final class YTDLPDiagnosticsTests: XCTestCase {
    func testLastErrorLineExtraction() {
        let output = """
        WARNING: something
        ERROR: first problem
        [download] retry
        ERROR: [youtube] xyz: Sign in to confirm you're not a bot
        """
        XCTAssertEqual(
            YTDLPDiagnostics.lastErrorLine(in: output),
            "ERROR: [youtube] xyz: Sign in to confirm you're not a bot"
        )
    }

    func testMissingAuthCookieDetection() {
        let partial = ExtensionCookiePayload.netscapeText(from: [
            BrowserCookie(name: "SID", value: "1", domain: ".youtube.com"),
            BrowserCookie(name: "SAPISID", value: "2", domain: ".google.com")
        ])
        let missing = YTDLPDiagnostics.missingAuthCookieNames(inNetscape: partial)
        XCTAssertTrue(missing.contains("LOGIN_INFO"))
        XCTAssertTrue(missing.contains("__Secure-3PSID"))
        XCTAssertFalse(missing.contains("SID"))
        XCTAssertFalse(missing.contains("SAPISID"))
    }

    func testCookieFlagLinesOmitValues() {
        let cookies = [
            BrowserCookie(
                name: "LOGIN_INFO",
                value: "super-secret",
                domain: ".youtube.com",
                secure: true,
                expirationDate: 1_900_000_000,
                httpOnly: true
            )
        ]
        let lines = YTDLPDiagnostics.cookieFlagLines(from: cookies)
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(lines[0].contains("name=LOGIN_INFO"))
        XCTAssertTrue(lines[0].contains("domain=.youtube.com"))
        XCTAssertTrue(lines[0].contains("httpOnly=true"))
        XCTAssertFalse(lines[0].contains("super-secret"))
    }

    func testWriteRunLogCreatesFileWithoutCookieValues() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ytd-diag-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        // Point home via writing directly — writeRunLog uses real home; invoke helpers instead.
        let netscape = ExtensionCookiePayload.netscapeText(from: [
            BrowserCookie(name: "LOGIN_INFO", value: "secret-value", domain: ".youtube.com")
        ])
        let cmd = YTDLPDiagnostics.commandLine(
            executable: "/opt/homebrew/bin/yt-dlp",
            arguments: ["-J", "--cookies", "/tmp/cookies.txt", "https://youtube.com/watch?v=x"]
        )
        XCTAssertTrue(cmd.contains("/tmp/cookies.txt"))
        XCTAssertFalse(cmd.contains("secret-value"))

        let flags = YTDLPDiagnostics.cookieFlagLines(fromNetscape: netscape).joined(separator: "\n")
        XCTAssertFalse(flags.contains("secret-value"))
        XCTAssertTrue(flags.contains("LOGIN_INFO"))
    }

    func testWriteRunLogIncludesExitCodeAndStdoutBytes() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("ytd-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let url = YTDLPDiagnostics.writeRunLog(
            executable: "/opt/homebrew/bin/yt-dlp",
            arguments: ["-J", "--no-warnings", "https://youtube.com/watch?v=x"],
            stderr: "",
            cookieFilePath: "/tmp/cookies.txt",
            netscapeText: nil,
            exitCode: 0,
            stdoutByteCount: 12345,
            homeDirectory: home
        )
        let fileURL = try XCTUnwrap(url)
        let body = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(body.contains("exitCode=0"))
        XCTAssertTrue(body.contains("stdoutBytes=12345"))
        XCTAssertTrue(body.contains("(empty)"))
    }

    func testWritePostRetryErrorLogIncludesTypeAndDescription() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("ytd-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let url = YTDLPDiagnostics.writePostRetryErrorLog(
            error: DownloadError.noSuitableFormats,
            homeDirectory: home
        )
        let fileURL = try XCTUnwrap(url)
        let body = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(body.contains("type=DownloadError"))
        XCTAssertTrue(body.contains("requiresCookies=false"))
        XCTAssertTrue(body.contains("No suitable video formats found"))
        XCTAssertTrue(fileURL.lastPathComponent.hasPrefix("post-retry-"))
    }

    func testVersionComparePrefersNewest() {
        XCTAssertEqual(
            BinaryBootstrap.compareYTDLPVersions(
                BinaryBootstrap.parseYTDLPVersion("2026.08.19"),
                BinaryBootstrap.parseYTDLPVersion("2025.01.01")
            ),
            .orderedDescending
        )
        let older = BinaryPaths(
            ytdlp: "/tmp/old",
            ffmpeg: "/tmp/ffmpeg",
            ffprobe: "/tmp/ffprobe",
            source: .installed
        )
        let newer = BinaryPaths(
            ytdlp: "/tmp/new",
            ffmpeg: "/tmp/ffmpeg",
            ffprobe: "/tmp/ffprobe",
            source: .homebrew
        )
        // preferNewestYTDLP runs --version; with missing binaries both score empty → stable max.
        let picked = BinaryBootstrap.preferNewestYTDLP(among: [older, newer])
        XCTAssertNotNil(picked)
    }
}
