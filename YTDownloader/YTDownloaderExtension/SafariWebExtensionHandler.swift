import SafariServices
import AppKit
import os.log

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

            let cookies = message?["cookies"] as? String

            // Best-effort backup. The content/background scripts also open
            // ytdownloader:// because a sandboxed appex may not be allowed
            // to launch the host app via NSWorkspace.
            openHostApp(videoId: videoId, url: url, cookies: cookies)

            let response = NSExtensionItem()
            response.userInfo = [
                SFExtensionMessageKey: [
                    "success": true,
                    "videoId": videoId
                ]
            ]
            context.completeRequest(returningItems: [response], completionHandler: nil)
        } else {
            context.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    private func openHostApp(videoId: String, url: String, cookies: String?) {
        var components = URLComponents()
        components.scheme = "ytdownloader"
        components.host = "download"
        var items = [
            URLQueryItem(name: "videoId", value: videoId),
            URLQueryItem(name: "url", value: url)
        ]
        if let cookies, !cookies.isEmpty {
            items.append(URLQueryItem(name: "cookies", value: cookies))
        }
        components.queryItems = items
        guard let customURL = components.url else {
            os_log("YTDownloader: failed to build custom URL")
            return
        }
        NSWorkspace.shared.open(customURL)
    }
}
