# YTDownloader Verification Report

## What Was Built

A complete macOS Safari Web Extension for downloading YouTube videos, consisting of:

1. **Native macOS App** (Swift/SwiftUI)
   - Download queue management
   - Settings interface
   - Binary manager (yt-dlp/ffmpeg auto-download)
   - Native messaging handler

2. **Safari Web Extension**
   - Content script (YD button injection)
   - Background worker (native messaging)
   - Manifest v3 configuration

3. **YTDownloaderCore Swift Package**
   - Format selection logic
   - Retry strategy
   - Error classification
   - Comprehensive unit tests

4. **Supporting Files**
   - Icon source (SVG) and generation script
   - GitHub Actions CI workflow
   - Comprehensive README

## Verification Status

### ✅ Verified in Development Environment

1. **File Structure**: All required files created in correct locations
2. **Code Syntax**: All Swift and JavaScript files written with correct syntax
3. **Project Files**: Xcode project.pbxproj structure valid
4. **Git Operations**: Successfully committed and pushed
5. **Documentation**: README complete with all sections
6. **Test Fixtures**: Realistic yt-dlp JSON fixtures created
7. **CI Configuration**: GitHub Actions workflow configured for macOS

### ⚠️ Not Verified (Requires macOS/Xcode)

1. **Xcode Build**: Project builds without errors
2. **Swift Tests**: Unit tests compile and pass
3. **Extension Loading**: Safari loads the extension
4. **Native Messaging**: Communication between extension and app works
5. **yt-dlp Integration**: Video download end-to-end
6. **App Signing**: Free signing team works correctly

## Testing Recommendations for Pavel

### Phase 1: Build Verification (5-10 minutes)

```bash
# Clone and setup
git clone https://github.com/opsspb/ytd-saf.git
cd ytd-saf
git checkout cursor/safari-extension-app-043f

# Generate icons
brew install librsvg  # if not already installed
./generate_icons.sh

# Open in Xcode
open YTDownloader.xcodeproj
```

In Xcode:
1. Select YTDownloader scheme
2. Set signing team for both targets (YTDownloader + YTDownloaderExtension)
3. Product → Build (⌘B)
4. Check for build errors

**Expected**: Build succeeds, possibly with warnings

### Phase 2: Unit Tests (2-5 minutes)

```bash
# Test Swift package
cd YTDownloaderCore
swift test
```

**Expected**: All tests pass
- FormatSelectorTests: 7 tests
- RetryStrategyTests: 4 tests
- ErrorClassifierTests: 8 tests

### Phase 3: App Launch (2-3 minutes)

In Xcode:
1. Product → Run (⌘R)
2. App should launch and show "Setting up YTDownloader"
3. Wait for binary download (yt-dlp + ffmpeg)
4. Should transition to onboarding screen

**Expected**: No crashes, binaries download successfully

### Phase 4: Extension Setup (5 minutes)

1. In Safari: Settings → Extensions
2. Enable YTDownloader
3. Grant permissions for youtube.com
4. Enable: Develop → Allow Unsigned Extensions
5. Navigate to youtube.com/watch?v=dQw4w9WgXcQ (or any video)

**Expected**: YD button appears near title

### Phase 5: Download Test (5-10 minutes)

1. Click YD button on a short public video
2. Button should show ⏳ then ✓
3. Switch to YTDownloader app
4. Video should appear in queue, status: Downloading

**Expected**: 
- Video downloads successfully
- File appears in ~/Downloads
- MKV file plays in QuickLook/Infuse

### Phase 6: Edge Cases (15-30 minutes)

Test these scenarios:

1. **High quality video**:
   - Find 4K 60fps video
   - Verify highest quality selected

2. **Age-restricted video**:
   - Should fail without cookies
   - Enable Safari cookies in Settings
   - Grant Full Disk Access
   - Retry download

3. **Multiple downloads**:
   - Queue 3-5 videos
   - Verify sequential processing
   - Check concurrent downloads setting (1-5)

4. **App restart**:
   - Quit app mid-download
   - Restart app
   - Verify queue persisted

5. **Thumbnail buttons**:
   - Navigate to youtube.com homepage
   - Verify YD buttons on thumbnails
   - Click thumbnail button (without navigating to video)

## Known Limitations (By Design)

1. **No App Sandbox**: Required to run downloaded binaries
2. **Free Signing**: Must enable "Allow Unsigned Extensions" in Safari
3. **Single video only**: No playlist support (would require UI changes)
4. **MKV output**: For maximum quality support (not MP4)
5. **No progress from yt-dlp**: Current implementation doesn't parse yt-dlp stdout for progress

## Potential Issues to Watch For

### Build Issues

**Issue**: Xcode can't find YTDownloaderCore package
**Fix**: File → Packages → Reset Package Caches

**Issue**: Code signing errors
**Fix**: Ensure both targets have same Team selected

### Runtime Issues

**Issue**: "yt-dlp not found" persists
**Fix**: Check `~/Library/Application Support/YTDownloader/bin/`

**Issue**: Extension not appearing in Safari
**Fix**: Run app at least once, restart Safari, check Extensions settings

**Issue**: YD button not appearing
**Fix**: Hard refresh YouTube page (⌘⇧R), check browser console for errors

**Issue**: Safari cookies fail
**Fix**: System Settings → Privacy → Full Disk Access → Add YTDownloader

### Download Issues

**Issue**: 403/429 errors
**Fix**: App will retry automatically (check retry state)

**Issue**: Age-restricted fails
**Fix**: Enable Safari cookies in app Settings

**Issue**: Videos play without audio
**Fix**: Check MKV file in VLC/Infuse (not QuickTime—may not support some codecs)

## GitHub Actions CI

The workflow in `.github/workflows/build.yml` will:
1. Run on macOS 14 runner
2. Generate icons
3. Run Swift package tests
4. Build the Xcode project
5. Attempt to archive the app

**First run**: After merge, check Actions tab for results

If CI fails:
- Check error logs in GitHub Actions
- Common issues: Xcode version mismatch, signing conflicts
- CI runs without signing (CODE_SIGNING_REQUIRED=NO)

## Files to Review

Before first build, review these files:

1. **YTDownloader.xcodeproj/project.pbxproj**:
   - Bundle identifiers correct: `com.ytdownloader.app` and `com.ytdownloader.app.extension`
   - File references point to correct paths

2. **YTDownloader/YTDownloader/YTDownloader.entitlements**:
   - App Sandbox: false (required for binary execution)
   - Network client: true

3. **YTDownloaderExtension/Resources/manifest.json**:
   - Permissions: nativeMessaging, storage
   - Host permissions: *://*.youtube.com/*

## Future Enhancements (Post-Verification)

Once basic functionality is confirmed:

1. **Progress tracking**: Parse yt-dlp stdout for download %
2. **Playlist support**: Batch download multiple videos
3. **Format picker**: Let user choose quality instead of auto-best
4. **Network throttling**: Bandwidth limiting
5. **Post-processing**: Auto-convert to MP4 option
6. **Notifications**: macOS notification on completion
7. **Menu bar app**: Run in menu bar instead of dock

## Distribution Checklist (For Later)

When ready to distribute:

- [ ] Enroll in Apple Developer Program ($99/year)
- [ ] Create Developer ID certificate
- [ ] Update signing in Xcode to use Developer ID
- [ ] Archive app: Product → Archive
- [ ] Notarize with Apple: `xcrun notarytool submit`
- [ ] Staple ticket: `xcrun stapler staple YTDownloader.app`
- [ ] Create DMG or zip for distribution
- [ ] Host on GitHub Releases
- [ ] Optional: Submit Homebrew cask

## Support

If issues arise during verification:

1. Check this document first
2. Review README.md troubleshooting section
3. Check GitHub Actions logs (if CI fails)
4. Review Xcode console logs
5. Check Safari Web Inspector console (Develop → Web Extension Background Content)
6. Open GitHub issue with:
   - macOS version
   - Xcode version
   - Error messages
   - Xcode build logs

## Success Criteria

Verification is successful when:

✅ Xcode project builds without errors  
✅ All unit tests pass  
✅ App launches and downloads binaries  
✅ Safari extension loads in Extensions settings  
✅ YD button appears on YouTube  
✅ Clicking button adds video to queue  
✅ Video downloads successfully to ~/Downloads  
✅ Downloaded MKV file plays correctly  

Once these are confirmed, the app is ready for personal use!
