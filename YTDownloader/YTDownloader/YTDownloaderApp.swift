import SwiftUI

@main
struct YTDownloaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var downloadManager: DownloadManager
    @StateObject private var binaryManager: BinaryManager

    init() {
        let downloads = DownloadManager()
        _downloadManager = StateObject(wrappedValue: downloads)
        _binaryManager = StateObject(wrappedValue: BinaryManager())
        // Attach before the first scene so a launch URL is not dropped.
        NativeMessaging.shared.attach(downloadManager: downloads)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(downloadManager)
                .environmentObject(binaryManager)
                .onOpenURL { url in
                    NativeMessaging.shared.handle(url: url)
                }
                .task {
                    await binaryManager.setup()
                }
        }
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About YTDownloader") {
                }
            }
        }

        Settings {
            SettingsView()
                .environmentObject(downloadManager)
        }
    }
}
