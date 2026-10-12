import XCTest
@testable import YTDownloaderCore

final class DownloadSettingsTests: XCTestCase {
    func testOldSettingsJSONGetsWindowAndLoginDefaults() throws {
        let json = """
        {"downloadDirectory":"~/Downloads","cookieMode":"none","maxConcurrentDownloads":2}
        """.data(using: .utf8)!
        let settings = try JSONDecoder().decode(DownloadSettings.self, from: json)
        XCTAssertEqual(settings.maxConcurrentDownloads, 2)
        XCTAssertFalse(settings.showWindowOnDownloadStart)
        XCTAssertFalse(settings.launchAtLogin)
    }

    func testNewSettingsRoundTrip() throws {
        let original = DownloadSettings(
            downloadDirectory: "/tmp/dl",
            cookieMode: .file,
            cookieFilePath: "/tmp/cookies.txt",
            maxConcurrentDownloads: 3,
            showWindowOnDownloadStart: true,
            launchAtLogin: true
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(DownloadSettings.self, from: data)
        XCTAssertEqual(decoded, original)
    }
}

final class AppIconCatalogTests: XCTestCase {
    func testAppIconPNGsExistAndAreNotTiny() throws {
        let iconset = repoRoot()
            .appendingPathComponent("YTDownloader/Resources/Assets.xcassets/AppIcon.appiconset")
        let required = [
            "icon_16x16.png", "icon_16x16@2x.png",
            "icon_32x32.png", "icon_32x32@2x.png",
            "icon_128x128.png", "icon_128x128@2x.png",
            "icon_256x256.png", "icon_256x256@2x.png",
            "icon_512x512.png", "icon_512x512@2x.png"
        ]
        for name in required {
            let url = iconset.appendingPathComponent(name)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "missing \(name)")
            let size = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber
            XCTAssertGreaterThan(size?.intValue ?? 0, 200, name)
        }
    }

    func testInfoPlistDeclaresAccessoryAndIconName() throws {
        let plistURL = repoRoot().appendingPathComponent("YTDownloader/YTDownloader/Info.plist")
        let data = try Data(contentsOf: plistURL)
        let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        XCTAssertEqual(plist?["LSUIElement"] as? Bool, true)
        XCTAssertEqual(plist?["CFBundleIconName"] as? String, "AppIcon")
        XCTAssertEqual(plist?["CFBundleIconFile"] as? String, "YTDownloader")
    }

    func testStandaloneIcnsExists() {
        let icns = repoRoot().appendingPathComponent("YTDownloader/Resources/AppIcon.icns")
        XCTAssertTrue(FileManager.default.fileExists(atPath: icns.path))
    }

    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
    }
}
