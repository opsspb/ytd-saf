# YTDownloader - Complete Testing Checklist for Pavel

## What Was Done (Automated Verification)

### ✅ Architecture Fixed for Free Apple ID Signing
- **Problem**: Original code used App Groups which require paid Apple Developer account
- **Solution**: Switched to custom URL scheme (`ytdownloader://`) which works with free signing
- **Impact**: You can now build and run with just your personal Apple ID (no $99/year fee needed)

### ✅ Build Verification
- Xcode project builds successfully without errors
- Both targets compile: YTDownloader (app) and YTDownloaderExtension (extension)
- No sandbox issues or entitlement conflicts

### ✅ Swift Package Tests
All 20 unit tests pass in YTDownloaderCore:
- ✅ ErrorClassifier: 9 tests (age-restricted, members-only, CAPTCHA, 403, 429, network errors)
- ✅ FormatSelector: 6 tests (4K HDR, high FPS, audio bitrate, original language)
- ✅ RetryStrategy: 5 tests (transient errors, max attempts, delay calculation)

### ✅ Download Pipeline Verification
Tested with real YouTube videos (using Homebrew yt-dlp/ffmpeg):
- ✅ Video info fetching (JSON parsing)
- ✅ Format selection logic (best resolution → fps → bitrate)
- ✅ Audio format selection (original language, best bitrate)
- ✅ ffmpeg merge command (`-c copy` without transcoding)
- ✅ Error classification patterns
- ✅ Retry strategy (exponential backoff: 5-30s + 60*(n-1), max 10 attempts)

### ✅ CI Pipeline Updated
- Fixed `integration-test` job to properly skip when YouTube blocks GitHub runners
- Uses conditional execution instead of silent exit(0)
- CI will be green for the right reasons

### ⚠️ Not Yet Verified (Requires Your Mac)
- Xcode app signing with your personal team
- Safari extension loading and registration
- Extension ↔ App communication via URL scheme
- First-run binary bootstrap (downloading yt-dlp/ffmpeg from official sources)
- Gatekeeper/quarantine attribute handling
- End-to-end download in the app's UI

---

## Your Testing Steps (Click-by-Click)

### Part 1: Build and Run (10 minutes)

#### Step 1: Open in Xcode
```bash
cd ~/Developer/ytd-saf
open YTDownloader.xcodeproj
```

Wait for Xcode to finish indexing (progress bar at top).

#### Step 2: Configure Signing (REQUIRED)

1. **In Xcode Project Navigator** (left sidebar), click the **YTDownloader** project (blue icon at top)
2. **Select the "YTDownloader" target** (under TARGETS)
3. **Go to "Signing & Capabilities" tab**
4. **Under "Team"**, click the dropdown:
   - If your Apple ID is not listed: **Xcode → Settings → Accounts → [+] Add Apple ID**
   - Select your personal Apple ID (will show as "Your Name (Personal Team)")
5. **Repeat for "YTDownloaderExtension" target**:
   - Select it in TARGETS list
   - Signing & Capabilities tab
   - Same Team selection

**Expected result**: Both targets show "Signing Certificate: Apple Development"

#### Step 3: Build and Run
1. **At the top of Xcode**, ensure "YTDownloader" is selected in the scheme dropdown (next to Play button)
2. **Click the Play button ▶** (or press ⌘R)

**What should happen**:
- Build progress in top status bar
- "Build Succeeded" notification
- YTDownloader app launches
- Shows "Setting up YTDownloader" with progress bar
- Downloads yt-dlp (~10MB) and ffmpeg (~50MB) from official sources (1-2 minutes)
- After download completes, shows onboarding screen

**If build fails**, check:
- Both targets have the same Team selected
- "Automatically manage signing" is checked
- You're connected to the internet (for package resolution)

**If app crashes on launch**, check:
- Xcode console (⌘⇧Y) for error messages
- Look for entitlement or binary download errors

#### Step 4: Verify Binary Download
```bash
ls -lh ~/Library/Application\ Support/YTDownloader/bin/
```

**Expected output**:
```
-rwxr-xr-x  yt-dlp     (~10MB)
-rwxr-xr-x  ffmpeg     (~50MB)
-rwxr-xr-x  ffprobe    (~1MB)
```

All three files should be executable (rwxr-xr-x).

**If files are missing**:
- Check Xcode console for download errors
- Check your internet connection
- Try deleting the folder and relaunching the app:
  ```bash
  rm -rf ~/Library/Application\ Support/YTDownloader
  ```

**Verify executability**:
```bash
~/Library/Application\ Support/YTDownloader/bin/yt-dlp --version
~/Library/Application\ Support/YTDownloader/bin/ffmpeg -version | head -1
```

Should print version numbers without "Permission denied" errors.

---

### Part 2: Safari Extension Setup (5 minutes)

#### Step 1: Enable Developer Features
1. **Open Safari**
2. **Safari → Settings** (or ⌘,)
3. **Go to "Advanced" tab**
4. **Check "Show features for web developers"**

#### Step 2: Allow Unsigned Extensions
1. **In Safari menu bar**: **Develop → Allow Unsigned Extensions**
2. You'll see a confirmation dialog - click "Allow"

**Why?** You're using free signing, so the extension isn't notarized. This is normal for development.

#### Step 3: Enable the Extension
1. **Safari → Settings** (⌘,)
2. **Go to "Extensions" tab**
3. **Find "YTDownloader"** in the left list
4. **Check the box** to enable it
5. **Click "Always Allow on Every Website"** (or click "Always Allow on youtube.com" if prompted)

**If extension is not listed**:
- Make sure YTDownloader app has been run at least once
- Quit Safari completely (⌘Q) and reopen
- Check System Settings → Privacy & Security → Extensions (should show YTDownloader)
- Try running the app again from Xcode

#### Step 4: Verify Extension Loaded
```bash
# Check Safari's extension list
pluginkit -m -p com.apple.Safari.extension | grep -i ytdownloader
```

**Expected**: Shows extension bundle ID (`com.ytdownloader.app.extension`)

**If empty**, check:
- Extension is enabled in Safari Settings
- YTDownloader app is in /Applications or ~/Library/Developer/Xcode/DerivedData/...
- Safari was restarted after enabling

---

### Part 3: Test Download Flow (10 minutes)

#### Test 1: Watch Page Button
1. **In Safari**, go to: https://www.youtube.com/watch?v=dQw4w9WgXcQ
2. **Look for the "YD" button** below the video (near Like/Share buttons)

**If button doesn't appear**:
- Hard refresh the page (⌘⇧R)
- Open Safari Web Inspector:
  - **Develop → Show JavaScript Console**
  - Check for error messages (red text)
- Make sure extension is enabled and has permission for youtube.com
- Try a different YouTube video

#### Test 2: Click to Download
1. **Click the "YD" button**
2. Button should briefly show **⏳** (loading), then **✓** (success)
3. **Switch to YTDownloader app** (should open automatically)

**What should happen**:
- Video appears in the download queue (left panel)
- Status changes: Queued → Downloading → Merging → Completed
- Progress bar shows percentage
- Video title appears after info is fetched

**If app doesn't open**:
- URL scheme might not be registered. Try:
  ```bash
  open "ytdownloader://download?videoId=test&url=https://www.youtube.com/watch?v=test"
  ```
  Should open the app (even if download fails - that's OK, just testing URL scheme)

**If download fails**:
- Check error message in the app (click the failed item)
- Common errors:
  - "yt-dlp not found": Binary download didn't complete. Relaunch app.
  - "403 Forbidden": YouTube rate limit. App will retry automatically.
  - "Age-restricted": Need to enable Safari cookies (see Part 4)

#### Test 3: Verify Downloaded File
1. **When status shows "Completed"**, click "Show in Finder" (or check ~/Downloads manually)
2. **File should be**: `{Title}_{VideoID}.mkv`

**Verify quality**:
```bash
ffprobe ~/Downloads/*dQw4w9WgXcQ.mkv 2>&1 | grep Stream
```

**Expected output**: Shows video and audio streams, e.g.:
```
Stream #0:0: Video: vp9, yuv420p, 1920x1080, ...
Stream #0:1: Audio: opus, 48000 Hz, stereo, ...
```

**Test playback**: Open in **IINA**, **Infuse**, or **VLC** (not QuickTime - it doesn't support VP9/Opus).

#### Test 4: Thumbnail Button (Feed Pages)
1. **In Safari**, go to: https://www.youtube.com
2. **Look for small "YD" buttons** on video thumbnails (top-right corner)
3. **Hover over a thumbnail** - button should appear
4. **Click the YD button WITHOUT clicking the thumbnail itself**

**Important**: Clicking should NOT navigate to the video or start preview. The button should trigger download directly.

**If buttons don't appear**:
- Same troubleshooting as Test 1
- Check browser console for errors
- The content script might not be injecting properly

---

### Part 4: Advanced Features (Optional, 10 minutes)

#### Test 5: Age-Restricted Video (Requires Full Disk Access)
1. Find an age-restricted video (e.g., search for music videos with explicit content)
2. Try downloading without cookies - should fail with "Age-restricted" error
3. **In YTDownloader app**: **Settings** (gear icon or YTDownloader → Settings)
4. **Under "Cookies"**, select **"Safari"**
5. **Click "Open Privacy Settings"** (or go manually: System Settings → Privacy & Security → Full Disk Access)
6. **Click the lock** to make changes (enter password)
7. **Click [+]**, navigate to and add **YTDownloader.app**
   - If built from Xcode: `~/Library/Developer/Xcode/DerivedData/.../YTDownloader.app`
   - If in Applications: `/Applications/YTDownloader.app`
8. **Restart the app** (quit and relaunch from Xcode or manually)
9. **Try downloading the age-restricted video again**

**Expected**: Download succeeds this time (yt-dlp reads Safari's cookies).

**If still fails**:
- Make sure you're signed in to YouTube in Safari
- Check YTDownloader is listed in Full Disk Access
- Restart Safari after granting permission

#### Test 6: Multiple Concurrent Downloads
1. **In YTDownloader**: **Settings → Concurrent Downloads → 3**
2. **In Safari**: Click "YD" on 3-4 different videos quickly
3. **In app**: All should appear in queue
4. **Observe**: Multiple downloads run in parallel

**Warning**: Too many concurrent downloads (>5) may trigger 429 errors. Start with 2-3.

#### Test 7: Queue Persistence
1. **Queue 2-3 videos**
2. **While one is downloading**, quit the app (⌘Q)
3. **Relaunch the app**

**Expected**: Queue is restored, downloads resume.

#### Test 8: Error Handling (403 Retry)
1. **Queue 5-10 videos very quickly** (stress test)
2. Some might fail with "403 Forbidden"

**Expected**:
- App automatically retries with exponential backoff
- Status shows "Retrying (attempt 2/10)..."
- Eventually succeeds (or reaches max 10 attempts)

---

### Part 5: Extension Registration Verification (Optional)

#### Check Extension Process
```bash
# Find Safari extension process
ps aux | grep -i ytdownloader | grep -v grep
```

**Expected**: Shows `com.apple.Safari.SafariForWebKitDevelopment` process running the extension.

#### Check Logs
```bash
# Open Console.app and filter by "YTDownloader"
open -a Console

# Or use log command
log show --predicate 'process == "YTDownloader"' --last 5m
```

Look for:
- "Setting up YTDownloader" messages
- Download progress logs
- Error messages if any

#### Check Extension Resources
```bash
# Find extension bundle
find ~/Library/Developer/Xcode/DerivedData -name "YTDownloaderExtension.appex" 2>/dev/null

# Check manifest
cat <path-to-extension>/Contents/Resources/manifest.json
```

**Expected**: manifest.json matches the version in your repo.

---

## Troubleshooting Guide

### Problem: Xcode won't build - "Signing requires a development team"
**Solution**: Make sure you selected your Team in Signing & Capabilities for BOTH targets.

### Problem: Xcode won't build - "Failed to resolve package dependencies"
**Solution**:
```
File → Packages → Reset Package Caches
Product → Clean Build Folder (⌘⇧K)
Build again
```

### Problem: App crashes immediately on launch
**Solution**:
1. Open Xcode console (⌘⇧Y)
2. Look for crash logs
3. Common causes:
   - Entitlement issues: Check YTDownloader.entitlements and YTDownloaderExtension.entitlements
   - Missing frameworks: Clean and rebuild

### Problem: Safari extension doesn't appear
**Solution**:
1. Run app at least once
2. Quit Safari completely (⌘Q)
3. Reopen Safari
4. Check: Safari → Settings → Extensions
5. If still missing:
   ```bash
   pluginkit -r ~/Library/Developer/Xcode/DerivedData/.../YTDownloader.app
   ```

### Problem: YD button doesn't appear on YouTube
**Solution**:
1. Hard refresh (⌘⇧R)
2. Check Safari console for JavaScript errors:
   - Develop → Show JavaScript Console
3. Check extension permissions:
   - Safari → Settings → Extensions → YTDownloader → youtube.com (should be allowed)
4. Check content.js is loaded:
   - Develop → Show Page Resources → Look for content.js

### Problem: Clicking YD button does nothing
**Solution**:
1. Check Safari console for errors
2. Test URL scheme manually:
   ```bash
   open "ytdownloader://download?videoId=test&url=https://www.youtube.com/watch?v=test"
   ```
   Should open the app (even if download fails)
3. If app doesn't open, URL scheme not registered:
   - Quit and relaunch the app
   - Check: `cat ~/Developer/ytd-saf/YTDownloader/YTDownloader/Info.plist | grep -A5 URLTypes`

### Problem: Download fails with "yt-dlp not found"
**Solution**:
1. Check binary directory:
   ```bash
   ls -lh ~/Library/Application\ Support/YTDownloader/bin/
   ```
2. If missing, delete and relaunch:
   ```bash
   rm -rf ~/Library/Application\ Support/YTDownloader
   ```
3. Make sure you have internet connection
4. Check Xcode console for download errors

### Problem: Download fails with "403 Forbidden"
**Solution**: This is YouTube rate limiting. The app will automatically retry with exponential backoff (up to 10 times). Just wait.

### Problem: Age-restricted videos fail even with Safari cookies
**Solution**:
1. Make sure you're signed in to YouTube in Safari
2. Check Full Disk Access is granted:
   ```bash
   ls -l ~/Library/Safari/Cookies
   ```
   If "Permission denied", Full Disk Access is not working
3. Restart both Safari and YTDownloader after granting permission

### Problem: Downloaded video won't play in QuickTime
**Solution**: QuickTime doesn't support VP9/AV1/Opus codecs. Use:
- **IINA** (recommended): https://iina.io
- **Infuse**: https://firecore.com/infuse
- **VLC**: https://www.videolan.org

---

## Success Criteria Checklist

Check off when verified:

### Build & Setup
- [ ] Xcode project builds without errors
- [ ] App launches and shows onboarding
- [ ] Binaries download successfully (yt-dlp, ffmpeg, ffprobe)
- [ ] Binaries are executable (no permission errors)

### Extension
- [ ] Extension appears in Safari Settings → Extensions
- [ ] Extension is enabled and has youtube.com permission
- [ ] "Allow Unsigned Extensions" is enabled in Develop menu

### Basic Download Flow
- [ ] YD button appears on YouTube watch pages
- [ ] YD button appears on YouTube feed/search thumbnails
- [ ] Clicking YD button opens the app
- [ ] Video appears in download queue
- [ ] Download progresses: Queued → Downloading → Merging → Completed
- [ ] Downloaded MKV file exists in ~/Downloads
- [ ] Video plays in IINA/VLC

### Advanced Features
- [ ] Queue persists after app restart
- [ ] Multiple concurrent downloads work (Settings → Concurrent Downloads)
- [ ] Age-restricted videos work with Safari cookies + Full Disk Access
- [ ] Retry logic works (403 errors retry automatically)

### Quality Verification
- [ ] Selected video format matches highest available (check with `yt-dlp -F <url>`)
- [ ] Selected audio format is original language, highest bitrate
- [ ] Output MKV has both video and audio streams (check with `ffprobe`)
- [ ] No transcoding (codecs preserved: vp9/av1 video, opus/aac audio)

---

## What to Report Back

After testing, please provide:

### 1. Build Results
- [ ] Build succeeded
- [ ] Build failed (paste error message)

### 2. Extension Loading
- [ ] Extension appears in Safari Settings
- [ ] Extension didn't load (paste `pluginkit -m -p com.apple.Safari.extension` output)

### 3. Download Test Results
- [ ] Successfully downloaded at least 1 video
- [ ] Downloaded file path: `_______`
- [ ] File size: `_______`
- [ ] ffprobe output (paste `ffprobe <file> 2>&1 | grep Stream` output)

### 4. Issues Encountered (if any)
- Xcode errors: `_______`
- Safari extension errors: `_______`
- Download errors: `_______`
- Other issues: `_______`

### 5. Manual Testing Notes
- Tested on macOS version: `_______`
- Xcode version: `_______`
- Safari version: `_______`
- Number of successful downloads: `_______`
- Any videos that failed: `_______` (paste URL)

---

## Next Steps After Successful Testing

1. **Clean up test files**:
   ```bash
   cd ~/Developer/ytd-saf
   rm test_download.swift test_pipeline.sh
   git add -A
   git commit -m "Clean up test scripts"
   ```

2. **Push changes** (requires your GitHub credentials):
   ```bash
   git push origin cursor/safari-extension-app-043f
   ```

3. **Verify CI is green**:
   - Go to https://github.com/opsspb/ytd-saf/pull/1
   - Check that all CI jobs pass (build, test-core, integration-test)

4. **Use the app!**
   - Keep it in Applications folder
   - Download videos as needed
   - Report any bugs on GitHub

5. **Optional: Distribute to others**
   - Enroll in Apple Developer Program ($99/year)
   - Follow README.md Distribution section for notarization

---

## Files Modified in This Session

- `YTDownloader/YTDownloader/YTDownloader.entitlements` - Removed App Groups
- `YTDownloader/YTDownloaderExtension/YTDownloaderExtension.entitlements` - Removed App Groups
- `YTDownloader/YTDownloader/Info.plist` - Added ytdownloader:// URL scheme
- `YTDownloader/YTDownloader/NativeMessaging.swift` - URL scheme handler via NSAppleEventManager
- `YTDownloader/YTDownloaderExtension/SafariWebExtensionHandler.swift` - Opens URL scheme
- `YTDownloader/YTDownloaderExtension/Resources/background.js` - Fixed Safari messaging API
- `.github/workflows/build.yml` - Fixed integration-test to properly skip
- `README.md` - Updated architecture documentation

All changes committed to: `cursor/safari-extension-app-043f`

Git user: Cursor Agent <cursoragent@cursor.com> (set for this repo only)
