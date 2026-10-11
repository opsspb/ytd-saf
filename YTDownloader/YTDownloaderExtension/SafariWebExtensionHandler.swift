import SafariServices
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
            
            DistributedNotificationCenter.default().post(
                name: NSNotification.Name("com.ytdownloader.download"),
                object: nil,
                userInfo: [
                    "videoId": videoId,
                    "url": url
                ]
            )
            
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
}
