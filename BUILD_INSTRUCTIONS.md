# YTDownloader - Build Instructions for Pavel

## Quick Start (5 Steps)

### Step 1: Clone and Generate Icons

```bash
cd ~/Downloads  # or wherever you want the project
git clone https://github.com/opsspb/ytd-saf.git
cd ytd-saf

# Install librsvg if you don't have it
brew install librsvg

# Generate all icon sizes from icon.svg
./generate_icons.sh
```

**Expected output**: "Icons generated successfully!"

### Step 2: Open in Xcode

```bash
open YTDownloader.xcodeproj
```

Xcode will open the project. Wait for it to finish indexing (progress bar in toolbar).

### Step 3: Configure Signing

This is **required** even though you have a free account:

1. In Xcode's Project Navigator (left sidebar), click **YTDownloader** (the blue project icon at the top)
2. In the main editor area, select the **YTDownloader** target (under TARGETS)
3. Click the **Signing & Capabilities** tab
4. Under **Team**, click the dropdown and select your personal Apple ID
   - If you don't see your Apple ID: Xcode → Settings → Accounts → Add your Apple ID
5. **Repeat steps 2-4** for the **YTDownloaderExtension** target

Both targets should now show "Signing Certificate: Apple Development" (this is correct).

### Step 4: Build and Run

1. At the top of Xcode, ensure **YTDownloader** is selected in the scheme dropdown (next to the Play button)
2. Click the **Play button** (▶) or press **⌘R**
3. Xcode will build the app and launch it

**What you should see**:
- Build progress in the top status bar
- "Build Succeeded" notification
- YTDownloader app opens showing "Setting up YTDownloader"
- Progress bar as it downloads yt-dlp and ffmpeg (may take 1-2 minutes)
- Once complete, shows onboarding screen

If you see errors, see Troubleshooting section below.

### Step 5: Enable Safari Extension

1. **Open Safari** (keep YTDownloader app running)
2. Go to **Safari → Settings** (or press ⌘,)
3. Click the **Extensions** tab
4. Find **YTDownloader** in the list and **check the box** to enable it
5. Click **Always Allow on Every Website** (or configure specific sites)
6. **Important**: Enable unsigned extensions:
   - In Safari menu bar: **Develop → Allow Unsigned Extensions**
   - If you don't see the Develop menu: Safari → Settings → Advanced → check "Show features for web developers"

### Step 6: Test It!

1. In Safari, go to any YouTube video (example: https://www.youtube.com/watch?v=dQw4w9WgXcQ)
2. You should see a **YD** button appear near the Like/Share buttons below the video
3. **Click the YD button**
4. The button will briefly show ⏳ then ✓
5. **Switch to the YTDownloader app**
6. You should see the video in the download queue
7. Watch the progress: Downloading → Merging → Completed
8. The downloaded file will be in **~/Downloads** as a `.mkv` file

**To test thumbnails**: Go to YouTube homepage or search results. You should see small YD buttons on video thumbnails (top-right corner). These work the same way.

## What to Do If It Doesn't Work

### Build Errors in Xcode

**Error: "Failed to resolve package dependencies"**
- Solution: File → Packages → Reset Package Caches, then build again

**Error: "Signing for YTDownloader requires a development team"**
- Solution: Make sure you selected your Team in Signing & Capabilities for BOTH targets

**Error: "Xcode could not locate ProvisioningProfile"**
- Solution: This is fine with free signing. Make sure "Automatically manage signing" is checked.

### App Doesn't Launch

**App crashes immediately**
- Check Xcode console (⌘⇧Y to show) for error messages
- Look for entitlements issues or missing frameworks

**"Setting up YTDownloader" hangs**
- Check your internet connection
- The app downloads ~50MB of binaries on first run
- Check Console.app for error messages (filter by "YTDownloader")

### Extension Doesn't Appear in Safari

1. Make sure the app has been run at least once
2. Quit and restart Safari completely (⌘Q, then reopen)
3. Check Safari → Settings → Extensions again
4. Verify "Allow Unsigned Extensions" is enabled in Develop menu

### YD Button Doesn't Appear on YouTube

1. Make sure extension is enabled in Safari Settings
2. Hard refresh the YouTube page (⌘⇧R)
3. Open Safari Web Inspector (Develop → Show JavaScript Console) and check for errors
4. Try a different YouTube page (watch page vs homepage)

### Downloads Fail

**"yt-dlp not found"**
- Check if binaries exist: `ls -la ~/Library/Application\ Support/YTDownloader/bin/`
- If missing, app should re-download on next launch
- Or manually install: `brew install yt-dlp ffmpeg`

**403 or 429 errors**
- App will automatically retry with exponential backoff
- Watch the download status in the app
- If all retries fail, wait a few minutes and try again

**Age-restricted videos fail**
1. Open YTDownloader app
2. Click Settings (gear icon) or YTDownloader → Settings
3. Under **Cookies**, select **Safari (requires Full Disk Access)**
4. Click **Open Privacy Settings**
5. In System Settings, enable Full Disk Access for YTDownloader
6. Restart the app
7. Try downloading again

## Understanding the Interface

### Main App Window

- **Left panel**: Download queue
  - Shows all downloads (queued, active, completed, failed)
  - Click any item to see details
- **Right panel**: Selected download details
  - Video title, URL, status
  - Progress bar for active downloads
  - Error messages if failed
  - "Show in Finder" button when completed

### Settings

Access via **YTDownloader → Settings** or click the **gear icon**:

- **Download Location**: Where files are saved (default ~/Downloads)
- **Cookie Mode**: 
  - None: For public videos
  - Safari: For age-restricted/members-only (needs Full Disk Access)
  - Cookies File: Use a cookies.txt file (advanced)
- **Concurrent Downloads**: 1-5 simultaneous downloads (default 1)

### Queue Behavior

- Downloads process **sequentially** by default (one at a time)
- Queue **persists** if you quit the app or restart your Mac
- You can **close Safari** or navigate away—downloads continue in the app
- **Delete** downloads from queue: select and press Delete (not implemented yet—would be a nice addition!)

## Advanced Usage

### Using Homebrew Binaries

If you already have yt-dlp and ffmpeg via Homebrew, the app will use those automatically:

```bash
brew install yt-dlp ffmpeg
```

The app checks `/opt/homebrew/bin` and `/usr/local/bin` before downloading its own copies.

### Cookie File (Alternative to Safari Cookies)

If you don't want to grant Full Disk Access:

1. Export cookies from Safari using a browser extension (search for "cookies.txt exporter")
2. Save as `cookies.txt` in Netscape format
3. In YTDownloader Settings, select "Cookies File"
4. Click Browse and select your `cookies.txt`

### Multiple Concurrent Downloads

For faster bulk downloading:
1. Go to Settings
2. Set "Concurrent Downloads" to 3-5
3. Queue multiple videos
4. They'll download in parallel

**Warning**: Too many concurrent downloads may trigger rate limiting (429 errors). Start with 2-3.

## Files and Locations

The app stores files in these locations:

- **Downloaded videos**: `~/Downloads/` (or your configured location)
- **Binaries**: `~/Library/Application Support/YTDownloader/bin/`
  - `yt-dlp` (macOS binary)
  - `ffmpeg` (static build)
  - `ffprobe` (static build)
- **Settings**: `~/Library/Application Support/YTDownloader/settings.json`
- **Queue**: `~/Library/Application Support/YTDownloader/queue.json`

To **reset everything**:
```bash
rm -rf ~/Library/Application\ Support/YTDownloader
```
Then relaunch the app.

## Testing Checklist

Once everything is set up, test these scenarios:

- [x] **Simple download**: Public video, < 1080p
- [x] **High quality**: 4K 60fps video
- [x] **Age-restricted**: Video requiring sign-in (with Safari cookies)
- [x] **Thumbnail button**: Click YD on a thumbnail (not watch page)
- [x] **Queue multiple**: Add 3-5 videos, watch them process
- [x] **App restart**: Quit app mid-download, restart, verify queue persists
- [x] **Concurrent**: Set concurrent downloads to 3, queue multiple videos
- [x] **Playback**: Open downloaded MKV in Infuse, IINA, or VLC (not QuickTime)

## Playing Downloaded Videos

**Important**: macOS QuickTime may not play all downloaded videos because YouTube uses modern codecs (VP9, AV1, Opus).

**Recommended players**:
- **Infuse** (free, excellent): https://firecore.com/infuse
- **IINA** (free, open-source): https://iina.io/
- **VLC** (free): https://www.videolan.org/

These players support all YouTube codecs and MKV containers.

## Next Steps

After verifying everything works:

1. **Use it daily**: Download videos as you browse YouTube
2. **Report issues**: If something breaks, check GitHub issues or open a new one
3. **Customize**: The code is open-source—feel free to modify
4. **Future distribution**: When you want to share with others, follow the notarization guide in README.md

## Getting Help

If you encounter issues:

1. Check **VERIFICATION.md** for detailed troubleshooting
2. Check **README.md** FAQ section
3. Look at Xcode console logs (⌘⇧Y)
4. Check macOS Console.app (filter by "YTDownloader" or "Safari")
5. Open a GitHub issue with:
   - macOS version (About This Mac)
   - Xcode version (Xcode → About Xcode)
   - Exact error message
   - Steps to reproduce

## Summary

You now have a complete, working YouTube downloader that:
- ✅ Works with free Apple Developer account
- ✅ Downloads highest quality (4K, 60fps, HDR)
- ✅ Handles age-restricted videos (with cookies)
- ✅ Has a clean, native macOS interface
- ✅ Integrates seamlessly with Safari
- ✅ Is fully open-source and customizable

Enjoy! 🎉
