# YTDownloader

A native macOS app with a Safari Web Extension that downloads YouTube videos in the highest quality using [yt-dlp](https://github.com/yt-dlp/yt-dlp). YouTube only in v1.

## Features

- **YD button** on the YouTube watch page and under the channel avatar on feed cards (card clicks do not navigate, start hover preview, or trigger ads)
- **Best video**: highest resolution, then fps, then video bitrate
- **Original-language audio**: `language_preference >= 0`, then highest audio bitrate
- **Merged MKV** with `ffmpeg -c copy` (no transcoding)
- **Persistent queue** in the app (Safari can close)
- **Cookies**: none, Safari (`--cookies-from-browser safari`, needs Full Disk Access), or `cookies.txt`
- **Retries**: random(5…30) + 60×(n−1) seconds, max 10, for 403/429/network
- **Self-installs** official yt-dlp + ffmpeg/ffprobe into `~/Library/Application Support/YTDownloader/bin`

## Requirements

- macOS 13 Ventura or later
- Xcode 15 or later to build
- Safari 17 or later
- A free personal Apple ID is enough (no paid Developer Program)

## Build (free personal team)

1. `open YTDownloader.xcodeproj`
2. Select the **YTDownloader** target → **Signing & Capabilities** → **Team** → your personal Apple ID
3. Repeat for **YTDownloaderExtension** (same team)
4. Scheme **YTDownloader** → **Product → Run** (⌘R)

Icons: `./generate_icons.sh` (or `generate_icons_python.py`) if `Assets.xcassets` is missing sizes.

First launch downloads yt-dlp from GitHub and ffmpeg/ffprobe from evermeet.cx, retrying with backoff, then falling back to [martin-riedl.de](https://ffmpeg.martin-riedl.de/) macOS arm64/amd64 zips. Each binary is chmod’d, de-quarantined, and checked with `-version` / `--version`. A failed setup shows the error and **Retry Setup**. Homebrew copies in `/opt/homebrew/bin` or `/usr/local/bin` are used when present.

## Enable the Safari extension

Free-team builds are unsigned from Safari’s point of view:

1. **Safari → Settings → Advanced** → **Show features for web developers**
2. **Develop → Allow Unsigned Extensions**
3. **Safari → Settings → Extensions** → enable **YTDownloader**
4. Allow it on `youtube.com`

The app must have been Run at least once so Safari can see the embedded `.appex`.

## How a click reaches the app

App Groups are not available on a free personal team, so the extension does **not** share a container with the app.

1. Content script sends `{ action: "download", videoId, url }`
2. Background script (and the page) open `ytdownloader://download?videoId=…&url=…`
3. Launch Services starts the app if it is not running
4. `AppDelegate` / `onOpenURL` enqueue the item; the queue keeps going if you change Safari tabs

A sandboxed `NSWorkspace.open` from the appex is unreliable (a sandboxed helper aborts). Opening the custom scheme from JS is the supported path. The native `SafariWebExtensionHandler` still tries `NSWorkspace` as a backup.

## Settings

**YTDownloader → Settings** or the gear icon:

- Download folder (default `~/Downloads`)
- Cookie mode: None / Safari / cookies.txt
- Concurrent downloads (1–5)

Safari cookies: **System Settings → Privacy & Security → Full Disk Access** → add YTDownloader, then restart the app.

## Tests

```bash
cd YTDownloaderCore && swift test
swift Scripts/run-content-tests.swift   # card YD button must not navigate
```

End-to-end downloads (same `VideoDownloadPipeline` as the app):

```bash
cd YTDownloaderCore
swift run ytd-e2e --skip-homebrew --output /tmp/ytd-e2e \
  "https://www.youtube.com/watch?v=jNQXAC9IVRw"
```

See [TESTING.md](TESTING.md) for what was verified on this Mac and Pavel’s Safari checklist.

## License

MIT. yt-dlp is Unlicense; FFmpeg is LGPL.
