import Foundation
import AppKit
import YTDownloaderCore

class NativeMessaging: ObservableObject {
    static let shared = NativeMessaging()

    private var pending: [(videoId: String, url: String, cookies: String?)] = []
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
        guard let command = AppURL.parse(url) else { return }
        switch command {
        case .showQueue:
            Task { @MainActor in
                AppWindowController.shared.showQueue(activate: true)
            }
        case .showSettings:
            Task { @MainActor in
                AppWindowController.shared.showSettings()
            }
        case .download(let videoId, let url, let cookies):
            enqueue(videoId: videoId, url: url, cookies: cookies)
        }
    }

    @objc private func handleGetURLEvent(_ event: NSAppleEventDescriptor, replyEvent: NSAppleEventDescriptor) {
        guard let urlString = event.paramDescriptor(forKeyword: keyDirectObject)?.stringValue,
              let url = URL(string: urlString) else {
            return
        }
        handle(url: url)
    }

    private func enqueue(videoId: String, url: String, cookies: String?) {
        if let manager {
            Task { @MainActor in
                manager.addDownload(videoId: videoId, url: url, cookiesPayload: cookies)
            }
        } else {
            pending.append((videoId, url, cookies))
        }
    }

    private func flushPending() {
        guard let manager else { return }
        let items = pending
        pending.removeAll()
        Task { @MainActor in
            for item in items {
                manager.addDownload(videoId: item.videoId, url: item.url, cookiesPayload: item.cookies)
            }
        }
    }
}
