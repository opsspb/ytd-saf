# Agent rules for YTDownloader

## Protected: VK and YouTube button injection

The following areas are **PROTECTED**. Do not modify them unless the task **explicitly** names VK or YouTube buttons (placement, selectors, styles, or injection):

- `YTDownloader/YTDownloaderExtension/Resources/vk.js` — selectors, DOM insertion, button styles/classes, `MutationObserver`, watch-page and card injection logic
- `YTDownloader/YTDownloaderExtension/Resources/content.js` — same for YouTube (watch page + cards)
- `YTDownloader/YTDownloaderExtension/Resources/styles.css` — styles for `.ytd-card-download-button`, `.ytd-watch-download-button`, `.ytd-vk`, and related button layout

### What "do not modify" means

- Cookie collection, Safari permission prompts, native-messaging handoff, background.js, Swift app code, yt-dlp/format selection, and queue UI changes must be **additive**.
- Those changes must **not** alter injection: selectors, where the button is inserted in the DOM, button markup/classes, MutationObserver setup, or CSS that controls button appearance/placement.
- Never reduce `manifest.json` `content_scripts` `matches` or `host_permissions` / `optional_host_permissions` for `vkvideo.ru`, `vk.com`, `vk.ru`, or `youtube.com`.

### Tests before every commit

Run all content-script tests and treat any failure as a commit blocker:

```bash
swift Scripts/run-content-tests.swift
swift Scripts/run-content-tests.swift YTDownloader/YTDownloaderExtension/Resources/vk.test.html
```

Expected: Failed: 0 on both (YouTube `content.test.html` and VK `vk.test.html`).

If a task does not mention VK/YouTube buttons and a diff still touches the protected paths above, stop and leave those files unchanged.

## Code signing (CRITICAL)
Never build signed in the `agent` macOS account or any automated environment. Always build with `CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=` and never pass `-allowProvisioningUpdates`. A signed build there creates a new Apple Development certificate for the free Personal Team, which revokes Pavel's certificate and makes Safari drop the extension. Only Pavel's account produces signed builds.
