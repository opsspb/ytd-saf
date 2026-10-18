import XCTest
@testable import YTDownloaderCore

final class ExtensionCookiePayloadTests: XCTestCase {
    func testNetscapeSerializationFromBrowserJSON() {
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
                session: true
            )
        ]

        let text = ExtensionCookiePayload.netscapeText(from: cookies)
        XCTAssertTrue(text.hasPrefix("# Netscape HTTP Cookie File"))
        let lines = text.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 3)

        XCTAssertTrue(lines[1].contains(".youtube.com"))
        XCTAssertTrue(lines[1].contains("TRUE\t/\tTRUE\t1900000000\tSID\tsecret-sid"))
        XCTAssertTrue(lines[2].contains("youtube.com\tFALSE\t/watch\tFALSE\t0\tsession\ttemp"))

        let roundTrip = ExtensionCookiePayload.parseNetscapeText(text)
        XCTAssertEqual(roundTrip.count, 2)
        XCTAssertEqual(roundTrip[0].name, "SID")
        XCTAssertEqual(roundTrip[0].value, "secret-sid")
        XCTAssertEqual(roundTrip[1].name, "session")
        XCTAssertEqual(roundTrip[1].session, true)
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
        XCTAssertEqual(loaded, text)
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
            lastError: .cookiesRequired,
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
            lastError: .cookiesRequired,
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
