import SwiftUI
import AppKit

@main
struct YTDownloaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var downloadManager: DownloadManager
    @StateObject private var binaryManager: BinaryManager

    init() {
        let downloads = DownloadManager()
        downloads.attachProgressBridge()
        _downloadManager = StateObject(wrappedValue: downloads)
        let binaries = BinaryManager()
        _binaryManager = StateObject(wrappedValue: binaries)
        NativeMessaging.shared.attach(downloadManager: downloads)
        AppSession.shared.downloadManager = downloads
        AppSession.shared.binaryManager = binaries
    }

    var body: some Scene {
        Window("YTDownloader", id: AppScenes.queueWindowID) {
            ContentView()
                .environmentObject(downloadManager)
                .environmentObject(binaryManager)
                .background(QueueWindowBridge(tagWindow: true))
                .onOpenURL { url in
                    NativeMessaging.shared.handle(url: url)
                }
                .task {
                    AppSession.shared.start()
                }
        }
        .defaultSize(width: 860, height: 560)
        .handlesExternalEvents(matching: Set<String>())
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About YTDownloader") {}
            }
        }

        Settings {
            SettingsView()
                .environmentObject(downloadManager)
                .background(QueueWindowBridge(tagWindow: false))
        }
    }
}

/// Always-on SwiftUI hook so AppKit can call `openWindow(id: "queue")` and so
/// the queue `NSWindow` is tagged even when the scene starts hidden.
private struct QueueWindowBridge: View {
    var tagWindow = false
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if tagWindow {
                QueueWindowConfigurator()
            } else {
                Color.clear
            }
        }
        .frame(width: 0, height: 0)
        .accessibilityHidden(true)
        .onAppear {
            AppWindowController.shared.openQueueScene = {
                openWindow(id: AppScenes.queueWindowID)
            }
        }
    }
}

private struct QueueWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            tag(view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            tag(nsView.window)
        }
    }

    private func tag(_ window: NSWindow?) {
        guard let window else { return }
        Task { @MainActor in
            AppWindowController.shared.register(window)
        }
    }
}
