import XCTest
@testable import YTDownloaderCore

final class SiteAdapterTests: XCTestCase {
    func testYouTubeAdapterLeavesFormatPolicyEmpty() {
        let adapter = SiteAdapterRegistry.adapter(for: "https://www.youtube.com/watch?v=jNQXAC9IVRw")
        XCTAssertEqual(adapter.site, .youtube)
        XCTAssertNil(adapter.formatSpec)
        XCTAssertNil(adapter.formatSort)
        XCTAssertTrue(adapter.extraArgs.isEmpty)
    }

    func testVKAdapterUsesYtDlpSorter() {
        let adapter = SiteAdapterRegistry.adapter(for: "https://vkvideo.ru/clip30014565_456240946")
        XCTAssertEqual(adapter.site, .vk)
        XCTAssertEqual(adapter.formatSpec, "bv*+ba/b")
        XCTAssertEqual(adapter.formatSort, "res,fps,vbr,abr,proto:https")
        XCTAssertTrue(adapter.extraArgs.contains("--no-write-subs"))
        XCTAssertTrue(adapter.extraArgs.contains("--retries"))
    }

    func testVKComUsesSameAdapter() {
        let adapter = SiteAdapterRegistry.adapter(for: "https://vk.com/video-30558759_456239017")
        XCTAssertEqual(adapter, SiteAdapterRegistry.vk)
    }

    func testParseChosenFormatsFromYtDlpLog() {
        let log = """
        [vk] Extracting URL: https://vkvideo.ru/clip30014565_456240946
        [info] 30014565_456240946: Downloading 1 format(s): dash_sep-6+dash_sep-11
        YTD_META:vk|||30014565_456240946|||Clip by @diamondoly|||dash_sep-6+dash_sep-11|||1080x1920|||30
        """
        let meta = YTDLPOutputParser.parseMeta(from: log)
        XCTAssertEqual(meta?.extractor, "vk")
        XCTAssertEqual(meta?.id, "30014565_456240946")
        XCTAssertEqual(meta?.title, "Clip by @diamondoly")
        XCTAssertEqual(meta?.formatId, "dash_sep-6+dash_sep-11")
        XCTAssertEqual(meta?.videoFormatId, "dash_sep-6")
        XCTAssertEqual(meta?.audioFormatId, "dash_sep-11")
        XCTAssertEqual(meta?.resolution, "1080x1920")
        XCTAssertEqual(meta?.fps, 30)
        XCTAssertEqual(YTDLPOutputParser.parseChosenFormatLine(from: log), "dash_sep-6+dash_sep-11")
    }

    func testParseSingleFormatAndFallbackLine() {
        let pair = YTDLPOutputParser.splitFormatPair("url1080")
        XCTAssertEqual(pair.video, "url1080")
        XCTAssertNil(pair.audio)

        let fallback = YTDLPOutputParser.parseMeta(from: "[info] id: Downloading 1 format(s): dash_sep-8+dash_sep-13")
        XCTAssertEqual(fallback?.formatId, "dash_sep-8+dash_sep-13")
        XCTAssertEqual(fallback?.videoFormatId, "dash_sep-8")
        XCTAssertEqual(fallback?.audioFormatId, "dash_sep-13")
    }
}
