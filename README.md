# YTDownloader

A native macOS app with a Safari Web Extension that downloads YouTube videos in the highest quality using [yt-dlp](https://github.com/yt-dlp/yt-dlp). YouTube only in v1.

## Features

- **YD button** on the YouTube watch page and under the channel avatar on feed cards (card clicks do not navigate, start hover preview, or trigger ads)
- **Best video**: highest resolution, then fps, then video bitrate
- **Original-language audio**: `language_preference >= 0`, then highest audio bitrate
- **Merged MKV** with `ffmpeg -c copy` (no transcoding)
- **Persistent queue** in the app (Safari can close)
- **Cookies**: Safari extension sends site cookies with each download (primary, no Full Disk Access); fallback: Safari store (`--cookies-from-browser`, needs FDA) or `cookies.txt`
- **Retries**: random(5…30) + 60×(n−1) seconds, max 10, for 403/429/network
- **Self-installs** official yt-dlp + ffmpeg/ffprobe into `~/Library/Application Support/YTDownloader/bin`

## Requirements

- macOS 13 Ventura or later
- Xcode 15 or later to build
- Safari 17 or later
- A free personal Apple ID is enough (no paid Developer Program)

## Build (free personal team)

1. `open YTDownloader.xcodeproj`
2. Both targets already use **Team** `4DVJSNGT52` (Pavel’s Personal Team) and **Automatic** signing so TCC grants survive rebuilds
3. Scheme **YTDownloader** → **Product → Run** (⌘R)
4. Headless/CI builds without an identity: pass `CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=`

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

1. YD click handler calls `browser.permissions.request({ origins: […] })` **inside the user gesture** so Safari shows its standard host-permission prompt (YouTube / Google / VK)
2. Content script messages the background worker, which collects cookies via `browser.cookies` (including all cookie stores)
3. Background `sendNativeMessage`s the payload to `SafariWebExtensionHandler`, which writes Netscape cookies into the macOS team-prefixed App Group (`$(TeamIdentifierPrefix)com.ytdownloader.shared`, e.g. `4DVJSNGT52.com.ytdownloader.shared`) and returns a short `cookieRef`
4. A compact `ytdownloader://download?videoId=…&url=…&cookieRef=…` launches the host app (legacy `cookies=` base64url remains as fallback when the App Group is unavailable, e.g. unsigned CI)
5. On sign-in errors the app reads the App Group file (or URL payload), writes a private temp `cookies.txt`, and retries with `--cookies`

A sandboxed `NSWorkspace.open` from the appex is unreliable. Opening the custom scheme from JS is the supported launch path.

## Settings

**YTDownloader → Settings** or the gear icon:

- Download folder (default `~/Downloads`)
- Cookie mode fallback: None / Safari / cookies.txt
- Concurrent downloads (1–5)

Prefer the extension cookie prompt. Safari-store fallback: **System Settings → Privacy & Security → Full Disk Access** → add YTDownloader, then restart the app.

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
