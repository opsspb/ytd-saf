// Content script for YouTube pages
(function (global) {
    'use strict';

    const BUTTON_ID = 'ytd-download-button';
    const CARD_BUTTON_CLASS = 'ytd-card-download-button';
    const CARD_BUTTON_MARKER = 'data-ytd-card-button';
    const AVATAR_COLUMN_CLASS = 'ytd-card-avatar-column';
    const CHECK_INTERVAL = 1000;

    const CARD_SELECTORS = [
        'yt-lockup-view-model',
        'ytd-rich-item-renderer',
        'ytd-rich-grid-media',
        'ytd-grid-video-renderer',
        'ytd-video-renderer',
        'ytd-compact-video-renderer'
    ];

    const VIDEO_LINK_SELECTORS = [
        'a.ytLockupViewModelContentImage[href*="watch?v="]',
        'a.yt-lockup-view-model__content-image[href*="watch?v="]',
        'a.ytLockupMetadataViewModelTitle[href*="watch?v="]',
        'a.yt-lockup-metadata-view-model__title[href*="watch?v="]',
        'a#video-title-link[href*="watch?v="]',
        'a#video-title[href*="watch?v="]',
        'a#thumbnail[href*="watch?v="]',
        'a.ytd-thumbnail[href*="watch?v="]',
        'a[href*="/watch?v="]'
    ];

    const AVATAR_COLUMN_SELECTORS = [
        '.yt-lockup-metadata-view-model__avatar',
        '.ytLockupMetadataViewModelAvatar'
    ];

    const AVATAR_SELECTORS = [
        '.yt-lockup-metadata-view-model__avatar',
        '.ytLockupMetadataViewModelAvatar',
        'yt-avatar-shape',
        '.ytSpecAvatarShapeHost',
        'yt-decorated-avatar-view-model',
        '#avatar-link',
        '#channel-thumbnail',
        '#avatar'
    ];

    const WATCH_ACTIONS_SELECTORS = [
        'ytd-watch-metadata #actions-inner',
        'ytd-watch-metadata #actions #menu-container ytd-menu-renderer',
        'ytd-watch-metadata #actions',
        '#actions-inner',
        '#flexible-item-buttons',
        '#actions #top-level-buttons-computed',
        '#top-level-buttons-computed',
        '#menu-container ytd-menu-renderer #top-level-buttons-computed',
        'ytd-menu-renderer.ytd-watch-metadata #top-level-buttons-computed',
        '#actions ytd-menu-renderer'
    ];

    const WATCH_ACTION_ANCHORS = [
        'segmented-like-dislike-button-view-model',
        'like-button-view-model',
        'button-view-model',
        'yt-button-view-model',
        'button[aria-label*="Share"]',
        'button[aria-label*="Поделиться"]',
        'button[aria-label*="Save"]',
        'button[aria-label*="Сохранить"]'
    ];

    let observerActive = false;
    let lastQueued = null;

    function getVideoId() {
        const urlParams = new URLSearchParams(window.location.search);
        return urlParams.get('v');
    }

    function getCanonicalUrl(videoId) {
        return `https://www.youtube.com/watch?v=${videoId}`;
    }

    function extractVideoIdFromUrl(url) {
        if (!url) return null;
        try {
            const parsed = new URL(url, 'https://www.youtube.com');
            const fromQuery = parsed.searchParams.get('v');
            if (fromQuery) return fromQuery;
            const shorts = parsed.pathname.match(/^\/shorts\/([^/]+)/);
            if (shorts) return shorts[1];
            const embed = parsed.pathname.match(/^\/embed\/([^/]+)/);
            if (embed) return embed[1];
        } catch (error) {
            // Fall through to regex for relative/malformed hrefs.
        }
        const match = String(url).match(/[?&]v=([^&]+)/);
        return match ? match[1] : null;
    }

    function isShortsHref(href) {
        return typeof href === 'string' && href.includes('/shorts/');
    }

    function downloadIconSvg() {
        return '<svg class="ytd-watch-icon" viewBox="0 0 24 24" aria-hidden="true" focusable="false">'
            + '<path fill="currentColor" d="M12 4a1 1 0 0 1 1 1v8.59l2.3-2.3a1 1 0 1 1 1.4 1.42l-4 4a1 1 0 0 1-1.4 0l-4-4a1 1 0 1 1 1.4-1.42L11 13.59V5a1 1 0 0 1 1-1Zm-7 14a1 1 0 0 1 1-1h12a1 1 0 1 1 0 2H6a1 1 0 0 1-1-1Z"/>'
            + '</svg>';
    }

    function paintWatchLabel(button, text) {
        if (!button) return;
        if (text === 'YD') {
            button.innerHTML = downloadIconSvg() + '<span>YD</span>';
            return;
        }
        button.textContent = text;
    }

    function createWatchPageButton() {
        const button = document.createElement('button');
        button.id = BUTTON_ID;
        button.type = 'button';
        button.className = 'ytd-watch-download-button';
        button.setAttribute('aria-label', 'Download with YTDownloader');
        paintWatchLabel(button, 'YD');
        button.addEventListener('click', handleWatchPageClick);
        return button;
    }

    async function handleWatchPageClick(e) {
        e.preventDefault();
        e.stopPropagation();

        const button = e.currentTarget;
        const videoId = getVideoId();
        if (!videoId) {
            setButtonState(button, 'error');
            return;
        }

        await queueDownload(button, videoId, getCanonicalUrl(videoId));
    }

    function setButtonState(button, state) {
        if (!button) return;
        button.dataset.ytdState = state;
        if (state === 'working') {
            paintWatchLabel(button, '…');
            button.disabled = true;
            return;
        }
        if (state === 'queued' || state === 'done') {
            paintWatchLabel(button, '✓');
            button.disabled = false;
            return;
        }
        if (state === 'error') {
            paintWatchLabel(button, 'YD');
            button.disabled = false;
            return;
        }
        paintWatchLabel(button, 'YD');
        button.disabled = false;
    }

    function openHostApp(videoId, url, cookiesPayload) {
        if (global.__YTD_TEST__) return;
        const params = new URLSearchParams({ videoId, url });
        if (cookiesPayload) {
            params.set('cookies', cookiesPayload);
        }
        const scheme = `ytdownloader://download?${params.toString()}`;
        const iframe = document.createElement('iframe');
        iframe.setAttribute('aria-hidden', 'true');
        iframe.style.cssText = 'position:absolute;width:0;height:0;border:0;visibility:hidden';
        iframe.src = scheme;
        document.documentElement.appendChild(iframe);
        setTimeout(() => iframe.remove(), 2000);
    }

    async function queueDownload(button, videoId, url) {
        lastQueued = { videoId, url, at: Date.now() };
        setButtonState(button, 'working');

        try {
            const runtime = (global.browser && global.browser.runtime) || (global.chrome && global.chrome.runtime);
            if (!runtime || !runtime.sendMessage) {
                openHostApp(videoId, url);
                setButtonState(button, 'queued');
                return;
            }

            const response = await runtime.sendMessage({
                action: 'download',
                videoId: videoId,
                url: url
            });

            // Backup iframe after background collected cookies (avoid racing a cookieless enqueue).
            openHostApp(videoId, url, response && response.cookies);

            if (response && response.success) {
                setButtonState(button, 'queued');
            } else {
                throw new Error('Download failed');
            }
        } catch (error) {
            console.error('YTDownloader error:', error);
            openHostApp(videoId, url);
            setButtonState(button, 'queued');
        }
    }

    function isUsable(el) {
        if (!el || !document.contains(el)) return false;
        const style = global.getComputedStyle ? getComputedStyle(el) : null;
        if (style && (style.display === 'none' || style.visibility === 'hidden' || style.opacity === '0')) {
            return false;
        }
        const rect = el.getBoundingClientRect ? el.getBoundingClientRect() : { width: 1, height: 20 };
        return rect.width > 8 && rect.height > 8;
    }

    function findWatchActionsRow() {
        for (const selector of WATCH_ACTION_ANCHORS) {
            const anchors = document.querySelectorAll(selector);
            for (const anchor of anchors) {
                if (!isUsable(anchor)) continue;
                const row = anchor.parentElement;
                if (row && isUsable(row)) return row;
            }
        }

        for (const selector of WATCH_ACTIONS_SELECTORS) {
            const nodes = document.querySelectorAll(selector);
            for (const node of nodes) {
                if (isUsable(node)) return node;
            }
        }
        return null;
    }

    function findShareOrSaveAnchor(row) {
        if (!row) return null;
        const candidates = row.querySelectorAll('button, [role="button"], yt-button-view-model, button-view-model');
        for (const node of candidates) {
            const label = ((node.getAttribute && node.getAttribute('aria-label')) || '')
                + ' ' + ((node.textContent || '').trim());
            if (/share|поделиться|save|сохранить/i.test(label) && isUsable(node)) {
                return node;
            }
        }
        return null;
    }

    function insertButtonOnWatchPage() {
        const videoId = getVideoId();
        const existing = document.getElementById(BUTTON_ID);

        if (!videoId) {
            if (existing) existing.remove();
            return;
        }

        const actionsRow = findWatchActionsRow();
        if (!actionsRow) return;

        if (existing && actionsRow.contains(existing) && isUsable(existing)) {
            // Keep pill styling even if YouTube re-parents siblings.
            existing.classList.add('ytd-watch-download-button');
            return;
        }
        if (existing) existing.remove();

        const button = createWatchPageButton();
        const anchor = findShareOrSaveAnchor(actionsRow);
        if (anchor && anchor.parentElement === actionsRow) {
            // Prefer between Share and Save when Share is found first.
            const next = anchor.nextElementSibling;
            if (next) actionsRow.insertBefore(button, next);
            else actionsRow.appendChild(button);
        } else {
            actionsRow.appendChild(button);
        }
    }

    function cardAlreadyProcessed(card) {
        const state = card.getAttribute(CARD_BUTTON_MARKER);
        return state === 'added' || state === 'skipped';
    }

    function markCard(card, state) {
        card.setAttribute(CARD_BUTTON_MARKER, state);
        const host = card.closest('ytd-rich-item-renderer');
        if (host && host !== card) {
            host.setAttribute(CARD_BUTTON_MARKER, state);
        }
    }

    function collectCards() {
        const seen = new Set();
        const cards = [];
        document.querySelectorAll(CARD_SELECTORS.join(',')).forEach((node) => {
            if (seen.has(node) || cardAlreadyProcessed(node)) return;
            // Prefer the inner lockup; the rich-item is only a shell.
            if (node.tagName === 'YTD-RICH-ITEM-RENDERER') {
                const lockup = node.querySelector('yt-lockup-view-model');
                if (lockup) {
                    if (!seen.has(lockup) && !cardAlreadyProcessed(lockup)) {
                        seen.add(lockup);
                        cards.push(lockup);
                    }
                    return;
                }
            }
            seen.add(node);
            cards.push(node);
        });
        return cards;
    }

    function isSkippableCard(card) {
        if (card.querySelector('[overlay-style="SHORTS"], ytm-shorts-lockup-view-model, ytd-reel-item-renderer')) {
            return true;
        }
        if (card.querySelector('a[href*="/shorts/"]')) {
            return true;
        }
        if (card.closest('ytd-ad-slot-renderer, ytd-promoted-sparkles-web-renderer')) {
            return true;
        }
        if (card.querySelector('[aria-label*="Sponsored"], [aria-label*="Реклама"]')) {
            return true;
        }
        return false;
    }

    function findVideoLink(card) {
        for (const selector of VIDEO_LINK_SELECTORS) {
            const link = card.querySelector(selector);
            if (!link) continue;
            const href = link.getAttribute('href') || '';
            if (isShortsHref(href)) continue;
            const videoId = extractVideoIdFromUrl(href);
            if (videoId) return { link, href, videoId };
        }
        return null;
    }

    function findAvatarAnchor(card) {
        for (const selector of AVATAR_COLUMN_SELECTORS.concat(AVATAR_SELECTORS)) {
            const node = card.querySelector(selector);
            if (node) return node;
        }
        return null;
    }

    function ensureAvatarColumn(avatarAnchor) {
        const existing = avatarAnchor.closest('.' + AVATAR_COLUMN_CLASS);
        if (existing) return existing;

        // Avatar hosts are often 36px circles. Wrap them so YD sits under the
        // circle instead of being clipped inside it.
        const host = avatarAnchor.closest(AVATAR_COLUMN_SELECTORS.join(',')) || avatarAnchor;
        const column = document.createElement('div');
        column.className = AVATAR_COLUMN_CLASS;
        host.parentNode.insertBefore(column, host);
        column.appendChild(host);
        return column;
    }

    function isolateFromYouTube(e) {
        e.preventDefault();
        e.stopPropagation();
    }

    // Capture-phase on pointer/mouse down only. Never attach this to `click`:
    // stopImmediatePropagation on click swallows our own queue handler.
    function attachPreviewBlockers(target) {
        ['mousedown', 'pointerdown', 'touchstart', 'auxclick'].forEach((eventType) => {
            target.addEventListener(eventType, isolateFromYouTube, true);
        });
    }

    function resolveCardVideoId(button) {
        const fromButton = button.getAttribute('data-video-id');
        if (fromButton) return fromButton;
        const card = button.closest(CARD_SELECTORS.join(','));
        if (!card) return null;
        const video = findVideoLink(card);
        return video ? video.videoId : null;
    }

    function createCardButton(videoId) {
        const buttonContainer = document.createElement('div');
        buttonContainer.className = 'ytd-card-button-container';

        const button = document.createElement('button');
        button.type = 'button';
        button.className = CARD_BUTTON_CLASS;
        button.textContent = 'YD';
        button.setAttribute('aria-label', 'Download video');
        button.setAttribute('data-video-id', videoId);

        attachPreviewBlockers(button);
        attachPreviewBlockers(buttonContainer);

        button.addEventListener('click', async (e) => {
            isolateFromYouTube(e);
            const id = resolveCardVideoId(button) || videoId;
            if (!id) {
                setButtonState(button, 'error');
                return;
            }
            await queueDownload(button, id, getCanonicalUrl(id));
        });

        buttonContainer.appendChild(button);
        return buttonContainer;
    }

    function insertButtonsOnCards() {
        collectCards().forEach((card) => {
            if (isSkippableCard(card)) {
                markCard(card, 'skipped');
                return;
            }

            const video = findVideoLink(card);
            if (!video) {
                // Skeleton / not hydrated yet — retry on the next pass.
                return;
            }

            const avatarAnchor = findAvatarAnchor(card);
            if (!avatarAnchor) {
                return;
            }

            const column = ensureAvatarColumn(avatarAnchor);
            if (column.querySelector('.' + CARD_BUTTON_CLASS)) {
                markCard(card, 'added');
                return;
            }

            const buttonContainer = createCardButton(video.videoId);
            column.appendChild(buttonContainer);
            markCard(card, 'added');
        });
    }

    function refresh() {
        insertButtonOnWatchPage();
        insertButtonsOnCards();
    }

    function initObserver() {
        if (observerActive || !document.body) return;

        const observer = new MutationObserver(() => {
            refresh();
        });

        observer.observe(document.body, {
            childList: true,
            subtree: true
        });

        observerActive = true;
    }

    function init() {
        refresh();
        initObserver();

        setInterval(refresh, CHECK_INTERVAL);

        window.addEventListener('yt-navigate-finish', refresh);
        window.addEventListener('yt-page-data-updated', refresh);

        let lastUrl = location.href;
        new MutationObserver(() => {
            if (location.href === lastUrl) return;
            lastUrl = location.href;
            setTimeout(refresh, 300);
        }).observe(document, { subtree: true, childList: true });
    }

    const api = {
        BUTTON_ID,
        CARD_BUTTON_CLASS,
        CARD_BUTTON_MARKER,
        extractVideoIdFromUrl,
        insertButtonOnWatchPage,
        insertButtonsOnCards,
        findWatchActionsRow,
        isUsable,
        refresh,
        init,
        get lastQueued() { return lastQueued; }
    };

    global.YTD = api;

    if (!global.__YTD_TEST__) {
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', init);
        } else {
            init();
        }
    }
})(typeof window !== 'undefined' ? window : globalThis);
