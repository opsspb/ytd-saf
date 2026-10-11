// Content script for YouTube pages
(function() {
    'use strict';
    
    const BUTTON_ID = 'ytd-download-button';
    const CARD_BUTTON_CLASS = 'ytd-card-download-button';
    const CARD_BUTTON_MARKER = 'data-ytd-card-button';
    const CHECK_INTERVAL = 1000;
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
        const match = url.match(/[?&]v=([^&]+)/);
        return match ? match[1] : null;
    }
    
    function createWatchPageButton() {
        const button = document.createElement('button');
        button.id = BUTTON_ID;
        button.className = 'yt-spec-button-shape-next yt-spec-button-shape-next--tonal yt-spec-button-shape-next--mono yt-spec-button-shape-next--size-m';
        button.style.cssText = `
            margin-left: 8px;
            font-weight: 500;
            font-size: 14px;
            padding: 0 16px;
            height: 36px;
            border-radius: 18px;
            cursor: pointer;
        `;
        button.setAttribute('aria-label', 'Download with YTDownloader');
        button.textContent = 'YD';
        
        button.addEventListener('click', handleWatchPageClick);
        
        return button;
    }
    
    async function handleWatchPageClick(e) {
        e.preventDefault();
        e.stopPropagation();
        
        const button = e.target;
        const videoId = getVideoId();
        const url = getCanonicalUrl(videoId);
        
        if (!videoId || !url) {
            button.textContent = '❌';
            setTimeout(() => {
                button.textContent = 'YD';
            }, 2000);
            return;
        }
        
        await queueDownload(button, videoId, url);
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
            const response = await browser.runtime.sendMessage({
                action: 'download',
                videoId: videoId,
                url: url
            });
            
            if (response && response.success) {
                button.textContent = '✓';
                setTimeout(() => {
                    button.textContent = 'YD';
                    button.disabled = false;
                }, 2000);
            } else {
                throw new Error('Download failed');
            }
        } catch (error) {
            console.error('YTDownloader error:', error);
            button.textContent = '❌';
            setTimeout(() => {
                button.textContent = 'YD';
                button.disabled = false;
            }, 2000);
        }
    }
    
    function insertButtonOnWatchPage() {
        if (document.getElementById(BUTTON_ID)) return;
        
        const videoId = getVideoId();
        if (!videoId) return;
        
        const actionsContainer = document.querySelector('#top-level-buttons-computed');
        if (!actionsContainer) return;
        
        const button = createWatchPageButton();
        actionsContainer.insertBefore(button, actionsContainer.firstChild);
    }
    
    function insertButtonsOnCards() {
        // Target video cards in grid/list views - skip Shorts and ads
        const cardSelectors = [
            'ytd-rich-item-renderer:not([data-ytd-card-button])',
            'ytd-grid-video-renderer:not([data-ytd-card-button])',
            'ytd-video-renderer:not([data-ytd-card-button])',
            'ytd-compact-video-renderer:not([data-ytd-card-button])'
        ];
        
        const cards = document.querySelectorAll(cardSelectors.join(','));
        
        cards.forEach(card => {
            // Skip if already processed
            if (card.hasAttribute(CARD_BUTTON_MARKER)) return;
            
            // Skip Shorts
            if (card.querySelector('[overlay-style="SHORTS"]') || 
                card.querySelector('a[href*="/shorts/"]')) {
                card.setAttribute(CARD_BUTTON_MARKER, 'skipped');
                return;
            }
            
            // Skip ads
            if (card.querySelector('[aria-label*="Sponsored"]') ||
                card.closest('ytd-ad-slot-renderer')) {
                card.setAttribute(CARD_BUTTON_MARKER, 'skipped');
                return;
            }
            
            // Find the video link
            const linkElement = card.querySelector('a#video-title-link, a#thumbnail, a.ytd-thumbnail');
            if (!linkElement) {
                card.setAttribute(CARD_BUTTON_MARKER, 'no-link');
                return;
            }
            
            const href = linkElement.getAttribute('href');
            const videoId = extractVideoIdFromUrl(href);
            if (!videoId) {
                card.setAttribute(CARD_BUTTON_MARKER, 'no-id');
                return;
            }
            
            // Find metadata area with channel avatar
            const metadataArea = card.querySelector('#metadata, #meta, ytd-video-meta-block');
            if (!metadataArea) {
                card.setAttribute(CARD_BUTTON_MARKER, 'no-metadata');
                return;
            }
            
            // Find channel avatar area (left column)
            const channelAvatar = metadataArea.querySelector('#avatar, #channel-thumbnail, a.ytd-channel-name');
            const avatarContainer = channelAvatar ? channelAvatar.closest('#avatar-link, #channel-info, .ytd-channel-name') : null;
            
            if (!avatarContainer) {
                card.setAttribute(CARD_BUTTON_MARKER, 'no-avatar');
                return;
            }
            
            // Create button - place it in a separate container to isolate from link handlers
            const buttonContainer = document.createElement('div');
            buttonContainer.className = 'ytd-card-button-container';
            buttonContainer.style.cssText = `
                display: flex;
                margin-top: 4px;
                pointer-events: auto;
            `;
            
            const button = document.createElement('button');
            button.className = CARD_BUTTON_CLASS;
            button.style.cssText = `
                background: var(--yt-spec-badge-chip-background);
                color: var(--yt-spec-text-primary);
                border: 1px solid var(--yt-spec-10-percent-layer);
                border-radius: 18px;
                padding: 4px 12px;
                font-size: 12px;
                font-weight: 500;
                cursor: pointer;
                font-family: "YouTube Sans", "Roboto", sans-serif;
                white-space: nowrap;
                transition: background 0.1s;
            `;
            button.textContent = 'YD';
            button.setAttribute('aria-label', 'Download video');
            button.setAttribute('data-video-id', videoId);
            
            // Add hover effect
            button.addEventListener('mouseenter', () => {
                button.style.background = 'var(--yt-spec-badge-chip-background-hover, rgba(255,255,255,0.1))';
            });
            button.addEventListener('mouseleave', () => {
                button.style.background = 'var(--yt-spec-badge-chip-background)';
            });
            
            // Critical: prevent all navigation/playback triggers
            // Use capture phase to intercept before YouTube's handlers
            const preventNavigation = (e) => {
                e.preventDefault();
                e.stopPropagation();
                e.stopImmediatePropagation();
            };
            
            ['mousedown', 'pointerdown', 'touchstart', 'click', 'auxclick'].forEach(eventType => {
                button.addEventListener(eventType, preventNavigation, true);
            });
            
            // Handle actual download on click (after prevention)
            button.addEventListener('click', async (e) => {
                preventNavigation(e);
                const url = getCanonicalUrl(videoId);
                await queueDownload(button, videoId, url);
            });
            
            buttonContainer.appendChild(button);
            
            // Insert below avatar
            if (avatarContainer.parentElement) {
                avatarContainer.parentElement.insertBefore(buttonContainer, avatarContainer.nextSibling);
            } else {
                avatarContainer.after(buttonContainer);
            }
            
            card.setAttribute(CARD_BUTTON_MARKER, 'added');
        });
    }
    
    function initObserver() {
        if (observerActive) return;
        
        const observer = new MutationObserver(() => {
            insertButtonOnWatchPage();
            insertButtonsOnCards();
        });
        
        observer.observe(document.body, {
            childList: true,
            subtree: true
        });
        
        observerActive = true;
    }
    
    function init() {
        insertButtonOnWatchPage();
        insertButtonsOnCards();
        initObserver();
        
        setInterval(() => {
            insertButtonOnWatchPage();
            insertButtonsOnCards();
        }, CHECK_INTERVAL);
    }
    
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
    
    // SPA navigation detection
    let lastUrl = location.href;
    new MutationObserver(() => {
        const currentUrl = location.href;
        if (currentUrl !== lastUrl) {
            lastUrl = currentUrl;
            setTimeout(() => {
                insertButtonOnWatchPage();
                insertButtonsOnCards();
            }, 500);
        }
    }).observe(document, { subtree: true, childList: true });
    
})();
