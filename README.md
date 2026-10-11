# YTDownloader

A native macOS app with Safari Web Extension that downloads YouTube videos in the highest quality using [yt-dlp](https://github.com/yt-dlp/yt-dlp).

## Features

- **One-click downloads**: Click "YD" button on any YouTube video (watch page or thumbnails)
- **Best quality**: Automatically selects highest resolution, frame rate, and bitrate
- **Original audio**: Downloads the original language audio track, not dubbed versions
- **Smart format selection**: VP9/AV1 video + Opus audio, merged to MKV without transcoding
- **Persistent queue**: Downloads continue even if you close Safari or navigate away
- **Cookie support**: Handles age-restricted and members-only videos with Safari cookies
- **Auto-retry**: Intelligent retry with exponential backoff for transient errors
- **Self-sufficient**: Automatically downloads and updates yt-dlp and ffmpeg

## Requirements

- macOS 13.0 (Ventura) or later
- Xcode 15.0 or later (for building)
- Safari 17.0 or later

## Building the App

### 1. Generate App Icons

First, generate the app icons from the included SVG:

```bash
# Install librsvg (if not already installed)
brew install librsvg

# Generate all icon sizes
./generate_icons.sh
```

### 2. Open in Xcode

```bash
open YTDownloader.xcodeproj
```

### 3. Configure Signing

1. Select the **YTDownloader** project in the Project Navigator
2. Select the **YTDownloader** target
3. Go to **Signing & Capabilities** tab
4. Under **Team**, select your personal Apple ID or team
5. Repeat for the **YTDownloaderExtension** target

**Note**: You can use a free Apple Developer account (personal team). No paid account required for personal use.

### 4. Build and Run

1. Select **YTDownloader** scheme
2. Click **Product → Run** (⌘R)
3. The app will build and launch

## Enabling the Extension in Safari

### Option 1: Via Safari Preferences

1. Open Safari
2. Go to **Safari → Settings** (⌘,)
3. Click **Extensions** tab
4. Find **YTDownloader** and enable it
5. Click **Always Allow on Every Website** (or configure per-site)

### Option 2: Via Developer Menu (Required for unsigned extensions)

Since you're building with a free signing team, Safari needs to allow unsigned extensions:

1. Enable Safari's Developer menu:
   - **Safari → Settings → Advanced**
   - Check **"Show features for web developers"**
2. In the menu bar: **Develop → Allow Unsigned Extensions**
3. Follow Option 1 steps above to enable the extension

## Using YTDownloader

### Downloading Videos

1. Navigate to any YouTube video or feed page
2. Click the **YD** button that appears:
   - On watch pages: next to Like/Share buttons
   - On thumbnails: top-right corner of video thumbnails
3. The button will show status: ⏳ (queued) → ✓ (added)
4. Open the YTDownloader app to see download progress

### App Interface

The main window shows:

- **Download queue**: All queued, active, and completed downloads
- **Progress**: Real-time progress for active downloads
- **Status**: Queued / Downloading XX% / Merging / Completed / Failed
- **Details**: Click any item to see full info and errors

### Settings

Access via **YTDownloader → Settings** or the gear icon:

- **Download Location**: Where files are saved (default: `~/Downloads`)
- **Cookie Mode**:
  - **None**: Default, works for most public videos
  - **Safari**: Use Safari cookies for age-restricted/members-only videos (requires Full Disk Access)
  - **Cookies File**: Path to a `cookies.txt` file (Netscape format)
- **Concurrent Downloads**: How many videos download simultaneously (1-5)

### Granting Full Disk Access (for Safari cookies)

If you enable Safari cookie mode:

1. Open **System Settings → Privacy & Security**
2. Scroll to **Full Disk Access**
3. Click **+** and add **YTDownloader.app**
4. Restart the app

## How It Works

### Architecture

```
┌─────────────────┐         ┌──────────────────┐
│  Safari Web     │         │   Native macOS   │
│   Extension     │◄───────►│       App        │
│                 │  Native │                  │
│  - Content JS   │Messages │  - SwiftUI       │
│  - Background   │         │  - Download      │
│    Worker       │         │    Manager       │
└─────────────────┘         │  - yt-dlp        │
                            │  - ffmpeg        │
                            └──────────────────┘
```

1. **Content script** (`content.js`) injects YD buttons on YouTube pages
2. **Background worker** (`background.js`) handles messages from buttons
3. **Native messaging** sends download requests to the macOS app via `DistributedNotificationCenter`
4. **Download Manager** queues downloads and orchestrates yt-dlp/ffmpeg
5. **Format Selector** parses yt-dlp JSON and picks optimal formats
6. **Binary Manager** ensures yt-dlp and ffmpeg are available

### Format Selection Logic

The app selects video and audio formats in strict priority order:

**Video** (highest first):
1. Resolution (height in pixels)
2. Frame rate (fps)
3. Video bitrate (vbr)

**Audio** (original language):
1. Original/default language track (`language_preference >= 0`)
2. Highest audio bitrate (abr)

The selected video and audio streams are downloaded separately and merged with ffmpeg (`-c copy`) without transcoding, preserving quality.

### Retry Strategy

For transient errors (403, 429, network issues):

- **Attempt 1**: random delay 5-30 seconds
- **Attempt 2**: random 5-30s + 60s = 65-90s
- **Attempt 3**: random 5-30s + 120s = 125-150s
- ...up to **10 attempts**

For cookie-required errors (age-restricted, members-only, CAPTCHA):
- Automatically retries **once** with cookies (if enabled)

### Binary Management

On first run, the app:

1. Checks for Homebrew installations of `yt-dlp`, `ffmpeg`, `ffprobe` in `/opt/homebrew/bin` and `/usr/local/bin`
2. If not found, downloads official binaries:
   - **yt-dlp**: Latest macOS binary from [yt-dlp releases](https://github.com/yt-dlp/yt-dlp/releases)
   - **ffmpeg/ffprobe**: Static builds from [evermeet.cx](https://evermeet.cx/ffmpeg/)
3. Stores binaries in `~/Library/Application Support/YTDownloader/bin/`

Binaries are made executable (`chmod 755`) after download. The app does NOT use App Sandbox to allow execution of downloaded binaries.

## Permissions

### App Entitlements

- **No App Sandbox**: Required to execute downloaded binaries (yt-dlp, ffmpeg)
- **Network Client**: Download videos and binaries
- **Files (Downloads, User-Selected)**: Write downloaded videos

### Extension Permissions

- **Native Messaging**: Communicate with the host app
- **Storage**: Persist settings
- **Host Permissions**: `*://*.youtube.com/*`

## Testing

### Unit Tests

The core logic is in the `YTDownloaderCore` Swift package with comprehensive tests:

```bash
# Run tests via Xcode
# Select YTDownloaderCore scheme → Product → Test (⌘U)

# Or via command line
cd YTDownloaderCore
swift test
```

Tests cover:
- **Format selection**: 4K, HDR, high FPS, multi-language audio
- **Retry strategy**: Delay calculation, attempt limits
- **Error classification**: Cookie-required, transient, fatal errors

### Manual Testing

The included `.github/workflows/build.yml` runs on macOS runners and:
1. Builds the app
2. Runs all unit tests
3. Archives the build (uploadable artifact)

## Project Structure

```
ytd-saf/
├── YTDownloader.xcodeproj/          # Xcode project
├── YTDownloader/
│   ├── YTDownloader/                # Main app target
│   │   ├── YTDownloaderApp.swift
│   │   ├── ContentView.swift
│   │   ├── DownloadManager.swift
│   │   ├── BinaryManager.swift
│   │   ├── NativeMessaging.swift
│   │   ├── SettingsView.swift
│   │   ├── YTDownloader.entitlements
│   │   └── Info.plist
│   ├── YTDownloaderExtension/       # Safari extension target
│   │   ├── SafariWebExtensionHandler.swift
│   │   ├── Resources/
│   │   │   ├── manifest.json
│   │   │   ├── content.js
│   │   │   ├── background.js
│   │   │   ├── styles.css
│   │   │   └── icon-*.png
│   │   ├── YTDownloaderExtension.entitlements
│   │   └── Info.plist
│   └── Resources/
│       └── Assets.xcassets/
├── YTDownloaderCore/                # Swift package (core logic)
│   ├── Package.swift
│   ├── Sources/
│   │   └── YTDownloaderCore/
│   │       ├── Models.swift
│   │       ├── FormatSelector.swift
│   │       ├── RetryStrategy.swift
│   │       └── ErrorClassifier.swift
│   └── Tests/
│       └── YTDownloaderCoreTests/
│           ├── FormatSelectorTests.swift
│           ├── RetryStrategyTests.swift
│           ├── ErrorClassifierTests.swift
│           └── Fixtures/
├── icon.svg                         # Source icon (1024x1024)
├── generate_icons.sh                # Icon generation script
├── .github/workflows/build.yml      # CI workflow
├── LICENSE                          # MIT License
└── README.md                        # This file
```

## Distribution

### Signing and Notarization (Future)

To distribute outside personal use:

1. Enroll in the [Apple Developer Program](https://developer.apple.com/programs/) ($99/year)
2. Create a **Developer ID Application** certificate
3. In Xcode, change **Code Signing Identity** to your Developer ID
4. Archive the app: **Product → Archive**
5. Notarize with Apple:
   ```bash
   xcrun notarytool submit YTDownloader.zip --keychain-profile "notary-profile" --wait
   xcrun stapler staple YTDownloader.app
   ```
6. Distribute the notarized `.app` or create a DMG

No code restructuring needed—just change signing settings.

### Distribution Options

- **Direct Download**: Zip the notarized `.app`, host on GitHub Releases
- **Mac App Store**: Requires additional entitlements and review (not recommended for yt-dlp use case)
- **Homebrew Cask**: Submit a cask formula after notarization

## Troubleshooting

### Extension Not Appearing in Safari

- Make sure the app has been run at least once
- Check **Safari → Settings → Extensions**
- Enable **Develop → Allow Unsigned Extensions** (for free signing)
- Restart Safari

### "yt-dlp not found" Error

- Wait for first-run setup to complete (progress shown in app)
- Check `~/Library/Application Support/YTDownloader/bin/` for binaries
- Manually install via Homebrew: `brew install yt-dlp ffmpeg`

### Age-Restricted Videos Fail

- Enable **Safari cookies** in Settings
- Grant **Full Disk Access** in System Settings
- Ensure you're signed into YouTube in Safari

### Download Fails with 403/429

- The app will automatically retry with exponential backoff
- If all retries fail, wait a few minutes and try again
- Consider reducing concurrent downloads in Settings

### Downloaded Binaries Won't Execute

- Check entitlements: App Sandbox must be **disabled**
- Verify binaries are executable: `ls -l ~/Library/Application\ Support/YTDownloader/bin/`
- Manually set: `chmod 755 ~/Library/Application\ Support/YTDownloader/bin/*`

## Development

### Building from Source

```bash
git clone https://github.com/posmolosv/ytd-saf.git
cd ytd-saf
./generate_icons.sh
open YTDownloader.xcodeproj
```

### Running Tests

```bash
cd YTDownloaderCore
swift test
```

### Debugging Native Messaging

Messages between extension and app use `DistributedNotificationCenter`. To debug:

1. Add `print()` statements in `NativeMessaging.swift`
2. View logs: **Window → Devices and Simulators → Open Console**
3. Filter by process: `YTDownloader`

### Modifying Format Selection

Edit `YTDownloaderCore/Sources/YTDownloaderCore/FormatSelector.swift` and run tests:

```bash
cd YTDownloaderCore
swift test --filter FormatSelectorTests
```

## License

MIT License - see [LICENSE](LICENSE) file.

Copyright © 2026 Pavel Osmolovskii

## Credits

- [yt-dlp](https://github.com/yt-dlp/yt-dlp): Video download engine (Unlicense)
- [FFmpeg](https://ffmpeg.org/): Media processing (LGPL v2.1+)
- Icon: Custom design

## FAQ

**Q: Is this legal?**  
A: Downloading videos for personal use is generally legal. Respect YouTube's Terms of Service and copyright laws. This tool is for personal archival only.

**Q: Why MKV instead of MP4?**  
A: MKV is a free container that supports all codecs YouTube uses (VP9, AV1, Opus) without transcoding. Quality is paramount.

**Q: Can I download private/unlisted videos?**  
A: If you can watch it in Safari while signed in, the app can download it with Safari cookies enabled.

**Q: Does it support playlists?**  
A: Not yet. Click YD on each video individually.

**Q: Will this be on the Mac App Store?**  
A: Unlikely. The App Store prohibits apps that download YouTube videos.

**Q: Can I contribute?**  
A: Yes! Pull requests welcome. See [GitHub repository](https://github.com/posmolosv/ytd-saf).
