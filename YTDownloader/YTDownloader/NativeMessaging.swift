import Foundation

class NativeMessaging: ObservableObject {
    static let shared = NativeMessaging()
    
    weak var downloadManager: DownloadManager?
    
    private let groupIdentifier = "group.com.ytdownloader.shared"
    private var containerURL: URL?
    private var requestsURL: URL?
    private var timer: Timer?
    
    private init() {
        setupSharedContainer()
        startMonitoring()
    }
    
    private func setupSharedContainer() {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier) else {
            print("Failed to get app group container")
            return
        }
        
        containerURL = container
        requestsURL = container.appendingPathComponent("requests")
        
        try? FileManager.default.createDirectory(at: requestsURL!, withIntermediateDirectories: true)
    }
    
    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForRequests()
        }
    }
    
    private func checkForRequests() {
        guard let requestsURL = requestsURL else { return }
        
        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: requestsURL,
                includingPropertiesForKeys: nil
            )
            
            for file in files where file.pathExtension == "json" {
                processRequest(at: file)
            }
        } catch {
            // Silent fail
        }
    }
    
    private func processRequest(at url: URL) {
        do {
            let data = try Data(contentsOf: url)
            let request = try JSONDecoder().decode(DownloadRequest.self, from: data)
            
            Task { @MainActor in
                downloadManager?.addDownload(videoId: request.videoId, url: request.url)
            }
            
            try FileManager.default.removeItem(at: url)
        } catch {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    func sendStatusUpdate(videoId: String, status: String, progress: Double) {
        // Optional: write status to shared container for extension to read
    }
}

struct DownloadRequest: Codable {
    let videoId: String
    let url: String
    let timestamp: Date
}
