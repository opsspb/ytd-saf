import XCTest
@testable import YTDownloaderCore

final class AppURLTests: XCTestCase {
    func testShowQueueVariants() {
        XCTAssertEqual(AppURL.parse("ytdownloader://show-queue"), .showQueue)
        XCTAssertEqual(AppURL.parse("ytdownloader://show-queue/"), .showQueue)
        XCTAssertEqual(AppURL.parse("ytdownloader://queue"), .showQueue)
        XCTAssertEqual(AppURL.parse(URL(string: "ytdownloader://show-queue")!), .showQueue)
    }

    func testShowSettings() {
        XCTAssertEqual(AppURL.parse("ytdownloader://settings"), .showSettings)
        XCTAssertEqual(AppURL.parse("ytdownloader://show-settings"), .showSettings)
    }

    func testDownloadQuery() {
        let parsed = AppURL.parse(
            "ytdownloader://download?videoId=dQw4w9WgXcQ&url=https://www.youtube.com/watch?v=dQw4w9WgXcQ"
        )
        guard case .download(let videoId, let url, let cookies) = parsed else {
            return XCTFail("expected download command")
        }
        XCTAssertEqual(videoId, "dQw4w9WgXcQ")
        XCTAssertEqual(url, "https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        XCTAssertNil(cookies)
    }

    func testBareSchemeWithDownloadQuery() {
        let parsed = AppURL.parse("ytdownloader://?videoId=abc&url=https://youtu.be/abc")
        guard case .download(let videoId, let url, _) = parsed else {
            return XCTFail("expected download command")
        }
        XCTAssertEqual(videoId, "abc")
        XCTAssertEqual(url, "https://youtu.be/abc")
    }

    func testPathDownload() {
        let parsed = AppURL.parse("ytdownloader:///download?videoId=vk1&url=https://vkvideo.ru/video-1_2")
        guard case .download(let videoId, _, _) = parsed else {
            return XCTFail("expected download command")
        }
        XCTAssertEqual(videoId, "vk1")
    }

    func testDownloadWithCookiesPayload() {
        let cookies = ExtensionCookiePayload.encodeBase64URL("# Netscape HTTP Cookie File\n.youtube.com\tTRUE\t/\tTRUE\t0\tSID\tabc")
        let built = AppURL.downloadURL(
            videoId: "vid1",
            url: "https://www.youtube.com/watch?v=vid1",
            cookies: cookies
        )
        XCTAssertNotNil(built)
        let parsed = AppURL.parse(built!)
        guard case .download(let videoId, let url, let payload) = parsed else {
            return XCTFail("expected download with cookies")
        }
        XCTAssertEqual(videoId, "vid1")
        XCTAssertEqual(url, "https://www.youtube.com/watch?v=vid1")
        XCTAssertEqual(payload, cookies)
        let netscape = ExtensionCookiePayload.netscapeText(fromURLPayload: payload!)
        XCTAssertTrue(netscape?.contains("SID") == true)
        XCTAssertTrue(netscape?.contains("abc") == true)
    }

    func testRejectsUnknownHostAndMissingQuery() {
        XCTAssertNil(AppURL.parse("https://example.com/show-queue"))
        XCTAssertNil(AppURL.parse("ytdownloader://download"))
        XCTAssertNil(AppURL.parse("ytdownloader://show-queue-now"))
        XCTAssertNil(AppURL.parse("ytdownloader://download?videoId=only"))
    }
}

final class MenuBarStatusTests: XCTestCase {
    func testIdleWhenQueueEmptyOrFinished() {
        XCTAssertEqual(MenuBarStatus.line(items: []), "Idle")
        XCTAssertEqual(
            MenuBarStatus.line(items: [
                item(status: .completed, progress: 1),
                item(status: .failed, progress: 0),
                item(status: .cancelled, progress: 0.2)
            ]),
            "Idle"
        )
        XCTAssertEqual(StatusMenuModel.make(items: []).statusLine, "Idle")
    }

    func testDownloadingCountAndPercent() {
        let items = [
            item(status: .downloading, progress: 0.43),
            item(status: .downloading, progress: 0.10),
            item(status: .queued, progress: 0),
            item(status: .queued, progress: 0),
            item(status: .queued, progress: 0),
            item(status: .completed, progress: 1)
        ]
        XCTAssertEqual(MenuBarStatus.line(items: items), "Downloading 2 of 5 · 43%")
    }

    func testMergingCountsAsTransfer() {
        let items = [
            item(status: .merging, progress: 0.99),
            item(status: .queued, progress: 0)
        ]
        XCTAssertEqual(MenuBarStatus.line(items: items), "Downloading 1 of 2 · 99%")
    }

    func testQueuedAndRetryingWhenNothingTransferring() {
        XCTAssertEqual(MenuBarStatus.line(items: [item(status: .queued)]), "Queued")
        XCTAssertEqual(
            MenuBarStatus.line(items: [item(status: .queued), item(status: .queued)]),
            "Queued 2"
        )
        XCTAssertEqual(MenuBarStatus.line(items: [item(status: .retrying)]), "Retrying")
    }

    func testMenuActionTitlesMatchNativeSpec() {
        XCTAssertEqual(StatusMenuSpec.showQueue, "Show Queue")
        XCTAssertEqual(StatusMenuSpec.stopAll, "Stop All")
        XCTAssertEqual(StatusMenuSpec.settings, "Settings…")
        XCTAssertEqual(StatusMenuSpec.quit, "Quit YTDownloader")
        XCTAssertEqual(
            StatusMenuSpec.actionTitles,
            ["Show Queue", "Stop All", "Settings…", "Quit YTDownloader"]
        )
        XCTAssertEqual(StatusMenuModel.make(items: []).actions, StatusMenuSpec.actionTitles)
    }

    private func item(status: DownloadStatus, progress: Double = 0) -> DownloadItem {
        DownloadItem(
            videoId: UUID().uuidString,
            url: "https://www.youtube.com/watch?v=dQw4w9WgXcQ",
            status: status,
            progress: progress
        )
    }
}
