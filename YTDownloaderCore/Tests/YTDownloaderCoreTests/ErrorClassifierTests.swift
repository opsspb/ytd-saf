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
    
    func testClassifyUnknownError() {
        let error = classifier.classifyError(from: "Some random unexpected error")
        if case .unknown(let msg) = error {
            XCTAssertEqual(msg, "Some random unexpected error")
        } else {
            XCTFail("Expected unknown error")
        }
    }
}
