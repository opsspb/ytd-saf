import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        _ = NativeMessaging.shared
        AppWindowController.shared.launchSuppressionDeadline = Date().addingTimeInterval(1.5)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowBecameVisible(_:)),
            name: Notification.Name("NSWindowDidBecomeVisibleNotification"),
            object: nil
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppSession.shared.start()
        AppWindowController.shared.suppressUnsolicitedWindows()
        DispatchQueue.main.async {
            AppWindowController.shared.suppressUnsolicitedWindows()
            AppWindowController.shared.attachDelegate()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            NativeMessaging.shared.handle(url: url)
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func windowBecameVisible(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        Task { @MainActor in
            guard AppWindowController.shared.shouldSuppressUnsolicited(window) else { return }
            window.orderOut(nil)
        }
    }
}
