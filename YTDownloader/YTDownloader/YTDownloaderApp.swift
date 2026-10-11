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
        let binaries = BinaryManager()
        _binaryManager = StateObject(wrappedValue: binaries)
        NativeMessaging.shared.attach(downloadManager: downloads)
        AppSession.shared.downloadManager = downloads
        AppSession.shared.binaryManager = binaries
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
