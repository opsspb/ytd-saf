import XCTest
@testable import YTDownloaderCore

final class FormatSelectorTests: XCTestCase {
    var selector: FormatSelector!
    
    override func setUp() {
        super.setUp()
        selector = FormatSelector()
    }
    
    func testSelect4KHDRWithHighestFPS() throws {
        let jsonData = try loadFixture(named: "video_info_4k_hdr_multilang.json")
        let info = try JSONDecoder().decode(YTDLPInfo.self, from: jsonData)
        
        let selected = try selector.selectBestFormats(from: info)
        
        XCTAssertEqual(selected.video.formatId, "701")
        XCTAssertEqual(selected.video.width, 3840)
        XCTAssertEqual(selected.video.height, 2160)
        XCTAssertEqual(selected.video.fps, 60)
        
        XCTAssertEqual(selected.audio.formatId, "251")
        XCTAssertEqual(selected.audio.language, "en")
        XCTAssertEqual(selected.audio.languagePreference, 10)
        XCTAssertEqual(selected.audio.abr, 160)
    }
    
    func testSelectHighestFPSWhenSameResolution() throws {
        let jsonData = try loadFixture(named: "video_info_high_fps.json")
        let info = try JSONDecoder().decode(YTDLPInfo.self, from: jsonData)
        
        let selected = try selector.selectBestFormats(from: info)
        
        XCTAssertEqual(selected.video.formatId, "303")
        XCTAssertEqual(selected.video.fps, 60)
    }
    
    func testSelectOriginalLanguageAudio() throws {
        let jsonData = try loadFixture(named: "video_info_4k_hdr_multilang.json")
        let info = try JSONDecoder().decode(YTDLPInfo.self, from: jsonData)
        
        let selected = try selector.selectBestFormats(from: info)
        
        XCTAssertGreaterThanOrEqual(selected.audio.languagePreference ?? -999, 0)
        XCTAssertEqual(selected.audio.language, "en")
    }
    
    func testNoSuitableFormatsThrowsError() {
        let info = YTDLPInfo(
            id: "test",
            title: "Test",
            formats: []
        )
        
        XCTAssertThrowsError(try selector.selectBestFormats(from: info)) { error in
            XCTAssertEqual(error as? DownloadError, .noSuitableFormats)
        }
    }
    
    func testSelectHighestBitrateWhenFPSEqual() throws {
        let formats = [
            VideoFormat(formatId: "1", ext: "webm", width: 1920, height: 1080, fps: 60, vcodec: "vp9", acodec: "none", vbr: 5000),
            VideoFormat(formatId: "2", ext: "webm", width: 1920, height: 1080, fps: 60, vcodec: "vp9", acodec: "none", vbr: 5500),
            VideoFormat(formatId: "3", ext: "webm", width: 1920, height: 1080, fps: 60, vcodec: "vp9", acodec: "none", vbr: 4800)
        ]
        
        let audioFormats = [
            VideoFormat(formatId: "a1", ext: "webm", vcodec: "none", acodec: "opus", abr: 128, languagePreference: 10)
        ]
        
        let info = YTDLPInfo(id: "test", title: "Test", formats: formats + audioFormats)
        let selected = try selector.selectBestFormats(from: info)
        
        XCTAssertEqual(selected.video.formatId, "2")
        XCTAssertEqual(selected.video.vbr, 5500)
    }
    
    func testSelectHighestAudioBitrateForOriginalLanguage() throws {
        let videoFormats = [
            VideoFormat(formatId: "v1", ext: "webm", width: 1920, height: 1080, fps: 30, vcodec: "vp9", acodec: "none", vbr: 3000)
        ]
        
        let audioFormats = [
            VideoFormat(formatId: "a1", ext: "webm", vcodec: "none", acodec: "opus", abr: 160, language: "en", languagePreference: 10),
            VideoFormat(formatId: "a2", ext: "webm", vcodec: "none", acodec: "opus", abr: 128, language: "en", languagePreference: 10),
            VideoFormat(formatId: "a3", ext: "webm", vcodec: "none", acodec: "opus", abr: 160, language: "es", languagePreference: -1)
        ]
        
        let info = YTDLPInfo(id: "test", title: "Test", formats: videoFormats + audioFormats)
        let selected = try selector.selectBestFormats(from: info)
        
        XCTAssertEqual(selected.audio.formatId, "a1")
        XCTAssertEqual(selected.audio.abr, 160)
        XCTAssertEqual(selected.audio.languagePreference, 10)
    }
    
    private func loadFixture(named name: String) throws -> Data {
        let testBundle = Bundle.module
        guard let url = testBundle.url(forResource: name.replacingOccurrences(of: ".json", with: ""), withExtension: "json", subdirectory: "Fixtures") else {
            XCTFail("Could not find fixture: \(name)")
            return Data()
        }
        return try Data(contentsOf: url)
    }
}
