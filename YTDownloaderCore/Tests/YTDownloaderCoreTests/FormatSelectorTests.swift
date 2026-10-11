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
        XCTAssertTrue(selected.video.vcodec?.hasPrefix("av01") == true)
        XCTAssertEqual(selected.video.vbr, 15000)
        
        XCTAssertEqual(selected.audio.formatId, "251")
        XCTAssertEqual(selected.audio.language, "en")
        XCTAssertEqual(selected.audio.languagePreference, 10)
        XCTAssertEqual(selected.audio.abr, 160)
    }
    
    func testFourKHighestBitrateWinsEvenIfThatRungIsHLS() throws {
        let formats = [
            VideoFormat(formatId: "642", ext: "mp4", width: 3840, height: 2160, fps: 60, vcodec: "vp09.02.51.10", acodec: "none", vbr: 32574, protocolName: "m3u8_native"),
            VideoFormat(formatId: "337", ext: "webm", width: 3840, height: 2160, fps: 60, vcodec: "vp9.2", acodec: "none", vbr: 28894, formatNote: "2160p60 HDR", protocolName: "https"),
            VideoFormat(formatId: "701", ext: "mp4", width: 3840, height: 2160, fps: 60, vcodec: "av01.0.13M.10", acodec: "none", vbr: 24632, formatNote: "2160p60 HDR", protocolName: "https"),
            VideoFormat(formatId: "315", ext: "webm", width: 3840, height: 2160, fps: 60, vcodec: "vp9", acodec: "none", vbr: 24041, formatNote: "2160p60", protocolName: "https"),
            VideoFormat(formatId: "140", ext: "m4a", vcodec: "none", acodec: "mp4a", abr: 128, protocolName: "https")
        ]
        let selected = try selector.selectBestFormats(from: YTDLPInfo(id: "LXb3EKWsInQ", title: "4K", formats: formats))
        XCTAssertEqual(selected.video.formatId, "642")
        XCTAssertEqual(selected.video.protocolName, "m3u8_native")
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
    
    func testPicksHighestBitrateAtSameResolutionEvenIfHLS() throws {
        let formats = [
            VideoFormat(
                formatId: "230",
                ext: "mp4",
                resolution: "320x240",
                width: 320,
                height: 240,
                fps: 30,
                vcodec: "avc1.4D400D",
                acodec: "none",
                vbr: 214.775,
                tbr: 214.775,
                protocolName: "m3u8_native"
            ),
            VideoFormat(
                formatId: "133",
                ext: "mp4",
                resolution: "320x240",
                width: 320,
                height: 240,
                fps: 30,
                vcodec: "avc1.4D400D",
                acodec: "none",
                vbr: 57.522,
                tbr: 57.522,
                formatNote: "240p",
                protocolName: "https"
            ),
            VideoFormat(
                formatId: "134",
                ext: "mp4",
                resolution: "320x240",
                width: 320,
                height: 240,
                fps: 30,
                vcodec: "avc1.4D400D",
                acodec: "none",
                vbr: 53.218,
                tbr: 53.218,
                formatNote: "240p",
                protocolName: "https"
            ),
            VideoFormat(
                formatId: "140",
                ext: "m4a",
                vcodec: "none",
                acodec: "mp4a.40.2",
                abr: 130,
                tbr: 129.63,
                protocolName: "https"
            ),
            VideoFormat(
                formatId: "234",
                ext: "mp4",
                vcodec: "none",
                protocolName: "m3u8_native"
            )
        ]

        let selected = try selector.selectBestFormats(from: YTDLPInfo(id: "E8e_Y4yLdd0", title: "I AM WAR, HELP ME KILL.", formats: formats))
        XCTAssertEqual(selected.video.formatId, "230")
        XCTAssertEqual(selected.video.protocolName, "m3u8_native")
        XCTAssertEqual(selected.video.vbr, 214.775)
        XCTAssertEqual(selected.audio.formatId, "140")
    }

    func testProtocolIsOnlyATieBreakerWhenBitrateMatches() throws {
        let formats = [
            VideoFormat(formatId: "hls", ext: "mp4", width: 1920, height: 1080, fps: 60, vcodec: "avc1", acodec: "none", vbr: 5000, protocolName: "m3u8_native"),
            VideoFormat(formatId: "dash", ext: "webm", width: 1920, height: 1080, fps: 60, vcodec: "vp9", acodec: "none", vbr: 5000, protocolName: "https"),
            VideoFormat(formatId: "140", ext: "m4a", vcodec: "none", acodec: "mp4a", abr: 128, protocolName: "https")
        ]
        let selected = try selector.selectBestFormats(from: YTDLPInfo(id: "x", title: "t", formats: formats))
        XCTAssertEqual(selected.video.formatId, "dash")
    }

    func testTopDASHVP9BeatsLowerBitrateHLSAt1080p() throws {
        let formats = [
            VideoFormat(formatId: "303", ext: "webm", width: 1920, height: 1080, fps: 60, vcodec: "vp9", acodec: "none", vbr: 4500, formatNote: "1080p60", protocolName: "https"),
            VideoFormat(formatId: "299", ext: "mp4", width: 1920, height: 1080, fps: 60, vcodec: "avc1", acodec: "none", vbr: 4000, formatNote: "1080p60", protocolName: "https"),
            VideoFormat(formatId: "hls1080", ext: "mp4", width: 1920, height: 1080, fps: 60, vcodec: "avc1", acodec: "none", vbr: 3200, protocolName: "m3u8_native"),
            VideoFormat(formatId: "140", ext: "m4a", vcodec: "none", acodec: "mp4a", abr: 128, protocolName: "https")
        ]
        let selected = try selector.selectBestFormats(from: YTDLPInfo(id: "x", title: "t", formats: formats))
        XCTAssertEqual(selected.video.formatId, "303")
        XCTAssertEqual(selected.video.vcodec, "vp9")
        XCTAssertEqual(selected.video.protocolName, "https")
    }

    func testHigherResolutionHLSBeatsLowerDASH() throws {
        let formats = [
            VideoFormat(formatId: "hls1080", ext: "mp4", width: 1920, height: 1080, fps: 30, vcodec: "avc1", acodec: "none", vbr: 4000, protocolName: "m3u8_native"),
            VideoFormat(formatId: "dash720", ext: "mp4", width: 1280, height: 720, fps: 30, vcodec: "avc1", acodec: "none", vbr: 2500, protocolName: "https"),
            VideoFormat(formatId: "140", ext: "m4a", vcodec: "none", acodec: "mp4a", abr: 128, protocolName: "https")
        ]
        let selected = try selector.selectBestFormats(from: YTDLPInfo(id: "x", title: "t", formats: formats))
        XCTAssertEqual(selected.video.formatId, "hls1080")
    }

    func testIgnoresVideoFormatsWithoutHeight() throws {
        let formats = [
            VideoFormat(formatId: "mystery", ext: "mp4", vcodec: "avc1", acodec: "none", vbr: 9000, protocolName: "m3u8_native"),
            VideoFormat(formatId: "133", ext: "mp4", resolution: "320x240", width: 320, height: 240, fps: 30, vcodec: "avc1", acodec: "none", vbr: 58, protocolName: "https"),
            VideoFormat(formatId: "140", ext: "m4a", vcodec: "none", acodec: "mp4a", abr: 128, protocolName: "https")
        ]
        let selected = try selector.selectBestFormats(from: YTDLPInfo(id: "x", title: "t", formats: formats))
        XCTAssertEqual(selected.video.formatId, "133")
    }

    func testResolvesHeightFromResolutionWhenHeightMissing() throws {
        let formats = [
            VideoFormat(formatId: "dash", ext: "mp4", resolution: "1280x720", vcodec: "avc1", acodec: "none", vbr: 2000, protocolName: "https"),
            VideoFormat(formatId: "low", ext: "mp4", width: 640, height: 360, fps: 30, vcodec: "avc1", acodec: "none", vbr: 800, protocolName: "https"),
            VideoFormat(formatId: "140", ext: "m4a", vcodec: "none", acodec: "mp4a", abr: 128, protocolName: "https")
        ]
        let selected = try selector.selectBestFormats(from: YTDLPInfo(id: "x", title: "t", formats: formats))
        XCTAssertEqual(selected.video.formatId, "dash")
    }

    func testLiveE8eFixturePicksHighestBitrateHLS230() throws {
        let jsonData = try loadFixture(named: "video_info_hls_vs_dash.json")
        let info = try JSONDecoder().decode(YTDLPInfo.self, from: jsonData)
        let selected = try selector.selectBestFormats(from: info)
        XCTAssertEqual(info.id, "E8e_Y4yLdd0")
        XCTAssertEqual(selected.video.formatId, "230")
        XCTAssertEqual(selected.video.protocolName, "m3u8_native")
        XCTAssertEqual(selected.video.height, 240)
        XCTAssertGreaterThan(selected.video.vbr ?? 0, 200)
        XCTAssertEqual(selected.audio.formatId, "140")
        XCTAssertEqual(selected.audio.protocolName, "https")
        let rung = selector.sameResolutionRung(as: selected.video, from: info)
        XCTAssertEqual(rung.first?.formatId, "230")
        XCTAssertTrue(rung.map(\.formatId).contains("133"))
        XCTAssertGreaterThan(rung.count, 1)
        XCTAssertTrue(rung.allSatisfy { $0.height == 240 })
    }

    func testDecodesProtocolFromJSON() throws {
        let json = Data("""
        {"format_id":"230","ext":"mp4","protocol":"m3u8_native","vcodec":"avc1","acodec":"none","height":240,"width":320}
        """.utf8)
        let format = try JSONDecoder().decode(VideoFormat.self, from: json)
        XCTAssertEqual(format.protocolName, "m3u8_native")
        XCTAssertEqual(format.height, 240)
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
