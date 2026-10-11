# Testing

## Automated (verified on this Mac)

### Unit tests

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
cd YTDownloaderCore && swift test
```

Includes format selection (4K/60, original-language audio), retry delays, error classification, and bootstrap URL/file-kind checks.

### Content script (card click must not navigate)

```bash
swift Scripts/run-content-tests.swift
```

Loads `YTDownloader/YTDownloaderExtension/Resources/content.test.html` in WKWebView. Expected: **16 passed, 0 failed** (previous card/watch cases plus lockup click hand-off, modern Like/Share actions row, relocate out of a hidden leftover row).

```bash
swift Scripts/run-content-tests.swift YTDownloader/YTDownloaderExtension/Resources/vk.test.html
```

VK fixtures use `data-testid` + hrefs (`video_card_author`, `grid-item`, `clip-preview-owner`). Expected: all passed, 0 failed (card/watch YD, no-navigation, skip live/playlist).

### Binary bootstrap (clean, not Homebrew)

`BinaryBootstrap(preferHomebrew: false)` downloaded:

- `yt-dlp` from GitHub releases (`yt-dlp_macos`)
- `ffmpeg` / `ffprobe`: evermeet.cx returned HTML 429 → retries → **martin-riedl.de arm64 release** zips

Installed to `~/Library/Application Support/YTDownloader/bin`, `chmod 755`, quarantine cleared, `ffmpeg -version` / `ffprobe -version` / `yt-dlp --version` succeeded. Binaries are Mach-O arm64 (ffmpeg/ffprobe) and universal (yt-dlp).

### End-to-end downloads (app pipeline + app binaries)

```bash
cd YTDownloaderCore
swift run ytd-e2e --skip-homebrew --output /tmp/ytd-e2e-run \
  "https://www.youtube.com/watch?v=jNQXAC9IVRw" \
  "https://www.youtube.com/watch?v=LXb3EKWsInQ" \
  "https://www.youtube.com/watch?v=J---aiyznGQ"
```

Used **installed app binaries** (not Homebrew). `VideoDownloadPipeline` is the same code path as `DownloadManager`.

| Video | Chosen video vs `yt-dlp -F` | Chosen audio | ffprobe |
|---|---|---|---|
| Me at the zoo (`jNQXAC9IVRw`, 19s) | **230** 320×240@15 (highest height, then bitrate among 240p) | **140** 130 kbps AAC | matroska, h264 + aac |
| Costa Rica 4K 60 HDR (`LXb3EKWsInQ`, 314s) | **642** 3840×2160@60 HDR VP9 (~32.5 Mb/s, highest height/fps/vbr) | **251-drc** 132.7 kbps Opus | matroska, vp9 3840×2160 + opus, 1.1 GB |
| Keyboard Cat (`J---aiyznGQ`, 55s) | **230** 320×240@15 | **140-drc** 130 kbps AAC, `language=en` | matroska, h264 + aac |

Container tag `ENCODER=Lavf…` only (muxer). Stream codecs match the selected yt-dlp formats → **copy, not re-encode**.

Public videos probed for multiple dubbed audio languages only exposed a single `language` (or none). Multi-language **selection** is covered by `FormatSelectorTests` + `video_info_4k_hdr_multilang.json`.

### URL scheme hand-off

Ad-hoc signed Debug build (`CODE_SIGN_IDENTITY=-`).

- Cold start: `open 'ytdownloader://download?videoId=handoff-cold&url=…'` launched the app and wrote `handoff-cold` into `queue.json`.
- Warm start (app already running) also enqueued.
- A **sandboxed** helper calling `NSWorkspace.shared.open` **aborted (exit 133)**. The extension therefore opens the scheme from **content.js** (hidden iframe) and **background.js** (`tabs.create`). `SafariWebExtensionHandler` still tries `NSWorkspace` as backup.

### CI

`.github/workflows/build.yml`: build + `swift test`. `integration-test` only runs format selection against a live YouTube fetch; if the runner is blocked the live steps are skipped (`if:`), not silently passed.

## Pavel: Safari click-by-click

Do not change system/Safari settings except as listed.

1. `open ~/Developer/ytd-saf/YTDownloader.xcodeproj`
2. Target **YTDownloader** → Signing & Capabilities → Team → personal Apple ID
3. Target **YTDownloaderExtension** → same Team
4. Scheme **YTDownloader** → Run (⌘R)
5. Wait until setup is Ready (or Retry if a download host is rate-limited)
6. Safari → Settings → Advanced → **Show features for web developers**
7. Develop → **Allow Unsigned Extensions**
8. Safari → Settings → Extensions → enable **YTDownloader** → allow on youtube.com
9. Open a watch page → **YD** next to Like/Share → app shows the item → MKV in ~/Downloads
10. Home/feed → **YD** under a card avatar → page must **not** navigate; app queues the video
11. Optional age-restricted: Settings → Cookies → Safari → System Settings → Privacy & Security → Full Disk Access → add YTDownloader → restart app
