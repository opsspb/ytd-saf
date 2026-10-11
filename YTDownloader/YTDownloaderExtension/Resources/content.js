// Content script for YouTube pages
(function() {
    'use strict';
    
    const BUTTON_ID = 'ytd-download-button';
    const CHECK_INTERVAL = 1000;
    let observerActive = false;
    
    function getVideoId() {
        const urlParams = new URLSearchParams(window.location.search);
        return urlParams.get('v');
    }
    
    function getCanonicalUrl() {
        const videoId = getVideoId();
        if (!videoId) return null;
        return `https://www.youtube.com/watch?v=${videoId}`;
    }
    
    function createDownloadButton() {
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
        
        button.addEventListener('click', handleDownloadClick);
        
        return button;
    }
    
    async function handleDownloadClick(e) {
        e.preventDefault();
        e.stopPropagation();
        
        const button = e.target;
        const videoId = getVideoId();
        const url = getCanonicalUrl();
        
        if (!videoId || !url) {
            button.textContent = '❌';
            setTimeout(() => {
                button.textContent = 'YD';
            }, 2000);
            return;
        }
        
        button.textContent = '⏳';
        button.disabled = true;
        
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
        
        const button = createDownloadButton();
        actionsContainer.insertBefore(button, actionsContainer.firstChild);
    }
    
    function insertButtonOnThumbnails() {
        const thumbnails = document.querySelectorAll('ytd-thumbnail:not([data-ytd-button])');
        
        thumbnails.forEach(thumbnail => {
            thumbnail.setAttribute('data-ytd-button', 'true');
            
            const linkElement = thumbnail.querySelector('a#thumbnail');
            if (!linkElement) return;
            
            const href = linkElement.getAttribute('href');
            if (!href || !href.includes('/watch?v=')) return;
            
            const urlParams = new URLSearchParams(href.split('?')[1]);
            const videoId = urlParams.get('v');
            if (!videoId) return;
            
            const container = thumbnail.querySelector('#mouseover-overlay, ytd-thumbnail-overlay-toggle-button-renderer');
            if (!container) return;
            
            const button = document.createElement('button');
            button.className = 'ytd-thumbnail-button';
            button.style.cssText = `
                position: absolute;
                top: 8px;
                right: 8px;
                background: rgba(0, 0, 0, 0.8);
                color: white;
                border: none;
                border-radius: 4px;
                padding: 4px 8px;
                font-size: 12px;
                font-weight: 600;
                cursor: pointer;
                z-index: 100;
                backdrop-filter: blur(4px);
            `;
            button.textContent = 'YD';
            
            button.addEventListener('click', async (e) => {
                e.preventDefault();
                e.stopPropagation();
                
                const url = `https://www.youtube.com/watch?v=${videoId}`;
                button.textContent = '⏳';
                button.disabled = true;
                
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
            });
            
            thumbnail.style.position = 'relative';
            thumbnail.appendChild(button);
        });
    }
    
    function initObserver() {
        if (observerActive) return;
        
        const observer = new MutationObserver(() => {
            insertButtonOnWatchPage();
            insertButtonOnThumbnails();
        });
        
        observer.observe(document.body, {
            childList: true,
            subtree: true
        });
        
        observerActive = true;
    }
    
    function init() {
        insertButtonOnWatchPage();
        insertButtonOnThumbnails();
        initObserver();
        
        setInterval(() => {
            insertButtonOnWatchPage();
            insertButtonOnThumbnails();
        }, CHECK_INTERVAL);
    }
    
    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', init);
    } else {
        init();
    }
    
    let lastUrl = location.href;
    new MutationObserver(() => {
        const currentUrl = location.href;
        if (currentUrl !== lastUrl) {
            lastUrl = currentUrl;
            setTimeout(() => {
                insertButtonOnWatchPage();
                insertButtonOnThumbnails();
            }, 500);
        }
    }).observe(document, { subtree: true, childList: true });
    
})();
