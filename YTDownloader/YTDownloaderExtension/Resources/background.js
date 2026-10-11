// Background service worker for Safari
browser.runtime.onMessage.addListener((request, sender, sendResponse) => {
    if (request.action === 'download') {
        const { videoId, url } = request;
        
        // Send message to the SafariWebExtensionHandler
        browser.runtime.sendMessage({
            action: 'download',
            videoId: videoId,
            url: url
        }).then(response => {
            sendResponse(response);
        }).catch(error => {
            console.error('Error sending message to native handler:', error);
            sendResponse({ success: false, error: error.message });
        });
        
        return true;
    }
});

browser.runtime.onInstalled.addListener(() => {
    console.log('YTDownloader extension installed');
});
