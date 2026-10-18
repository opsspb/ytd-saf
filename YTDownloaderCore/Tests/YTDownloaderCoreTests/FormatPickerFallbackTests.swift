import XCTest
@testable import YTDownloaderCore

final class FormatPickerFallbackTests: XCTestCase {
    func testFormatTableLinesAreCompactWithoutURLs() throws {
        let formats = [
            VideoFormat(
                formatId: "96",
                ext: "mp4",
                resolution: "1920x1080",
                width: 1920,
                height: 1080,
                fps: 30,
                vcodec: "avc1.640028",
                acodec: "mp4a.40.2",
                tbr: 4500,
                formatNote: "1080p",
                protocolName: "m3u8_native"
            ),
            VideoFormat(
                formatId: "233",
                ext: "mp4",
                vcodec: "none",
                acodec: nil,
                formatNote: "Default, low",
                protocolName: "m3u8_native"
            )
        ]
        let lines = YTDLPDiagnostics.formatTableLines(from: formats)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(
            lines[0],
            "96\tmp4\tm3u8_native\tavc1.640028\tmp4a.40.2\t1080\t30.0\t4500.0\t1080p"
        )
        XCTAssertTrue(lines[1].contains("233"))
        XCTAssertTrue(lines[1].contains("null"))
        XCTAssertFalse(lines.joined().contains("http"))
        XCTAssertFalse(lines.joined().contains("cookie"))
    }

    func testWriteFormatPickerFallbackLogIncludesTableAndSpec() throws {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("ytd-fmt-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }

        let info = YTDLPInfo(
            id: "rBIesPXJV2E",
            title: "Age gated",
            formats: [
                VideoFormat(
                    formatId: "96",
                    ext: "mp4",
                    width: 1920,
                    height: 1080,
                    fps: 30,
                    vcodec: "avc1",
                    acodec: "mp4a.40.2",
                    tbr: 4000,
                    formatNote: "1080p",
                    protocolName: "m3u8_native"
                )
            ]
        )
        let url = YTDLPDiagnostics.writeFormatPickerFallbackLog(
            info: info,
            fallbackSpec: "96",
            homeDirectory: home
        )
        let fileURL = try XCTUnwrap(url)
        let body = try String(contentsOf: fileURL, encoding: .utf8)
        XCTAssertTrue(body.contains("fallbackSpec=96"))
        XCTAssertTrue(body.contains("96\tmp4\tm3u8_native"))
        XCTAssertTrue(body.contains("rBIesPXJV2E"))
        XCTAssertFalse(body.contains("https://"))

        let jsonURL = fileURL.deletingPathExtension().appendingPathExtension("json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: jsonURL.path))
        let attrs = try FileManager.default.attributesOfItem(atPath: jsonURL.path)
        let perms = attrs[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.int16Value, 0o600)
        let json = try String(contentsOf: jsonURL, encoding: .utf8)
        XCTAssertFalse(json.contains("https://"))
        XCTAssertTrue(json.contains("\"format_id\""))
    }

    func testInfoAndDownloadArgsShareCookiesAndExtractorArgs() {
        let pipeline = VideoDownloadPipeline(
            ytdlpPath: "/tmp/yt-dlp",
            ffmpegPath: "/tmp/ffmpeg",
            cookieMode: .file,
            cookieFilePath: "/tmp/ytd-cookies-test.txt"
        )
        let url = "https://www.youtube.com/watch?v=rBIesPXJV2E"
        let infoArgs = pipeline.infoArguments(url: url, useCookies: true)
        let dlArgs = pipeline.formatSpecDownloadArguments(
            url: url,
            formatSpec: FormatSelector.ytDlpFallbackFormatSpec,
            outputPath: "/tmp/out.mkv",
            useCookies: true
        )

        XCTAssertTrue(infoArgs.contains("-J"))
        XCTAssertEqual(infoArgs.firstIndex(of: "--cookies").map { infoArgs[$0 + 1] }, "/tmp/ytd-cookies-test.txt")
        XCTAssertEqual(dlArgs.firstIndex(of: "--cookies").map { dlArgs[$0 + 1] }, "/tmp/ytd-cookies-test.txt")

        let infoExt = infoArgs.firstIndex(of: "--extractor-args").map { infoArgs[$0 + 1] }
        let dlExt = dlArgs.firstIndex(of: "--extractor-args").map { dlArgs[$0 + 1] }
        XCTAssertEqual(infoExt, "youtube:player_client=default,web_safari")
        XCTAssertEqual(dlExt, infoExt)

        XCTAssertTrue(dlArgs.contains("-f"))
        XCTAssertEqual(dlArgs.firstIndex(of: "-f").map { dlArgs[$0 + 1] }, "bv*+ba/b")
        XCTAssertTrue(dlArgs.contains("--merge-output-format"))
        XCTAssertEqual(dlArgs.firstIndex(of: "--merge-output-format").map { dlArgs[$0 + 1] }, "mkv")
    }

    func testAuthArgsAbsentWithoutCookies() {
        let pipeline = VideoDownloadPipeline(
            ytdlpPath: "/tmp/yt-dlp",
            ffmpegPath: "/tmp/ffmpeg",
            cookieMode: .file,
            cookieFilePath: "/tmp/ytd-cookies-test.txt"
        )
        let url = "https://www.youtube.com/watch?v=jNQXAC9IVRw"
        let infoArgs = pipeline.infoArguments(url: url, useCookies: false)
        let dlArgs = pipeline.formatSpecDownloadArguments(
            url: url,
            formatSpec: "96",
            outputPath: "/tmp/out.mkv",
            useCookies: false
        )
        XCTAssertFalse(infoArgs.contains("--cookies"))
        XCTAssertFalse(infoArgs.contains("--extractor-args"))
        XCTAssertFalse(dlArgs.contains("--cookies"))
        XCTAssertFalse(dlArgs.contains("--extractor-args"))
    }

    func testCookieJarDebugPreservesWhenFlagSet() throws {
        let suite = "ytd-cookie-jar-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("ytd-cookies-\(UUID().uuidString).txt")
        try Data("# Netscape\n".utf8).write(to: temp)
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("ytd-support-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: support)
            try? FileManager.default.removeItem(at: temp)
        }

        defaults.set(true, forKey: CookieJarDebug.keepLastCookieJarKey)
        CookieJarDebug.disposeTempCookieFile(temp, supportDirectory: support, defaults: defaults)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path))
        let kept = support.appendingPathComponent("last-cookie-jar.txt")
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept.path))
        let perms = try FileManager.default.attributesOfItem(atPath: kept.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(perms?.int16Value, 0o600)
    }

    func testCookieJarDebugDeletesWhenFlagOff() throws {
        let suite = "ytd-cookie-jar-test-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }

        let temp = FileManager.default.temporaryDirectory.appendingPathComponent("ytd-cookies-\(UUID().uuidString).txt")
        try Data("# Netscape\n".utf8).write(to: temp)
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("ytd-support-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: support) }

        defaults.set(false, forKey: CookieJarDebug.keepLastCookieJarKey)
        CookieJarDebug.disposeTempCookieFile(temp, supportDirectory: support, defaults: defaults)
        XCTAssertFalse(FileManager.default.fileExists(atPath: temp.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: support.appendingPathComponent("last-cookie-jar.txt").path))
    }

    func testVerifyOutputMissingAudioThrows() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("ytd-probe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let ffprobe = dir.appendingPathComponent("ffprobe")
        let script = """
        #!/bin/sh
        echo video
        exit 0
        """
        try script.write(to: ffprobe, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ffprobe.path)

        let media = dir.appendingPathComponent("out.mkv")
        try Data("fake".utf8).write(to: media)

        let pipeline = VideoDownloadPipeline(
            ytdlpPath: "/tmp/yt-dlp",
            ffmpegPath: "/tmp/ffmpeg",
            ffprobePath: ffprobe.path
        )
        XCTAssertThrowsError(try pipeline.verifyOutputHasVideoAndAudio(at: media.path)) { error in
            let message = (error as? DownloadError)?.errorDescription ?? ""
            XCTAssertTrue(message.contains("missing an audio stream"))
        }
    }
}
