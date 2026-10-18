// Content script for vkvideo.ru / vk.com / vk.ru public videos and clips.
(function (global) {
    'use strict';

    const BUTTON_ID = 'ytd-download-button';
    const CARD_BUTTON_CLASS = 'ytd-card-download-button';
    const CARD_BUTTON_MARKER = 'data-ytd-card-button';
    const AVATAR_COLUMN_CLASS = 'ytd-card-avatar-column';
    const CHECK_INTERVAL = 1000;
    // Matches /video-1_2, /video1_2, /@chan/video-1_2, ?z=video-1_2, clip…
    const ID_RE = /(?:^|[/?#=&])(video|clip)(-?\d+)_(\d+)/i;

    const CARD_SELECTORS = [
        '[data-testid="grid-item"]',
        '[data-testid="video_card_preview"]',
        '[data-testid="video_card_thumb"]',
        '[data-testid="video_card_info_layout_container"]',
        '[data-testid="group-card"]',
        '[data-testid="clipcard"]',
        '[data-testid="video-playlist-card"]',
        '[role="presentation"]'
    ];

    const AUTHOR_SELECTORS = [
        '[data-testid="video_card_author"]',
        '[data-testid="video_card_owner"]',
        '[data-testid="clip-preview-owner"]',
        '[data-testid*="author"]',
        '[data-testid*="owner"]',
        '[data-testid*="avatar"]'
    ];

    const META_SELECTORS = [
        '[data-testid="video_card_info_layout_container"]',
        '[data-testid="video_card_additional_info"]',
        '[data-testid="video_card_controls"]'
    ];

    const WATCH_ACTION_SELECTORS = [
        '[data-testid="video_page_like_button"]',
        '[data-testid="video_page_share_button"]',
        '[data-testid="video_card_share_button"]',
        'button[aria-label*="Share"]',
        'button[aria-label*="Поделиться"]',
        'button[aria-label*="Like"]',
        'button[aria-label*="Нравится"]',
        'button[aria-label*="Add to"]',
        'button[aria-label*="Смотреть позже"]',
        '[data-testid*="like"]',
        '[data-testid*="share"]'
    ];
    const WATCH_ACTION_FALLBACKS = [
        '[data-testid="dropdownactionsheet"]',
        '[data-testid="video_owner_container"]',
        '[data-testid="video-page-info"]',
        '[data-testid="video_page_title"]'
    ];
    const WATCH_ACTION_TEXT = /поделиться|share|нравится|like|1\s*тыс|тыс\.|watch later|смотреть позже/i;

    let observerActive = false;
    let lastQueued = null;

    // Must run inside the YD click handler so Safari can show its host-permission prompt.
    const COOKIE_HOST_ORIGINS = [
        '*://*.youtube.com/*',
        '*://youtube.com/*',
        '*://*.google.com/*',
        '*://google.com/*',
        '*://*.vk.com/*',
        '*://vk.com/*',
        '*://*.vk.ru/*',
        '*://vk.ru/*',
        '*://*.vkvideo.ru/*',
        '*://vkvideo.ru/*'
    ];

    async function requestCookieHostPermissions() {
        const api = (global.browser && global.browser.permissions)
            || (global.chrome && global.chrome.permissions);
        if (!api || typeof api.request !== 'function') {
            return true;
        }
        try {
            return !!(await api.request({ origins: COOKIE_HOST_ORIGINS }));
        } catch (error) {
            console.warn('YTDownloader VK: permissions.request failed', error);
            return false;
        }
    }

    function parseVKHref(href) {
        if (!href) return null;
        const raw = String(href);
        if (/\/live-|\/playlist\/|video_ext\.php|youtube\.com|youtu\.be/i.test(raw)) {
            return null;
        }
        const match = raw.match(ID_RE);
        if (!match) return null;
        const kind = match[1].toLowerCase();
        const oid = match[2];
        const vid = match[3];
        const id = oid + '_' + vid;
        return {
            kind,
            id,
            url: 'https://vkvideo.ru/' + kind + oid + '_' + vid
        };
    }

    function getWatchRef() {
        return parseVKHref(global.location && global.location.href);
    }

    function createWatchPageButton() {
        const button = document.createElement('button');
        button.id = BUTTON_ID;
        button.type = 'button';
        button.className = 'ytd-watch-download-button ytd-vk';
        button.setAttribute('aria-label', 'Download with YTDownloader');
        button.textContent = 'YD';
        button.addEventListener('click', handleWatchPageClick);
        return button;
    }

    async function handleWatchPageClick(e) {
        e.preventDefault();
        e.stopPropagation();
        const button = e.currentTarget;
        const ref = getWatchRef();
        if (!ref) {
            setButtonState(button, 'error');
            return;
        }
        await queueDownload(button, ref.id, ref.url);
    }

    function setButtonState(button, state) {
        if (!button) return;
        button.dataset.ytdState = state;
        if (state === 'working') {
            button.textContent = '…';
            button.disabled = true;
            return;
        }
        if (state === 'queued' || state === 'done') {
            button.textContent = '✓';
            button.disabled = false;
            return;
        }
        button.textContent = 'YD';
        button.disabled = false;
    }

    function openHostApp(videoId, url, handoff) {
        if (global.__YTD_TEST__) return;
        const params = new URLSearchParams({ videoId, url });
        if (handoff && handoff.cookieRef) {
            params.set('cookieRef', handoff.cookieRef);
        } else if (handoff && handoff.cookies) {
            params.set('cookies', handoff.cookies);
        }
        const scheme = 'ytdownloader://download?' + params.toString();
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

        await requestCookieHostPermissions();

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
            openHostApp(videoId, url, response || undefined);
            if (response && response.success) {
                setButtonState(button, 'queued');
            } else {
                throw new Error('Download failed');
            }
        } catch (error) {
            console.error('YTDownloader VK error:', error);
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
        // Watch-page controls can be in flex rows that report tiny width before paint.
        return rect.height > 8 && (rect.width > 8 || rect.height >= 28);
    }

    function actionLabel(node) {
        return ((node.getAttribute && node.getAttribute('aria-label')) || '') + ' ' + ((node.textContent || '').trim());
    }

    function findWatchActionControl() {
        for (const selector of WATCH_ACTION_SELECTORS) {
            const nodes = document.querySelectorAll(selector);
            for (const node of nodes) {
                if (isUsable(node)) return node;
            }
        }
        const controls = document.querySelectorAll('button, [role="button"], a');
        for (const node of controls) {
            if (!isUsable(node)) continue;
            if (WATCH_ACTION_TEXT.test(actionLabel(node))) return node;
        }
        for (const selector of WATCH_ACTION_FALLBACKS) {
            const nodes = document.querySelectorAll(selector);
            for (const node of nodes) {
                if (node) return node;
            }
        }
        return null;
    }

    function rowFromControl(node) {
        // Only use video-page-info layout when the matched control lives inside it
        // (or is the info block itself). Never steal an unrelated fixture/row.
        const info = (node.getAttribute && node.getAttribute('data-testid') === 'video-page-info')
            ? node
            : node.closest('[data-testid="video-page-info"]');
        if (info) {
            const owner = info.querySelector('[data-testid="video_owner_container"]');
            if (owner && owner.parentElement && owner.parentElement.children.length >= 2) {
                return owner.parentElement;
            }
            const flexRows = info.querySelectorAll('[class*="vkuiFlex"], [class*="Flex"]');
            for (const flex of flexRows) {
                if (flex.children.length >= 2) return flex;
            }
        }

        let current = node;
        for (let i = 0; i < 8 && current; i++) {
            const parent = current.parentElement;
            if (!parent) break;
            const rect = parent.getBoundingClientRect ? parent.getBoundingClientRect() : { height: 40, width: 200 };
            const kids = Array.from(parent.children).filter((el) => {
                if (!el.getBoundingClientRect) return true;
                const r = el.getBoundingClientRect();
                return r.height > 8;
            });
            if (kids.length >= 2 && rect.height > 8 && rect.height < 120 && rect.width > 80) {
                return parent;
            }
            current = parent;
        }
        return node.parentElement;
    }

    function findWatchActionsRow() {
        const control = findWatchActionControl();
        if (control) {
            const row = rowFromControl(control);
            if (row) return row;
            if (isUsable(control)) return control.parentElement || control;
        }
        const title = document.querySelector('[data-testid="video_page_title"], h1');
        if (title && title.parentElement) return title.parentElement;
        return null;
    }

    function insertButtonOnWatchPage() {
        const ref = getWatchRef();
        const existing = document.getElementById(BUTTON_ID);
        if (!ref) {
            if (existing) existing.remove();
            return;
        }
        const actionsRow = findWatchActionsRow();
        if (!actionsRow) return;
        if (existing && actionsRow.contains(existing) && isUsable(existing)) {
            return;
        }
        if (existing) existing.remove();
        actionsRow.appendChild(createWatchPageButton());
    }

    function cardAlreadyProcessed(card) {
        const state = card.getAttribute(CARD_BUTTON_MARKER);
        return state === 'added' || state === 'skipped';
    }

    function markCard(card, state) {
        card.setAttribute(CARD_BUTTON_MARKER, state);
    }

    function isSkippableCard(card) {
        const refs = collectVideoRefs(card);
        if (refs.length > 0) return false;
        return !!card.querySelector('a[href*="/live-"], a[href*="/playlist/"], a[href*="video_ext.php"]');
    }

    function collectVideoRefs(root) {
        const found = [];
        const seen = new Set();
        function consider(link) {
            if (!link || seen.has(link) || !link.getAttribute) return;
            const ref = parseVKHref(link.getAttribute('href') || '');
            if (!ref) return;
            seen.add(link);
            found.push({ link, ref });
        }
        consider(root);
        if (root.querySelectorAll) {
            root.querySelectorAll('a[href]').forEach(consider);
        }
        // Title nodes sometimes expose href via data attributes after SPA hydration.
        if (root.querySelectorAll) {
            root.querySelectorAll('[href], [data-href], [data-url]').forEach((node) => {
                const href = node.getAttribute('href')
                    || node.getAttribute('data-href')
                    || node.getAttribute('data-url')
                    || '';
                const ref = parseVKHref(href);
                if (!ref || seen.has(node)) return;
                seen.add(node);
                found.push({ link: node, ref });
            });
        }
        return found;
    }

    function findVideoLink(card) {
        const refs = collectVideoRefs(card);
        if (refs.length) return refs[0];
        const dataId = card.getAttribute('data-video-id') || card.getAttribute('data-id');
        if (dataId && /^-?\d+_\d+$/.test(dataId)) {
            return { link: null, ref: { kind: 'video', id: dataId, url: 'https://vkvideo.ru/video' + dataId } };
        }
        return null;
    }

    function findCardRoot(link) {
        let node = link;
        for (let i = 0; i < 16 && node && node !== document.body; i++) {
            const testid = node.getAttribute && node.getAttribute('data-testid');
            if (testid && /grid-item|group-card|clip-preview|clipcard|video_card_preview|video_card_thumb|tile|video-playlist-card/i.test(testid)) {
                // Prefer presentation wrapper that also contains the info layout.
                const presentation = node.closest('[role="presentation"]');
                if (presentation && presentation.querySelector('[data-testid="video_card_info_layout_container"]')) {
                    return presentation;
                }
                return node;
            }
            if (node.getAttribute && node.getAttribute('role') === 'presentation'
                && node.querySelector && node.querySelector('[data-testid="video_card_info_layout_container"]')) {
                return node;
            }
            if (node.matches && node.matches('article, li, [role="listitem"]')) {
                return node;
            }
            const parent = node.parentElement;
            if (!parent || parent === document.body || parent === document.documentElement) {
                return node;
            }
            // Never swallow a whole home grid: stop before a parent with other videos.
            if (collectVideoRefs(parent).length > 1) {
                return node;
            }
            node = parent;
        }
        return node;
    }

    function elevateCardRoot(node) {
        if (!node) return node;
        if (node.getAttribute && node.getAttribute('data-testid') === 'video_card_info_layout_container') {
            const presentation = node.closest('[role="presentation"]');
            if (presentation) return presentation;
            const grid = node.closest('[data-testid="grid-item"], [data-testid*="card"]');
            if (grid && grid !== node) return grid;
        }
        if (node.getAttribute && /video_card_preview|video_card_thumb/i.test(node.getAttribute('data-testid') || '')) {
            return node.closest('[role="presentation"]')
                || node.closest('[data-testid="grid-item"]')
                || node;
        }
        return node;
    }

    function findAuthorAnchor(card) {
        for (const selector of AUTHOR_SELECTORS) {
            const node = card.querySelector(selector);
            if (node) return node;
        }
        return null;
    }

    function findMetaRow(card) {
        for (const selector of META_SELECTORS) {
            const node = card.querySelector(selector);
            if (node) return node;
        }
        return card;
    }

    function ensureAvatarColumn(avatarAnchor) {
        const existing = avatarAnchor.closest('.' + AVATAR_COLUMN_CLASS);
        if (existing) return existing;
        const column = document.createElement('div');
        column.className = AVATAR_COLUMN_CLASS;
        if (avatarAnchor.parentNode) {
            avatarAnchor.parentNode.insertBefore(column, avatarAnchor);
            column.appendChild(avatarAnchor);
        }
        return column;
    }

    function isolateFromNavigation(e) {
        e.preventDefault();
        e.stopPropagation();
    }

    function attachPreviewBlockers(target) {
        ['mousedown', 'pointerdown', 'touchstart', 'auxclick'].forEach((eventType) => {
            target.addEventListener(eventType, isolateFromNavigation, true);
        });
    }

    function createCardButton(ref) {
        const buttonContainer = document.createElement('div');
        buttonContainer.className = 'ytd-card-button-container';

        const button = document.createElement('button');
        button.type = 'button';
        button.className = CARD_BUTTON_CLASS + ' ytd-vk';
        button.textContent = 'YD';
        button.setAttribute('aria-label', 'Download video');
        button.setAttribute('data-video-id', ref.id);
        button.setAttribute('data-video-url', ref.url);

        attachPreviewBlockers(button);
        attachPreviewBlockers(buttonContainer);

        button.addEventListener('click', async (e) => {
            isolateFromNavigation(e);
            const id = button.getAttribute('data-video-id') || ref.id;
            const url = button.getAttribute('data-video-url') || ref.url;
            if (!id) {
                setButtonState(button, 'error');
                return;
            }
            await queueDownload(button, id, url);
        });

        buttonContainer.appendChild(button);
        return buttonContainer;
    }

    function collectCards() {
        const seen = new Set();
        const cards = [];
        function add(card) {
            const root = elevateCardRoot(card);
            if (!root || seen.has(root) || cardAlreadyProcessed(root)) return;
            if (root === document.body || root === document.documentElement) return;
            seen.add(root);
            cards.push(root);
        }
        document.querySelectorAll(CARD_SELECTORS.join(',')).forEach((node) => {
            if (node.getAttribute && node.getAttribute('role') === 'presentation') {
                if (!node.querySelector('[data-testid="video_card_info_layout_container"], a[href*="video"], a[href*="clip"]')) {
                    return;
                }
            }
            add(node.closest('[data-testid="grid-item"]')
                || node.closest('[role="presentation"]')
                || node.closest('[data-testid*="card"]')
                || node);
        });
        document.querySelectorAll('a[href]').forEach((link) => {
            const href = link.getAttribute('href') || '';
            if (/[?&]t=/.test(href)) return;
            if (!parseVKHref(href)) return;
            add(findCardRoot(link));
        });
        return cards;
    }

    function insertButtonsOnCards() {
        const seenIds = new Set();
        collectCards().forEach((card) => {
            if (isSkippableCard(card)) {
                markCard(card, 'skipped');
                return;
            }
            const video = findVideoLink(card);
            if (!video) return;
            if (seenIds.has(video.ref.id)) {
                markCard(card, 'added');
                return;
            }
            seenIds.add(video.ref.id);

            if (card.querySelector('.' + CARD_BUTTON_CLASS)) {
                markCard(card, 'added');
                return;
            }

            const author = findAuthorAnchor(card);
            const buttonContainer = createCardButton(video.ref);
            if (author) {
                const column = ensureAvatarColumn(author);
                column.appendChild(buttonContainer);
            } else {
                findMetaRow(card).appendChild(buttonContainer);
            }
            markCard(card, 'added');
        });
    }

    function refresh() {
        insertButtonOnWatchPage();
        insertButtonsOnCards();
    }

    function initObserver() {
        if (observerActive || !document.body) return;
        const observer = new MutationObserver(() => { refresh(); });
        observer.observe(document.body, { childList: true, subtree: true });
        observerActive = true;
    }

    function init() {
        refresh();
        initObserver();
        setInterval(refresh, CHECK_INTERVAL);
        window.addEventListener('popstate', refresh);
        ['pushState', 'replaceState'].forEach((method) => {
            const original = history[method];
            if (typeof original !== 'function') return;
            history[method] = function () {
                const result = original.apply(this, arguments);
                setTimeout(refresh, 200);
                setTimeout(refresh, 800);
                setTimeout(refresh, 2000);
                return result;
            };
        });
        let lastUrl = location.href;
        new MutationObserver(() => {
            if (location.href === lastUrl) return;
            lastUrl = location.href;
            setTimeout(refresh, 300);
            setTimeout(refresh, 1200);
        }).observe(document, { subtree: true, childList: true });
    }

    const api = {
        BUTTON_ID,
        CARD_BUTTON_CLASS,
        CARD_BUTTON_MARKER,
        parseVKHref,
        insertButtonOnWatchPage,
        insertButtonsOnCards,
        findWatchActionsRow,
        isUsable,
        refresh,
        init,
        get lastQueued() { return lastQueued; }
    };

    global.YTDVK = api;

    if (!global.__YTD_TEST__) {
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', init);
        } else {
            init();
        }
    }
})(typeof window !== 'undefined' ? window : globalThis);
