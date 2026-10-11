import XCTest
@testable import YTDownloaderCore

final class DownloadItemStatusTests: XCTestCase {
    func testCompletedClearsLeftoverInterruptError() {
        var item = DownloadItem(
            videoId: "UdjPbLwlJp4",
            url: "https://www.youtube.com/watch?v=UdjPbLwlJp4",
            title: "2026 Singapore GP Meme Review",
            status: .downloading,
            progress: 0.4,
            error: "Interrupted; retrying"
        )

        item.applyStatus(.completed, progress: 1, outputPath: "/tmp/singapore.mkv")

        XCTAssertEqual(item.status, .completed)
        XCTAssertNil(item.error)
        XCTAssertFalse(item.showsFailureUI)
        XCTAssertEqual(item.listStatusText, "Completed")
        XCTAssertEqual(item.outputPath, "/tmp/singapore.mkv")
        XCTAssertTrue(item.log?.contains("Interrupted; retrying") == true)
    }

    func testSanitizeCompletedQueueItemDropsRedError() {
        var item = DownloadItem(
            videoId: "UdjPbLwlJp4",
            url: "https://www.youtube.com/watch?v=UdjPbLwlJp4",
            status: .completed,
            progress: 1,
            error: "Interrupted; retrying",
            outputPath: "/Users/pavel/Downloads/singapore.mkv"
        )

        item.sanitizeAfterLoad()

        XCTAssertEqual(item.status, .completed)
        XCTAssertNil(item.error)
        XCTAssertFalse(item.showsFailureUI)
        XCTAssertTrue(item.log?.contains("Interrupted; retrying") == true)
    }

    func testInterruptedLoadDoesNotUseRedError() {
        var item = DownloadItem(
            videoId: "abc",
            url: "https://www.youtube.com/watch?v=abc",
            status: .downloading,
            progress: 0.5
        )

        item.sanitizeAfterLoad()

        XCTAssertEqual(item.status, .queued)
        XCTAssertEqual(item.progress, 0)
        XCTAssertNil(item.error)
        XCTAssertFalse(item.showsFailureUI)
        XCTAssertEqual(item.listStatusText, "Queued")
        XCTAssertTrue(item.log?.contains("Interrupted; retrying") == true)
    }

    func testRetryingUsesNeutralStatusLine() {
        var item = DownloadItem(videoId: "abc", url: "https://www.youtube.com/watch?v=abc")
        let note = DownloadItem.retryStatusLine(delay: 23, attempt: 2, maxAttempts: 10)
        XCTAssertEqual(note, "Retrying in 23s, attempt 2/10")

        item.applyStatus(.retrying, retryNote: note, appendLog: "Access forbidden (403)")

        XCTAssertEqual(item.status, .retrying)
        XCTAssertNil(item.error)
        XCTAssertFalse(item.showsFailureUI)
        XCTAssertEqual(item.listStatusText, "Retrying in 23s, attempt 2/10")
        XCTAssertEqual(item.retryNote, note)
        XCTAssertTrue(item.log?.contains("Access forbidden (403)") == true)
    }

    func testDecodesLegacyQueueItemWithoutLogFields() throws {
        let json = """
        {
          "id": "AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEEE",
          "videoId": "UdjPbLwlJp4",
          "url": "https://www.youtube.com/watch?v=UdjPbLwlJp4",
          "title": "2026 Singapore GP Meme Review",
          "status": "completed",
          "progress": 1,
          "error": "Interrupted; retrying",
          "outputPath": "/tmp/out.mkv",
          "addedAt": 0,
          "completedAt": 1
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        var item = try decoder.decode(DownloadItem.self, from: json)
        XCTAssertEqual(item.error, "Interrupted; retrying")
        item.sanitizeAfterLoad()
        XCTAssertNil(item.error)
        XCTAssertFalse(item.showsFailureUI)
    }
}
