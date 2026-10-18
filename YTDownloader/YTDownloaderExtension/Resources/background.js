const MAX_COOKIES_ENCODED = 12000;

const PRIORITY_COOKIE_NAMES = new Set([
    'LOGIN_INFO', 'SID', 'HSID', 'SSID', 'APISID', 'SAPISID',
    '__Secure-1PSID', '__Secure-3PSID', '__Secure-1PSIDTS', '__Secure-3PSIDTS',
    '__Secure-1PAPISID', '__Secure-3PAPISID', 'SIDCC',
    '__Secure-1PSIDCC', '__Secure-3PSIDCC',
    'VISITOR_INFO1_LIVE', 'CONSENT', 'SOCS', 'PREF', 'ACCOUNT_CHOOSER',
    'remixsid', 'remixnsid', 'remixstid', 'remixlgck', 'remixdmgr', 'p',
    'remixpu', 'remixuas', 'remixdt'
]);

function domainsForPageURL(pageUrl) {
    try {
        const host = new URL(pageUrl).hostname.toLowerCase();
        if (host.includes('youtube') || host.includes('youtu.be') || host.includes('google')) {
            return ['youtube.com', 'google.com'];
        }
        if (host.includes('vk')) {
            return ['vk.com', 'vk.ru', 'vkvideo.ru'];
        }
    } catch (error) {
        // Fall through.
    }
    return [];
}

function cookiesToNetscape(cookies) {
    const lines = ['# Netscape HTTP Cookie File'];
    for (const c of cookies) {
        const domain = c.domain || '';
        const includeSub = domain.startsWith('.') ? 'TRUE' : 'FALSE';
        const path = c.path || '/';
        const secure = c.secure ? 'TRUE' : 'FALSE';
        let expires = '0';
        if (!c.session && typeof c.expirationDate === 'number') {
            expires = String(Math.floor(c.expirationDate));
        }
        lines.push([domain, includeSub, path, secure, expires, c.name, c.value].join('\t'));
    }
    return lines.join('\n');
}

function base64urlEncode(text) {
    const bytes = new TextEncoder().encode(text);
    let binary = '';
    for (let i = 0; i < bytes.length; i++) {
        binary += String.fromCharCode(bytes[i]);
    }
    return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/g, '');
}

function prioritizeCookies(cookies) {
    return cookies.slice().sort((a, b) => {
        const ap = PRIORITY_COOKIE_NAMES.has(a.name) ? 0 : 1;
        const bp = PRIORITY_COOKIE_NAMES.has(b.name) ? 0 : 1;
        if (ap !== bp) return ap - bp;
        return String(a.name).localeCompare(String(b.name));
    });
}

function encodeCookiesPayload(cookies) {
    if (!cookies || cookies.length === 0) return null;
    const ordered = prioritizeCookies(cookies);
    const tryEncode = (list) => {
        const encoded = base64urlEncode(cookiesToNetscape(list));
        return encoded.length <= MAX_COOKIES_ENCODED ? encoded : null;
    };
    let encoded = tryEncode(ordered);
    if (encoded) return encoded;
    let kept = ordered.filter((c) => PRIORITY_COOKIE_NAMES.has(c.name));
    if (kept.length === 0) {
        kept = ordered.slice(0, 20);
    }
    while (kept.length > 0) {
        encoded = tryEncode(kept);
        if (encoded) return encoded;
        kept.pop();
    }
    return null;
}

async function cookieStoreIds() {
    if (!browser.cookies.getAllCookieStores) {
        return [undefined];
    }
    try {
        const stores = await browser.cookies.getAllCookieStores();
        if (stores && stores.length) {
            return stores.map((store) => store.id);
        }
    } catch (error) {
        console.warn('YTDownloader: getAllCookieStores failed');
    }
    return [undefined];
}

async function collectCookiesForURL(pageUrl) {
    if (!browser.cookies || !browser.cookies.getAll) {
        return [];
    }
    const domains = domainsForPageURL(pageUrl);
    const seen = new Set();
    const all = [];
    const storeIds = await cookieStoreIds();

    const ingest = (batch) => {
        for (const cookie of batch || []) {
            const key = `${cookie.domain}\n${cookie.path}\n${cookie.name}`;
            if (seen.has(key)) continue;
            seen.add(key);
            all.push(cookie);
        }
    };

    for (const storeId of storeIds) {
        for (const domain of domains) {
            try {
                const query = { domain };
                if (storeId !== undefined) query.storeId = storeId;
                ingest(await browser.cookies.getAll(query));
            } catch (error) {
                // Safari returns nothing until host permission is granted via user gesture.
                console.warn('YTDownloader: cookies.getAll failed for domain');
            }
        }
        if (pageUrl) {
            try {
                const query = { url: pageUrl };
                if (storeId !== undefined) query.storeId = storeId;
                ingest(await browser.cookies.getAll(query));
            } catch (error) {
                // Ignore URL-scoped failures.
            }
        }
    }
    return all;
}

function downloadSchemeURL(videoId, url, { cookiesPayload, cookieRef } = {}) {
    const params = new URLSearchParams({ videoId, url });
    if (cookieRef) {
        params.set('cookieRef', cookieRef);
    } else if (cookiesPayload) {
        params.set('cookies', cookiesPayload);
    }
    return `ytdownloader://download?${params.toString()}`;
}

function openHostApp(videoId, url, handoff = {}) {
    const scheme = downloadSchemeURL(videoId, url, handoff);

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

function notifyNativeHandler(videoId, url, cookiesPayload) {
    const payload = { action: 'download', videoId, url };
    if (cookiesPayload) {
        payload.cookies = cookiesPayload;
    }
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

    (async () => {
        const cookies = await collectCookiesForURL(url);
        const cookiesPayload = encodeCookiesPayload(cookies);
        let cookieRef = null;
        let via = 'url-scheme';

        try {
            const response = await notifyNativeHandler(videoId, url, cookiesPayload);
            if (response && response.cookieRef) {
                cookieRef = response.cookieRef;
                via = 'native-app-group';
            } else if (response && response.success) {
                via = 'native';
            }
        } catch (error) {
            console.warn('YTDownloader: native handler unavailable, URL scheme used instead', error);
        }

        // Prefer short cookieRef URL; fall back to capped cookies= only when needed.
        openHostApp(videoId, url, {
            cookieRef,
            cookiesPayload: cookieRef ? null : cookiesPayload
        });

        sendResponse({
            success: true,
            videoId,
            via,
            cookieRef: cookieRef || undefined,
            cookies: cookieRef ? undefined : (cookiesPayload || undefined),
            cookieCount: cookies.length
        });
    })();

    return true;
});

browser.runtime.onInstalled.addListener(() => {
    console.log('YTDownloader extension installed');
});
