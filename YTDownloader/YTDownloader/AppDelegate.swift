import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Register the Apple Event handler before Launch Services delivers
        // the ytdownloader:// URL that launched the app.
        _ = NativeMessaging.shared
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            NativeMessaging.shared.handle(url: url)
        }
    }
}
