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
                .task {
                    await binaryManager.setup()
                    nativeMessaging.downloadManager = downloadManager
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
