// Background service worker
browser.runtime.onMessage.addListener((request, sender, sendResponse) => {
    if (request.action === 'download') {
        const { videoId, url } = request;
        
        browser.runtime.sendNativeMessage('application.id', {
            action: 'download',
            videoId: videoId,
            url: url
        }, (response) => {
            if (browser.runtime.lastError) {
                console.error('Native messaging error:', browser.runtime.lastError);
                sendResponse({ success: false, error: browser.runtime.lastError.message });
            } else {
                sendResponse(response);
            }
        });
        
        return true;
    }
});

browser.runtime.onInstalled.addListener(() => {
    console.log('YTDownloader extension installed');
});
