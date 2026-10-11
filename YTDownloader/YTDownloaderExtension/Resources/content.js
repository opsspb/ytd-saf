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
        '#actions #top-level-buttons-computed',
        '#top-level-buttons-computed',
        '#flexible-item-buttons',
        'ytd-watch-metadata #actions-inner',
        'ytd-watch-metadata #actions',
        '#menu-container ytd-menu-renderer #top-level-buttons-computed'
    ];

    let observerActive = false;

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

    function createWatchPageButton() {
        const button = document.createElement('button');
        button.id = BUTTON_ID;
        button.type = 'button';
        button.className = 'ytd-watch-download-button';
        button.setAttribute('aria-label', 'Download with YTDownloader');
        button.textContent = 'YD';
        button.addEventListener('click', handleWatchPageClick);
        return button;
    }

    async function handleWatchPageClick(e) {
        e.preventDefault();
        e.stopPropagation();

        const button = e.currentTarget;
        const videoId = getVideoId();
        if (!videoId) {
            flashButton(button, '❌');
            return;
        }

        await queueDownload(button, videoId, getCanonicalUrl(videoId));
    }

    function flashButton(button, text) {
        button.textContent = text;
        setTimeout(() => {
            button.textContent = 'YD';
            button.disabled = false;
        }, 2000);
    }

    function openHostApp(videoId, url) {
        const params = new URLSearchParams({ videoId, url });
        const scheme = `ytdownloader://download?${params.toString()}`;
        const iframe = document.createElement('iframe');
        iframe.setAttribute('aria-hidden', 'true');
        iframe.style.cssText = 'position:absolute;width:0;height:0;border:0;visibility:hidden';
        iframe.src = scheme;
        document.documentElement.appendChild(iframe);
        setTimeout(() => iframe.remove(), 2000);
    }

    async function queueDownload(button, videoId, url) {
        button.textContent = '⏳';
        button.disabled = true;
        openHostApp(videoId, url);

        try {
            const runtime = (global.browser && global.browser.runtime) || (global.chrome && global.chrome.runtime);
            if (!runtime || !runtime.sendMessage) {
                flashButton(button, '✓');
                return;
            }

            const response = await runtime.sendMessage({
                action: 'download',
                videoId: videoId,
                url: url
            });

            if (response && response.success) {
                flashButton(button, '✓');
            } else {
                throw new Error('Download failed');
            }
        } catch (error) {
            console.error('YTDownloader error:', error);
            flashButton(button, '❌');
        }
    }

    function findWatchActionsRow() {
        for (const selector of WATCH_ACTIONS_SELECTORS) {
            const node = document.querySelector(selector);
            if (node) return node;
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

        if (existing && document.contains(existing)) return;

        const actionsRow = findWatchActionsRow();
        if (!actionsRow) return;

        const button = createWatchPageButton();
        // Append after Like/Share so we do not break the segmented control.
        actionsRow.appendChild(button);
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

    function attachNoNavigation(target) {
        const preventNavigation = (e) => {
            e.preventDefault();
            e.stopPropagation();
            e.stopImmediatePropagation();
        };

        ['mousedown', 'mouseup', 'pointerdown', 'pointerup', 'touchstart', 'click', 'auxclick', 'mouseover', 'mouseenter'].forEach((eventType) => {
            target.addEventListener(eventType, preventNavigation, true);
        });

        return preventNavigation;
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

        const preventNavigation = attachNoNavigation(button);
        attachNoNavigation(buttonContainer);

        button.addEventListener('click', async (e) => {
            preventNavigation(e);
            await queueDownload(button, videoId, getCanonicalUrl(videoId));
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
        refresh,
        init
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
