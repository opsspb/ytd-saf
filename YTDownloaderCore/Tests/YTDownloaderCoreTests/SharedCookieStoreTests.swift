import XCTest
@testable import YTDownloaderCore

final class SharedCookieStoreTests: XCTestCase {
    func testWriteReadRoundTripInTempContainer() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytd-appgroup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let netscape = ExtensionCookiePayload.netscapeText(from: [
            BrowserCookie(name: "SID", value: "secret", domain: ".youtube.com")
        ])
        let ref = try SharedCookieStore.writeNetscape(
            videoId: "rBlesPXJV2E",
            netscapeText: netscape,
            containerURL: root
        )
        XCTAssertTrue(ref.hasPrefix("rBlesPXJV2E-"))
        XCTAssertEqual(
            SharedCookieStore.readNetscape(cookieRef: ref, containerURL: root),
            netscape
        )

        let attrs = try FileManager.default.attributesOfItem(
            atPath: root
                .appendingPathComponent(SharedCookieStore.directoryName)
                .appendingPathComponent("\(ref).txt")
                .path
        )
        XCTAssertEqual((attrs[.posixPermissions] as? NSNumber)?.intValue, 0o600)
    }

    func testResolvePrefersCookieRefOverURLPayload() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytd-appgroup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let netscape = "# Netscape HTTP Cookie File\n.youtube.com\tTRUE\t/\tTRUE\t0\tSID\tfrom-file"
        let ref = try SharedCookieStore.writeNetscape(
            videoId: "v1",
            netscapeText: netscape,
            containerURL: root
        )
        let urlPayload = ExtensionCookiePayload.encodeBase64URL(
            "# Netscape HTTP Cookie File\n.youtube.com\tTRUE\t/\tTRUE\t0\tSID\tfrom-url"
        )
        let resolved = SharedCookieStore.resolveNetscapePayload(
            cookieRef: ref,
            cookiesURLPayload: urlPayload,
            containerURL: root
        )
        XCTAssertEqual(resolved, netscape)
        XCTAssertTrue(resolved?.contains("from-file") == true)
    }

    func testResolveFallsBackToURLPayload() {
        let urlPayload = ExtensionCookiePayload.encodeBase64URL(
            "# Netscape HTTP Cookie File\n.youtube.com\tTRUE\t/\tTRUE\t0\tSID\tlegacy"
        )
        let resolved = SharedCookieStore.resolveNetscapePayload(
            cookieRef: nil,
            cookiesURLPayload: urlPayload,
            containerURL: FileManager.default.temporaryDirectory
                .appendingPathComponent("missing-\(UUID().uuidString)")
        )
        XCTAssertTrue(resolved?.contains("legacy") == true)
    }

    func testRejectsPathTraversalCookieRef() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ytd-appgroup-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        _ = try SharedCookieStore.writeNetscape(
            videoId: "ok",
            netscapeText: "# Netscape HTTP Cookie File\n",
            containerURL: root
        )
        XCTAssertNil(
            SharedCookieStore.readNetscape(cookieRef: "../escape", containerURL: root)
        )
    }

    func testRawNetscapeAcceptedByPayloadDecoder() {
        let raw = "# Netscape HTTP Cookie File\n.youtube.com\tTRUE\t/\tTRUE\t0\tSID\traw"
        XCTAssertTrue(ExtensionCookiePayload.looksLikeNetscape(raw))
        XCTAssertEqual(ExtensionCookiePayload.netscapeText(fromURLPayload: raw), raw)
    }

    func testContainerUnavailableWithoutAppGroup() {
        // On unsigned CI, the real App Group container is typically nil.
        // Writing without an injected container must throw when unavailable.
        if SharedCookieStore.containerURL() == nil {
            XCTAssertThrowsError(
                try SharedCookieStore.writeNetscape(
                    videoId: "x",
                    netscapeText: "# Netscape HTTP Cookie File\n"
                )
            ) { error in
                XCTAssertEqual(error as? SharedCookieStoreError, .containerUnavailable)
            }
        }
    }

    func testResolveAppGroupIDFromInfoPlist() {
        let teamPrefixed = SharedCookieStore.resolveAppGroupID(
            infoDictionary: [
                SharedCookieStore.appGroupIDInfoPlistKey: "4DVJSNGT52.com.ytdownloader.shared"
            ]
        )
        XCTAssertEqual(teamPrefixed, "4DVJSNGT52.com.ytdownloader.shared")
    }

    func testResolveAppGroupIDFallsBackWhenMissingOrUnexpanded() {
        XCTAssertEqual(
            SharedCookieStore.resolveAppGroupID(infoDictionary: [:]),
            SharedCookieStore.appGroupIDSuffix
        )
        XCTAssertEqual(
            SharedCookieStore.resolveAppGroupID(infoDictionary: [
                SharedCookieStore.appGroupIDInfoPlistKey:
                    "$(TeamIdentifierPrefix)com.ytdownloader.shared"
            ]),
            SharedCookieStore.appGroupIDSuffix
        )
        XCTAssertEqual(
            SharedCookieStore.resolveAppGroupID(infoDictionary: [
                SharedCookieStore.appGroupIDInfoPlistKey: "   "
            ]),
            SharedCookieStore.appGroupIDSuffix
        )
    }

    func testResolveAppGroupIDRejectsLegacyGroupPrefixHardcode() {
        // Entitlements use team-prefixed form; runtime must not invent `group.`.
        let id = SharedCookieStore.resolveAppGroupID(infoDictionary: [:])
        XCTAssertFalse(id.hasPrefix("group."))
        XCTAssertEqual(id, "com.ytdownloader.shared")
    }
}
