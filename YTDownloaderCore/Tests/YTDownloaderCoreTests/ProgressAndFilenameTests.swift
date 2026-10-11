import XCTest
@testable import YTDownloaderCore

final class ProgressAndFilenameTests: XCTestCase {
    func testParsesNewlinePercent() {
        XCTAssertEqual(YTDLPProgress.parse("[download]  12.3% of 10.00MiB at 1.00MiB/s") ?? -1, 0.123, accuracy: 0.0001)
        XCTAssertEqual(YTDLPProgress.parse("download:  45.0%") ?? -1, 0.45, accuracy: 0.0001)
        XCTAssertEqual(YTDLPProgress.parse("download:100%") ?? -1, 1.0, accuracy: 0.0001)
        XCTAssertNil(YTDLPProgress.parse("Downloading webpage"))
    }

    func testKeepsCyrillicTitle() {
        let name = OutputFilename.make(
            title: "Таможня осадила Давидыча! Уголовное дело за BMW из РОЛЬФ? (Ярдрей 706)",
            videoId: "39l1VzQit3o"
        )
        XCTAssertTrue(name.contains("Таможня"))
        XCTAssertTrue(name.contains("Давидыча"))
        XCTAssertTrue(name.hasSuffix("_39l1VzQit3o.mkv"))
        XCTAssertFalse(name.contains("/"))
        XCTAssertFalse(name.contains("?"))
    }

    func testEmptyTitleFallsBack() {
        XCTAssertEqual(OutputFilename.make(title: "///", videoId: "abc"), "video_abc.mkv")
    }

    func testProcessRunnerTimesOut() throws {
        let result = try ProcessRunner.run(executable: "/bin/sleep", arguments: ["20"], timeout: 1)
        XCTAssertTrue(result.timedOut)
    }

    func testSkipsStoryboardFormats() throws {
        let formats = [
            VideoFormat(formatId: "sb0", ext: "mhtml", width: 1920, height: 1080, fps: 1, vcodec: "jpg", acodec: "none", formatNote: "storyboard"),
            VideoFormat(formatId: "299", ext: "mp4", width: 1920, height: 1080, fps: 60, vcodec: "avc1", acodec: "none", vbr: 4000),
            VideoFormat(formatId: "140", ext: "m4a", vcodec: "none", acodec: "mp4a", abr: 128, languagePreference: 10)
        ]
        let selected = try FormatSelector().selectBestFormats(from: YTDLPInfo(id: "x", title: "t", formats: formats))
        XCTAssertEqual(selected.video.formatId, "299")
        XCTAssertEqual(selected.audio.formatId, "140")
    }
}
