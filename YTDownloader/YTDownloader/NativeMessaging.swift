import Foundation

class NativeMessaging: ObservableObject {
    static let shared = NativeMessaging()
    
    weak var downloadManager: DownloadManager?
    
    private init() {
        setupMessageListener()
    }
    
    private func setupMessageListener() {
        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleMessage(_:)),
            name: NSNotification.Name("com.ytdownloader.download"),
            object: nil
        )
    }
    
    @objc private func handleMessage(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let videoId = userInfo["videoId"] as? String,
              let url = userInfo["url"] as? String else {
            return
        }
        
        Task { @MainActor in
            downloadManager?.addDownload(videoId: videoId, url: url)
        }
    }
    
    func sendStatusUpdate(videoId: String, status: String, progress: Double) {
        DistributedNotificationCenter.default().post(
            name: NSNotification.Name("com.ytdownloader.status"),
            object: nil,
            userInfo: [
                "videoId": videoId,
                "status": status,
                "progress": progress
            ]
        )
    }
}
