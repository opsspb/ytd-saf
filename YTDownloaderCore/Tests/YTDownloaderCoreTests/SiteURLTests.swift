import XCTest
@testable import YTDownloaderCore

final class SiteURLTests: XCTestCase {
    func testYouTubeWatchAndShorts() {
        let watch = SiteURL.resolve("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
        XCTAssertEqual(watch?.site, .youtube)
        XCTAssertEqual(watch?.id, "dQw4w9WgXcQ")
        XCTAssertEqual(watch?.kind, .video)
        XCTAssertTrue(watch?.isDownloadable == true)

        let short = SiteURL.resolve("https://www.youtube.com/shorts/abc123Short")
        XCTAssertEqual(short?.id, "abc123Short")
        XCTAssertEqual(short?.site, .youtube)

        let youtu = SiteURL.resolve("https://youtu.be/jNQXAC9IVRw")
        XCTAssertEqual(youtu?.id, "jNQXAC9IVRw")
        XCTAssertEqual(youtu?.url, "https://www.youtube.com/watch?v=jNQXAC9IVRw")
    }

    func testVKVideoAndClip() {
        let video = SiteURL.resolve("https://vkvideo.ru/video-220754053_456242564")
        XCTAssertEqual(video?.site, .vk)
        XCTAssertEqual(video?.id, "-220754053_456242564")
        XCTAssertEqual(video?.kind, .video)
        XCTAssertEqual(video?.url, "https://vkvideo.ru/video-220754053_456242564")
        XCTAssertTrue(video?.isDownloadable == true)

        let clip = SiteURL.resolve("https://vkvideo.ru/clip30014565_456240946")
        XCTAssertEqual(clip?.id, "30014565_456240946")
        XCTAssertEqual(clip?.kind, .clip)
        XCTAssertEqual(clip?.url, "https://vkvideo.ru/clip30014565_456240946")

        let negativeClip = SiteURL.resolve("https://vk.com/clip-53316211_456243863")
        XCTAssertEqual(negativeClip?.id, "-53316211_456243863")
        XCTAssertEqual(negativeClip?.kind, .clip)
        XCTAssertEqual(negativeClip?.url, "https://vkvideo.ru/clip-53316211_456243863")
    }

    func testVKcomAndVkRuAndQueryZ() {
        let vkCom = SiteURL.resolve("https://vk.com/video205387401_165548505")
        XCTAssertEqual(vkCom?.id, "205387401_165548505")
        XCTAssertEqual(vkCom?.site, .vk)

        let vkRu = SiteURL.resolve("https://vk.ru/video-220754053_456242564")
        XCTAssertEqual(vkRu?.id, "-220754053_456242564")

        let zLink = SiteURL.resolve("https://vk.com/videos-77521?z=video-77521_162222515%2Fclub77521")
        XCTAssertEqual(zLink?.id, "-77521_162222515")
        XCTAssertEqual(zLink?.kind, .video)

        let feedZ = SiteURL.resolve("https://vk.com/feed?z=video-43215063_166094326")
        XCTAssertEqual(feedZ?.id, "-43215063_166094326")

        let clipZ = SiteURL.resolve("https://vk.com/clips-74006511?z=clip-74006511_456247211")
        XCTAssertEqual(clipZ?.id, "-74006511_456247211")
        XCTAssertEqual(clipZ?.kind, .clip)
    }

    func testVKSkipsLivePlaylistEmbed() {
        let liveHost = SiteURL.resolve("https://live.vkvideo.ru/some-stream")
        XCTAssertEqual(liveHost?.kind, .unsupported)
        XCTAssertFalse(liveHost?.isDownloadable == true)

        let livePath = SiteURL.resolve("https://vkvideo.ru/live-12345")
        XCTAssertEqual(livePath?.kind, .live)
        XCTAssertFalse(livePath?.isDownloadable == true)

        let playlist = SiteURL.resolve("https://vkvideo.ru/playlist/-204353299_426")
        XCTAssertEqual(playlist?.kind, .playlist)
        XCTAssertFalse(playlist?.isDownloadable == true)

        let embed = SiteURL.resolve("https://vk.com/video_ext.php?oid=-77521&id=162222515&hash=abc")
        XCTAssertEqual(embed?.kind, .unsupported)
        XCTAssertFalse(embed?.isDownloadable == true)
    }

    func testUnknownURLIsNil() {
        XCTAssertNil(SiteURL.resolve("https://example.com/watch"))
        XCTAssertNil(SiteURL.resolve(""))
    }
}
