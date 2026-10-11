import XCTest
@testable import YTDownloaderCore

final class ErrorClassifierTests: XCTestCase {
    var classifier: ErrorClassifier!
    
    override func setUp() {
        super.setUp()
        classifier = ErrorClassifier()
    }
    
    func testClassifyCookiesRequired() {
        let error1 = classifier.classifyError(from: "ERROR: Sign in to confirm your age")
        XCTAssertEqual(error1, .cookiesRequired)
        XCTAssertTrue(error1.requiresCookies)
        
        let error2 = classifier.classifyError(from: "ERROR: This video requires login")
        XCTAssertEqual(error2, .cookiesRequired)
    }
    
    func testClassifyAgeRestricted() {
        let error = classifier.classifyError(from: "ERROR: This video is age-restricted and may be inappropriate for some users")
        XCTAssertEqual(error, .ageRestricted)
        XCTAssertTrue(error.requiresCookies)
    }
    
    func testClassifyMembersOnly() {
        let error1 = classifier.classifyError(from: "ERROR: This video is only available to members")
        XCTAssertEqual(error1, .membersOnly)
        XCTAssertTrue(error1.requiresCookies)
        
        let error2 = classifier.classifyError(from: "Join this channel to get access to members-only content")
        XCTAssertEqual(error2, .membersOnly)
    }
    
    func testClassifyCaptchaRequired() {
        let error1 = classifier.classifyError(from: "ERROR: CAPTCHA required")
        XCTAssertEqual(error1, .captchaRequired)
        XCTAssertTrue(error1.requiresCookies)
        
        let error2 = classifier.classifyError(from: "Please confirm you're not a bot")
        XCTAssertEqual(error2, .captchaRequired)
    }
    
    func testClassifyForbidden() {
        let error1 = classifier.classifyError(from: "ERROR: HTTP Error 403: Forbidden")
        XCTAssertEqual(error1, .forbidden)
        XCTAssertTrue(error1.isTransient)
        
        let error2 = classifier.classifyError(from: "Unable to download webpage: HTTP Error 403")
        XCTAssertEqual(error2, .forbidden)
    }
    
    func testClassifyTooManyRequests() {
        let error1 = classifier.classifyError(from: "ERROR: HTTP Error 429: Too Many Requests")
        XCTAssertEqual(error1, .tooManyRequests)
        XCTAssertTrue(error1.isTransient)
        
        let error2 = classifier.classifyError(from: "Server returned 429 too many requests")
        XCTAssertEqual(error2, .tooManyRequests)
    }
    
    func testClassifyNetworkError() {
        let error1 = classifier.classifyError(from: "ERROR: Connection timed out")
        if case .networkError = error1 {
            XCTAssertTrue(error1.isTransient)
        } else {
            XCTFail("Expected networkError")
        }
        
        let error2 = classifier.classifyError(from: "Network connection lost")
        if case .networkError = error2 {
            XCTAssertTrue(error2.isTransient)
        } else {
            XCTFail("Expected networkError")
        }
    }
    
    func testClassifyNoSuitableFormats() {
        let error = classifier.classifyError(from: "ERROR: No video formats found")
        XCTAssertEqual(error, .noSuitableFormats)
        XCTAssertFalse(error.isTransient)
        XCTAssertFalse(error.requiresCookies)
    }
    
    func testClassifyRequestedFormatUnavailable() {
        let error = classifier.classifyError(from: "ERROR: [youtube] 39l1VzQit3o: Requested format is not available. Use --list-formats")
        if case .downloadFailed(let msg) = error {
            XCTAssertTrue(msg.contains("Requested format is not available"))
        } else {
            XCTFail("Expected downloadFailed, got \(error)")
        }
    }

    func testClassifyUnknownError() {
        let error = classifier.classifyError(from: "Some random unexpected error")
        if case .unknown(let msg) = error {
            XCTAssertEqual(msg, "Some random unexpected error")
        } else {
            XCTFail("Expected unknown error")
        }
    }

    func testShortDisplayLineHidesFfmpegDump() {
        let stored = DownloadError.mergeFailed(
            "ffmpeg version 9.0.2-https://www.martin-riedl.de\nInput #0, mpegts ... video.mp4\nCan't write packet with unknown timestamp"
        ).errorDescription
        XCTAssertEqual(DownloadError.shortDisplayLine(from: stored), "Failed to merge video and audio")
        XCTAssertTrue(DownloadError.hasTechnicalDetails(stored))
    }

    func testShortDisplayLinePeelsUnknownYtDlpError() {
        let stored = DownloadError.unknown("ERROR: [youtube] clickIsoVid: This video is unavailable").errorDescription
        XCTAssertEqual(DownloadError.shortDisplayLine(from: stored), "[youtube] clickIsoVid: This video is unavailable")
    }

    func testShortMessageDoesNotIncludeLog() {
        XCTAssertEqual(DownloadError.mergeFailed("huge log").shortMessage, "Failed to merge video and audio")
        XCTAssertEqual(DownloadError.downloadFailed("huge log").shortMessage, "Download failed")
        XCTAssertEqual(DownloadError.unknown("oops").shortMessage, "Download failed")
    }
}
