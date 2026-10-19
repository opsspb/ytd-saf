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

const KEY_AUTH_COOKIE_NAMES = [
    'LOGIN_INFO', '__Secure-3PSID', '__Secure-1PSID', 'SID', 'SAPISID', 'SSID', 'HSID'
];

/** One year — session cookies must not use Netscape expiry 0. */
const SESSION_COOKIE_LIFETIME_SEC = 365 * 24 * 60 * 60;

function domainsForPageURL(pageUrl) {
    try {
        const host = new URL(pageUrl).hostname.toLowerCase();
        if (host.includes('youtube') || host.includes('youtu.be') || host.includes('google')) {
            return ['youtube.com', '.youtube.com', 'google.com', '.google.com', 'accounts.google.com'];
        }
        if (host.includes('vk')) {
            return ['vk.com', '.vk.com', 'vk.ru', '.vk.ru', 'vkvideo.ru', '.vkvideo.ru'];
        }
    } catch (error) {
        // Fall through.
    }
    return [];
}

function cookieURLsForPageURL(pageUrl) {
    try {
        const host = new URL(pageUrl).hostname.toLowerCase();
        if (host.includes('youtube') || host.includes('youtu.be') || host.includes('google')) {
            return [
                'https://www.youtube.com',
                'https://youtube.com',
                'https://accounts.google.com',
                'https://www.google.com'
            ];
        }
        if (host.includes('vk')) {
            return [
                'https://vk.com',
                'https://www.vk.com',
                'https://vk.ru',
                'https://vkvideo.ru',
                'https://www.vkvideo.ru'
            ];
        }
    } catch (error) {
        // Fall through.
    }
    if (pageUrl) return [pageUrl];
    return [];
}

function sanitizeField(value) {
    return String(value == null ? '' : value)
        .replace(/\r/g, '')
        .replace(/\n/g, '')
        .replace(/\t/g, ' ');
}

function normalizeCookie(cookie, nowSec) {
    let domain = String(cookie.domain || '').trim();
    const hostOnly = cookie.hostOnly === true;
    const wantSubdomains = cookie.hostOnly === false || (!hostOnly && domain.startsWith('.'));
    if (wantSubdomains) {
        if (domain && !domain.startsWith('.')) domain = '.' + domain;
    } else if (domain.startsWith('.')) {
        domain = domain.slice(1);
    }

    let expires = null;
    const isSession = cookie.session === true || typeof cookie.expirationDate !== 'number';
    if (isSession) {
        expires = Math.floor(nowSec + SESSION_COOKIE_LIFETIME_SEC);
    } else {
        expires = Math.floor(cookie.expirationDate);
    }

    return {
        name: sanitizeField(cookie.name),
        value: sanitizeField(cookie.value),
        domain,
        path: sanitizeField(cookie.path || '/'),
        secure: !!cookie.secure,
        httpOnly: !!cookie.httpOnly,
        expirationDate: expires,
        session: false,
        hostOnly: !wantSubdomains
    };
}

function dedupeCookies(cookies) {
    const best = new Map();
    const order = [];
    for (const cookie of cookies) {
        const key = `${cookie.domain.toLowerCase()}\n${cookie.path}\n${cookie.name}`;
        const existing = best.get(key);
        if (!existing) {
            best.set(key, cookie);
            order.push(key);
            continue;
        }
        const existingExpiry = existing.expirationDate || 0;
        const newExpiry = cookie.expirationDate || 0;
        if (newExpiry > existingExpiry || (newExpiry === existingExpiry && cookie.value.length > existing.value.length)) {
            best.set(key, cookie);
        }
    }
    return order.map((key) => best.get(key));
}

function cookiesToNetscape(cookies) {
    const nowSec = Date.now() / 1000;
    const normalized = dedupeCookies(cookies.map((c) => normalizeCookie(c, nowSec)));
    const lines = ['# Netscape HTTP Cookie File'];
    for (const c of normalized) {
        const domain = c.domain || '';
        const includeSub = domain.startsWith('.') ? 'TRUE' : 'FALSE';
        const path = c.path || '/';
        const secure = c.secure ? 'TRUE' : 'FALSE';
        const expires = String(c.expirationDate);
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

function logAuthCookiePresence(cookies) {
    const names = new Set((cookies || []).map((c) => c.name));
    const present = KEY_AUTH_COOKIE_NAMES.filter((n) => names.has(n));
    const missing = KEY_AUTH_COOKIE_NAMES.filter((n) => !names.has(n));
    console.log(
        'YTDownloader: auth cookies present=[' + present.join(',') +
        '] missing=[' + missing.join(',') + '] total=' + (cookies ? cookies.length : 0)
    );
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

function partitionQueries(url) {
    const queries = [{ url }];
    // Chromium-style partitioned cookies / Firefox firstPartyDomain when available.
    try {
        const host = new URL(url).hostname;
        if (typeof browser !== 'undefined' && browser.cookies) {
            queries.push({ url, partitionKey: { topLevelSite: `https://${host}` } });
            queries.push({ url, firstPartyDomain: host });
            queries.push({ url, firstPartyDomain: '' });
        }
    } catch (error) {
        // Ignore URL parse failures.
    }
    return queries;
}

async function collectCookiesForURL(pageUrl) {
    if (!browser.cookies || !browser.cookies.getAll) {
        return [];
    }
    const domains = domainsForPageURL(pageUrl);
    const urls = cookieURLsForPageURL(pageUrl);
    if (pageUrl && !urls.includes(pageUrl)) {
        urls.push(pageUrl);
    }
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
                console.warn('YTDownloader: cookies.getAll failed for domain');
            }
        }
        for (const url of urls) {
            for (const base of partitionQueries(url)) {
                try {
                    const query = Object.assign({}, base);
                    if (storeId !== undefined) query.storeId = storeId;
                    ingest(await browser.cookies.getAll(query));
                } catch (error) {
                    // Safari may reject partitionKey / firstPartyDomain — ignore.
                }
            }
        }
    }
    logAuthCookiePresence(all);
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

function notifyNativeHandler(videoId, url, { cookiesPayload, netscapeFull } = {}) {
    const payload = { action: 'download', videoId, url };
    // Prefer uncapped Netscape for App Group write; URL-capped payload is fallback.
    if (netscapeFull) {
        payload.netscapeFull = netscapeFull;
    }
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
        const fullNetscape = cookies.length ? cookiesToNetscape(cookies) : null;
        const netscapeFull = fullNetscape ? base64urlEncode(fullNetscape) : null;
        const cookiesPayload = encodeCookiesPayload(cookies);
        let cookieRef = null;
        let via = 'url-scheme';

        try {
            const response = await notifyNativeHandler(videoId, url, {
                cookiesPayload,
                netscapeFull
            });
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
