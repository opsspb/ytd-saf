import SafariServices
import AppKit
import os.log
import YTDownloaderCore

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {

    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem
        let message = request?.userInfo?[SFExtensionMessageKey] as? [String: Any]

        guard let action = message?["action"] as? String else {
            context.completeRequest(returningItems: nil, completionHandler: nil)
            return
        }

        if action == "download" {
            guard let videoId = message?["videoId"] as? String,
                  let url = message?["url"] as? String else {
                context.completeRequest(returningItems: nil, completionHandler: nil)
                return
            }

            let cookiesPayload = message?["cookies"] as? String
            var cookieRef: String?
            var responseCookies: String?

            if let cookiesPayload, !cookiesPayload.isEmpty,
               let netscape = ExtensionCookiePayload.netscapeText(fromURLPayload: cookiesPayload) {
                do {
                    cookieRef = try SharedCookieStore.writeNetscape(
                        videoId: videoId,
                        netscapeText: netscape
                    )
                } catch {
                    // Unsigned / no App Group: fall back to capped URL cookies.
                    os_log("YTDownloader: App Group cookie write failed, using URL fallback")
                    responseCookies = cookiesPayload
                }
            }

            // Best-effort backup. Content/background also open ytdownloader:// because
            // a sandboxed appex may not be allowed to launch the host via NSWorkspace.
            openHostApp(
                videoId: videoId,
                url: url,
                cookieRef: cookieRef,
                cookies: cookieRef == nil ? responseCookies : nil
            )

            var payload: [String: Any] = [
                "success": true,
                "videoId": videoId
            ]
            if let cookieRef {
                payload["cookieRef"] = cookieRef
            } else if let responseCookies {
                payload["cookies"] = responseCookies
            }

            let response = NSExtensionItem()
            response.userInfo = [SFExtensionMessageKey: payload]
            context.completeRequest(returningItems: [response], completionHandler: nil)
        } else {
            context.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    private func openHostApp(videoId: String, url: String, cookieRef: String?, cookies: String?) {
        guard let customURL = AppURL.downloadURL(
            videoId: videoId,
            url: url,
            cookies: cookies,
            cookieRef: cookieRef
        ) else {
            os_log("YTDownloader: failed to build custom URL")
            return
        }
        NSWorkspace.shared.open(customURL)
    }
}
