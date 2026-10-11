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
            
            sendDownloadRequest(videoId: videoId, url: url)
            
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
    
    private func sendDownloadRequest(videoId: String, url: String) {
        let urlString = "ytdownloader://download?videoId=\(videoId)&url=\(url.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url)"
        
        guard let customURL = URL(string: urlString) else {
            os_log("Failed to create custom URL")
            return
        }
        
        NSWorkspace.shared.open(customURL)
    }
}
