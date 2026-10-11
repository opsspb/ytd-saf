import XCTest
@testable import YTDownloaderCore

final class BinaryBootstrapTests: XCTestCase {
    func testDetectsZipMachOAndHTML() {
        XCTAssertEqual(DownloadedFileKind.detect(data: Data([0x50, 0x4B, 0x03, 0x04, 0x00])), .zip)
        XCTAssertEqual(DownloadedFileKind.detect(data: Data([0xCF, 0xFA, 0xED, 0xFE, 0x00])), .macho)
        XCTAssertEqual(DownloadedFileKind.detect(data: Data("<html><body>429 Too Many Requests</body></html>".utf8)), .html)
        XCTAssertEqual(DownloadedFileKind.detect(data: Data()), .unknown)
    }

    func testMartinRiedlURLsAreArchSpecific() {
        let arm = BinaryBootstrap.martinRiedlURL(tool: "ffmpeg", arch: "arm64", channel: "release")
        XCTAssertEqual(arm.absoluteString, "https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/ffmpeg.zip")

        let intel = BinaryBootstrap.martinRiedlURL(tool: "ffprobe", arch: "amd64", channel: "snapshot")
        XCTAssertEqual(intel.absoluteString, "https://ffmpeg.martin-riedl.de/redirect/latest/macos/amd64/snapshot/ffprobe.zip")
    }

    func testEvermeetAndYTDLPURLs() {
        XCTAssertEqual(
            BinaryBootstrap.evermeetURL(tool: "ffmpeg").absoluteString,
            "https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip"
        )
        XCTAssertTrue(BinaryBootstrap.ytdlpURL().absoluteString.contains("yt-dlp_macos"))
    }

    func testBootstrapErrorMessageIsActionable() {
        let error = DownloadError.bootstrapFailed("HTTP 429")
        XCTAssertTrue(error.errorDescription?.contains("yt-dlp/ffmpeg") == true)
        XCTAssertTrue(error.errorDescription?.contains("HTTP 429") == true)
        XCTAssertFalse(error.isTransient)
        XCTAssertFalse(error.requiresCookies)
    }

    func testCpuArchitectureIsKnown() {
        let arch = BinaryBootstrap.cpuArchitecture()
        XCTAssertTrue(arch == "arm64" || arch == "amd64")
    }
}
