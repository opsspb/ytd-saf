import XCTest
@testable import YTDownloaderCore

final class YTDLPProgressParserTests: XCTestCase {
    func testParsesMachineReadableYTDProgLines() {
        let video = "YTD_PROG: 12.3%|24000000|195278000|112555.27|120|/tmp/out.f160.mp4"
        let info = YTDLPProgress.parseTransfer(video)
        XCTAssertEqual(info?.fraction ?? -1, 0.123, accuracy: 0.0001)
        XCTAssertEqual(info?.downloadedBytes, 24_000_000)
        XCTAssertEqual(info?.expectedBytes, 195_278_000)
        XCTAssertEqual(info?.stream, .video)
        XCTAssertNotNil(info?.speed)
        XCTAssertEqual(info?.eta, "2m00s")

        let audioDone = "YTD_PROG:100.0%|117526|117526|981410.2|NA|/tmp/out.f139.m4a"
        let audio = YTDLPProgress.parseTransfer(audioDone)
        XCTAssertEqual(audio?.fraction ?? -1, 1.0, accuracy: 0.0001)
        XCTAssertEqual(audio?.stream, .audio)
    }

    func testParsesRealYtDlpDestinationAndBarePercent() {
        XCTAssertEqual(
            YTDLPProgress.streamKind(fromDestination: "[download] Destination: /tmp/ytd-prog-test/tpl.f160.mp4"),
            .video
        )
        XCTAssertEqual(
            YTDLPProgress.streamKind(fromDestination: "[download] Destination: /tmp/ytd-prog-test/tpl.f139.m4a"),
            .audio
        )
        XCTAssertEqual(YTDLPProgress.parse("  0.5%") ?? -1, 0.005, accuracy: 0.0001)
        XCTAssertEqual(YTDLPProgress.parse("100.0%") ?? -1, 1.0, accuracy: 0.0001)
        XCTAssertEqual(
            YTDLPProgress.parse("[download]  45.6% of  10.00MiB at    1.20MiB/s ETA 00:04") ?? -1,
            0.456,
            accuracy: 0.0001
        )
    }

    func testParsesAria2cNoticeLines() {
        let full = "[#2c3f5a 12MiB/5.4GiB(2%) CN:16 DL:3.5MiB ETA:25m12s]"
        let info = YTDLPProgress.parseTransfer(full)
        XCTAssertEqual(info?.fraction ?? -1, 0.02, accuracy: 0.0001)
        XCTAssertEqual(info?.speed, "3.5MiB")
        XCTAssertEqual(info?.sizeText, "12MiB/5.4GiB")

        let noEta = "[#a1b2c3 512MiB/1.0GiB(50%) CN:8 DL:8.1MiB]"
        XCTAssertEqual(YTDLPProgress.parseTransfer(noEta)?.fraction ?? -1, 0.5, accuracy: 0.0001)

        let percentOnly = "[#deadbe 100MiB/200MiB(50%) CN:4]"
        XCTAssertEqual(YTDLPProgress.parseTransfer(percentOnly)?.fraction ?? -1, 0.5, accuracy: 0.0001)
    }

    func testSessionIsMonotonicPerStageAndReaches100BeforeMerge() {
        var session = DownloadProgressSession()
        let lines = [
            "[download] Destination: /tmp/out.f299.mp4",
            "YTD_PROG: 10.0%|10|100|1000|9|/tmp/out.f299.mp4",
            "YTD_PROG:  5.0%|5|100|1000|9|/tmp/out.f299.mp4", // regressive noise ignored
            "YTD_PROG: 70.0%|70|100|1000|3|/tmp/out.f299.mp4",
            "[download] Destination: /tmp/out.f140.m4a",
            "YTD_PROG:  1.0%|1|100|1000|99|/tmp/out.f140.m4a",
            "YTD_PROG:100.0%|100|100|1000|NA|/tmp/out.f140.m4a",
            "[Merger] Merging formats into \"/tmp/out.mkv\""
        ]

        var videoFractions: [Double] = []
        var audioFractions: [Double] = []
        var sawMerge = false
        for line in lines {
            let result = session.events(for: line)
            for transfer in result.transfers {
                switch transfer.stream {
                case .video:
                    if let fraction = transfer.fraction { videoFractions.append(fraction) }
                case .audio:
                    if let fraction = transfer.fraction { audioFractions.append(fraction) }
                case .unknown:
                    break
                }
            }
            if result.merging { sawMerge = true }
        }

        XCTAssertEqual(videoFractions.first ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(videoFractions.last ?? -1, 1, accuracy: 0.0001)
        XCTAssertTrue(isMonotonic(videoFractions))
        XCTAssertEqual(audioFractions.first ?? -1, 0, accuracy: 0.0001)
        XCTAssertEqual(audioFractions.last ?? -1, 1, accuracy: 0.0001)
        XCTAssertTrue(isMonotonic(audioFractions))
        XCTAssertTrue(sawMerge)
        XCTAssertLessThan(videoFractions.filter { $0 < 1 }.last ?? 1, 1.01)
    }

    func testProgressTemplateUsesMachineReadablePrefix() {
        XCTAssertTrue(YTDLPProgress.progressTemplate().contains("YTD_PROG:"))
        XCTAssertTrue(YTDLPProgress.progressCLIArgs.contains("--newline"))
        XCTAssertTrue(YTDLPProgress.progressCLIArgs.contains("--progress-template"))
    }

    private func isMonotonic(_ values: [Double]) -> Bool {
        zip(values, values.dropFirst()).allSatisfy { $0 <= $1 + 0.000_001 }
    }
}
