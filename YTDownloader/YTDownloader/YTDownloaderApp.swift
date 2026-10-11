import SwiftUI

@main
struct YTDownloaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var downloadManager: DownloadManager
    @StateObject private var binaryManager: BinaryManager

    init() {
        let downloads = DownloadManager()
        downloads.attachProgressBridge()
        _downloadManager = StateObject(wrappedValue: downloads)
        _binaryManager = StateObject(wrappedValue: BinaryManager())
        NativeMessaging.shared.attach(downloadManager: downloads)
    }

    var body: some Scene {
        Window("YTDownloader", id: "main") {
            ContentView()
                .environmentObject(downloadManager)
                .environmentObject(binaryManager)
                .onOpenURL { url in
                    NativeMessaging.shared.handle(url: url)
                }
                .task {
                    await binaryManager.setup()
                    downloadManager.resumeQueue()
                }
        }
        .defaultSize(width: 860, height: 560)
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
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
