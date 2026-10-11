import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        _ = NativeMessaging.shared
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowBecameVisible(_:)),
            name: Notification.Name("NSWindowDidBecomeVisibleNotification"),
            object: nil
        )
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppWindowController.shared.suppressUnsolicitedWindows()
        DispatchQueue.main.async {
            AppWindowController.shared.suppressUnsolicitedWindows()
            AppWindowController.shared.attachDelegate()
            AppSession.shared.start()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            NativeMessaging.shared.handle(url: url)
        }
        // Background handoff: do not steal focus or open the queue.
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        false
    }

    func applicationShouldOpenUntitledFile(_ sender: NSApplication) -> Bool {
        false
    }

    @objc private func windowBecameVisible(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        Task { @MainActor in
            guard !AppWindowController.shared.userRequestedWindow else { return }
            guard AppWindowController.shared.isQueueWindow(window) else { return }
            window.orderOut(nil)
        }
    }
}
