import SafariServices
import os.log

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    private let groupIdentifier = "group.com.ytdownloader.shared"
    
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
            
            let success = sendDownloadRequest(videoId: videoId, url: url)
            launchHostApp()
            
            let response = NSExtensionItem()
            response.userInfo = [
                SFExtensionMessageKey: [
                    "success": success,
                    "videoId": videoId
                ]
            ]
            
            context.completeRequest(returningItems: [response], completionHandler: nil)
        } else {
            context.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }
    
    private func sendDownloadRequest(videoId: String, url: String) -> Bool {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            os_log("Failed to get app group container")
            return false
        }
        
        let requestsURL = containerURL.appendingPathComponent("requests")
        try? FileManager.default.createDirectory(at: requestsURL, withIntermediateDirectories: true)
        
        let downloadRequest = DownloadRequest(videoId: videoId, url: url, timestamp: Date())
        
        do {
            let data = try JSONEncoder().encode(downloadRequest)
            let fileName = "\(UUID().uuidString).json"
            let fileURL = requestsURL.appendingPathComponent(fileName)
            try data.write(to: fileURL)
            return true
        } catch {
            os_log("Failed to write download request: %@", error.localizedDescription)
            return false
        }
    }
    
    private func launchHostApp() {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/Applications/YTDownloader.app"),
                                          configuration: configuration,
                                          completionHandler: nil)
    }
}

struct DownloadRequest: Codable {
    let videoId: String
    let url: String
    let timestamp: Date
}
