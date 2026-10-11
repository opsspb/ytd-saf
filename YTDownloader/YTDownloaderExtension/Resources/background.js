function downloadSchemeURL(videoId, url) {
    const params = new URLSearchParams({ videoId, url });
    return `ytdownloader://download?${params.toString()}`;
}

function openHostApp(videoId, url) {
    const scheme = downloadSchemeURL(videoId, url);

    // Custom-scheme navigation from the extension page launches the host app
    // even when the sandboxed native handler cannot call NSWorkspace.
    if (browser.tabs && browser.tabs.create) {
        browser.tabs.create({ url: scheme, active: false }).then((tab) => {
            if (tab && tab.id && browser.tabs.remove) {
                setTimeout(() => {
                    browser.tabs.remove(tab.id).catch(() => {});
                }, 2000);
            }
        }).catch((error) => {
            console.warn('YTDownloader: tabs.create scheme failed', error);
        });
    }
}

function notifyNativeHandler(videoId, url) {
    const payload = { action: 'download', videoId, url };
    if (browser.runtime.sendNativeMessage) {
        return browser.runtime.sendNativeMessage('com.ytdownloader.app', payload);
    }
    return Promise.resolve(null);
}

browser.runtime.onMessage.addListener((request, sender, sendResponse) => {
    if (request.action !== 'download') {
        return;
    }

    const { videoId, url } = request;
    openHostApp(videoId, url);

    notifyNativeHandler(videoId, url).then((response) => {
        sendResponse(response || { success: true, videoId });
    }).catch((error) => {
        console.warn('YTDownloader: native handler unavailable, URL scheme used instead', error);
        sendResponse({ success: true, videoId, via: 'url-scheme' });
    });

    return true;
});

browser.runtime.onInstalled.addListener(() => {
    console.log('YTDownloader extension installed');
});
