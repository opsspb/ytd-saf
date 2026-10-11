import Foundation
import AppKit

class NativeMessaging: ObservableObject {
    static let shared = NativeMessaging()

    private var pending: [(videoId: String, url: String)] = []
    private var manager: DownloadManager?

    private init() {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleGetURLEvent(_:replyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func attach(downloadManager: DownloadManager) {
        manager = downloadManager
        flushPending()
    }

    func handle(url: URL) {
        guard url.scheme == "ytdownloader" else { return }
        guard url.host == "download" || url.path == "/download" || url.path.isEmpty else { return }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return }
        let items = components.queryItems ?? []
        let videoId = items.first(where: { $0.name == "videoId" })?.value
        let videoURL = items.first(where: { $0.name == "url" })?.value
        guard let videoId, let videoURL else { return }
        enqueue(videoId: videoId, url: videoURL)
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else {
            return
        }
        handle(url: url)
    }

    private func enqueue(videoId: String, url: String) {
        if let manager {
            Task { @MainActor in
                manager.addDownload(videoId: videoId, url: url)
            }
        } else {
            pending.append((videoId, url))
        }
    }

    private func flushPending() {
        guard let manager else { return }
        let items = pending
        pending.removeAll()
        Task { @MainActor in
            for item in items {
                manager.addDownload(videoId: item.videoId, url: item.url)
            }
        }
    }
}
