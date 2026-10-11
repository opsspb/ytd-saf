import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        _ = NativeMessaging.shared
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        activateMainWindow()
        coalesceWindows()
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            NativeMessaging.shared.handle(url: url)
        }
        activateMainWindow()
        coalesceWindows()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        activateMainWindow()
        return true
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    private func activateMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = mainWindows().first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    private func coalesceWindows() {
        let extras = Array(mainWindows().dropFirst())
        extras.forEach { $0.close() }
    }

    private func mainWindows() -> [NSWindow] {
        NSApp.windows.filter { window in
            window.canBecomeMain
                && !(window is NSPanel)
                && window.level == .normal
                && !window.title.contains("Settings")
                && !window.title.contains("Preferences")
        }
    }
}
