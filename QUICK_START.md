# YTDownloader - Quick Start

## 1. Build (First Time Only)

```bash
git clone https://github.com/opsspb/ytd-saf.git
cd ytd-saf
brew install librsvg
./generate_icons.sh
open YTDownloader.xcodeproj
```

In Xcode:
1. Select both targets → Signing & Capabilities → Choose your Team
2. Press ⌘R to build and run

## 2. Enable Extension (First Time Only)

1. Safari → Settings → Extensions → Enable **YTDownloader**
2. Safari → Develop → **Allow Unsigned Extensions**

## 3. Use It

1. Go to any YouTube video
2. Click the **YD** button
3. Switch to YTDownloader app to see progress
4. Find downloaded video in ~/Downloads

## Settings

YTDownloader → Settings:
- **Download Location**: Change where videos are saved
- **Cookie Mode**: Enable for age-restricted videos (+ grant Full Disk Access)
- **Concurrent Downloads**: 1-5 simultaneous downloads

## Troubleshooting

**No YD button?**
- Refresh page (⌘⇧R)
- Check Safari Settings → Extensions
- Enable Develop → Allow Unsigned Extensions

**Downloads fail?**
- App retries automatically (watch status)
- For age-restricted: enable Safari cookies in Settings
- For 403/429: wait a few minutes

**Videos won't play?**
- Use Infuse, IINA, or VLC (not QuickTime)
- MKV files contain VP9/AV1/Opus codecs

## Full Documentation

- **BUILD_INSTRUCTIONS.md**: Detailed step-by-step guide
- **VERIFICATION.md**: Testing plan and troubleshooting
- **README.md**: Complete feature documentation

## File Locations

- Videos: `~/Downloads/`
- Binaries: `~/Library/Application Support/YTDownloader/bin/`
- Settings: `~/Library/Application Support/YTDownloader/settings.json`

## Reset Everything

```bash
rm -rf ~/Library/Application\ Support/YTDownloader
```

Then restart the app.
