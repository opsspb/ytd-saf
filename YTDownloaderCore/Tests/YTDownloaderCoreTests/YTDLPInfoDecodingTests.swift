import XCTest
@testable import YTDownloaderCore

final class YTDLPInfoDecodingTests: XCTestCase {
    func testRealMeAtTheZooDecodesAndSelects() throws {
        try assertDecodesAndSelects(fixture: "video_info_real_me_at_the_zoo.json", minHeight: 144)
    }

    func testRealCostaRica4KDecodesAndSelects() throws {
        let selected = try assertDecodesAndSelects(fixture: "video_info_real_costa_rica_4k.json", minHeight: 2160)
        XCTAssertEqual(selected.video.height, 2160)
    }

    func testRealRickRollDecodesAndSelects() throws {
        try assertDecodesAndSelects(fixture: "video_info_real_rickroll.json", minHeight: 144)
    }

    func testDescribeDecodeErrorMentionsCodingPath() {
        struct Tiny: Decodable { let filesize: Int }
        let data = Data(#"{"filesize":1.5}"#.utf8)
        do {
            _ = try JSONDecoder().decode(Tiny.self, from: data)
            XCTFail("expected decode failure")
        } catch {
            let message = VideoDownloadPipeline.describeDecodeError(error)
            XCTAssertTrue(message.contains("JSON decode failed"))
        }
    }

    @discardableResult
    private func assertDecodesAndSelects(fixture: String, minHeight: Int) throws -> SelectedFormats {
        let data = try loadFixture(named: fixture)
        let info = try JSONDecoder().decode(YTDLPInfo.self, from: data)
        XCTAssertFalse(info.formats.isEmpty)
        let selected = try FormatSelector().selectBestFormats(from: info)
        XCTAssertGreaterThanOrEqual(selected.video.height ?? 0, minHeight)
        XCTAssertTrue(selected.audio.hasAudio)
        XCTAssertTrue(selected.audio.isAudioOnly)
        return selected
    }

    private func loadFixture(named name: String) throws -> Data {
        let testBundle = Bundle.module
        let base = name.replacingOccurrences(of: ".json", with: "")
        guard let url = testBundle.url(forResource: base, withExtension: "json", subdirectory: "Fixtures") else {
            XCTFail("Could not find fixture: \(name)")
            return Data()
        }
        return try Data(contentsOf: url)
    }
}
