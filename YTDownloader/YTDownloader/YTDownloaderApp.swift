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
        MenuBarExtra {
            StatusMenuContent(downloadManager: downloadManager)
        } label: {
            Text("YD")
                .font(.system(size: 12, weight: .bold))
        }
        .menuBarExtraStyle(.menu)

        Window("YTDownloader", id: AppScenes.queueWindowID) {
            ContentView()
                .environmentObject(downloadManager)
                .environmentObject(binaryManager)
                .background(QueueWindowBridge())
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
        }
    }
}

/// Tags the SwiftUI queue `NSWindow` so AppKit can bring it forward above Safari.
private struct QueueWindowBridge: View {
    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .background(QueueWindowConfigurator())
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
