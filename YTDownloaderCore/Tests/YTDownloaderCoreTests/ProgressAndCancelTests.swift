import XCTest
@testable import YTDownloaderCore

final class ProgressAndCancelTests: XCTestCase {
    func testParsesAria2cProgressLine() {
        let line = "[#2c3f5a 12MiB/5.4GiB(2%) CN:16 DL:3.5MiB ETA:25m12s]"
        let info = YTDLPProgress.parseTransfer(line)
        XCTAssertEqual(info?.fraction ?? 0, 0.02, accuracy: 0.0001)
        XCTAssertEqual(info?.speed, "3.5MiB")
        XCTAssertTrue(info?.eta?.contains("25m") == true)
        XCTAssertEqual(info?.sizeText, "12MiB/5.4GiB")
        XCTAssertNotNil(info?.expectedBytes)
    }

    func testDiskByteCount() {
        XCTAssertEqual(YTDLPProgress.byteCount("5.4GiB"), Int64(5.4 * 1024 * 1024 * 1024))
        XCTAssertEqual(YTDLPProgress.byteCount("12MiB"), 12 * 1024 * 1024)
    }

    func testAppSupportOverride() {
        let url = AppSupport.directory(environment: [AppSupport.environmentKey: "/tmp/ytd-test-support"], arguments: [])
        XCTAssertEqual(url.path, "/tmp/ytd-test-support")
        let fromArgs = AppSupport.directory(environment: [:], arguments: ["app", "--app-support", "/tmp/ytd-arg-support"])
        XCTAssertEqual(fromArgs.path, "/tmp/ytd-arg-support")
        XCTAssertEqual(AppSupport.fetchingTitle(for: "https://vkvideo.ru/video-1_2"), "Fetching info… · VK")
        XCTAssertEqual(AppSupport.fetchingTitle(for: "https://www.youtube.com/watch?v=abc"), "Fetching info… · YouTube")
    }

    func testDisplayTitleHidesRawId() {
        let item = DownloadItem(videoId: "-212451998_456243253", url: "https://vkvideo.ru/video-212451998_456243253")
        XCTAssertEqual(item.displayTitle, "Fetching info… · VK")
        XCTAssertFalse(item.displayTitle.contains("212451998"))
    }

    func testFormatSummaryAndMeta() {
        let log = "YTD_META:vk|||-212451998_456243253|||Title|||dash_webm-5+dash_sep-13|||1920x1080|||60|||vp09.00.41.08|||mp4a.40.2|||9485|||265"
        let meta = YTDLPOutputParser.parseMeta(from: log)
        XCTAssertEqual(meta?.title, "Title")
        XCTAssertEqual(meta?.summary, "1920x1080 60fps VP9 + AAC 265k")
    }

    func testProcessCancellationStopsSleep() throws {
        let token = ProcessCancellation()
        let started = Date()
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
            token.cancel()
        }
        let result = try ProcessRunner.run(
            executable: "/bin/sleep",
            arguments: ["20"],
            timeout: 15,
            cancellation: token
        )
        XCTAssertTrue(result.cancelled)
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }
}
