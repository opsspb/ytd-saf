import Foundation
import AppKit

class NativeMessaging: ObservableObject {
    static let shared = NativeMessaging()
    
    weak var downloadManager: DownloadManager?
    
    private init() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }
    
    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString),
              url.scheme == "ytdownloader",
              url.host == "download" else {
            return
        }
        
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            return
        }
        
        var videoId: String?
        var videoURL: String?
        
        for item in queryItems {
            if item.name == "videoId" {
                videoId = item.value
            } else if item.name == "url" {
                videoURL = item.value
            }
        }
        
        guard let videoId = videoId, let videoURL = videoURL else {
            return
        }
        
        Task { @MainActor in
            downloadManager?.addDownload(videoId: videoId, url: videoURL)
        }
    }
    
    func sendStatusUpdate(videoId: String, status: String, progress: Double) {
        // Future: Could implement distributed notifications for status updates
    }
}
