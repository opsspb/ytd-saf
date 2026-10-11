import SwiftUI

@main
struct YTDownloaderApp: App {
    @StateObject private var downloadManager = DownloadManager()
    @StateObject private var binaryManager = BinaryManager()
    @StateObject private var nativeMessaging = NativeMessaging.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(downloadManager)
                .environmentObject(binaryManager)
                .onOpenURL { url in
                    NativeMessaging.shared.handle(url: url)
                }
                .task {
                    NativeMessaging.shared.attach(downloadManager: downloadManager)
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
