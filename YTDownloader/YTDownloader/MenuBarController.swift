import AppKit
import SwiftUI
import ServiceManagement
import YTDownloaderCore

extension Notification.Name {
    static let ytdDownloadDidEnqueue = Notification.Name("ytdDownloadDidEnqueue")
}

@MainActor
final class AppSession {
    static let shared = AppSession()
    var downloadManager: DownloadManager?
    var binaryManager: BinaryManager?
    private var started = false

    func start() {
        guard !started else { return }
        guard let downloads = downloadManager, let binaries = binaryManager else { return }
        started = true
        StatusMenuActions.shared.install(downloadManager: downloads)
        Task {
            await binaries.setup()
            downloads.resumeQueue()
        }
    }
}

enum AppScenes {
    static let queueWindowID = "queue"
}

@MainActor
final class AppWindowController: NSObject, NSWindowDelegate {
    static let shared = AppWindowController()

    private(set) var userRequestedWindow = false
    var launchSuppressionDeadline = Date.distantPast
    var openQueueScene: (() -> Void)?

    private var registeredQueueWindow: NSWindow?
    private var fallbackWindow: NSWindow?
    private var fallbackSettingsWindow: NSWindow?

    func register(_ window: NSWindow) {
        guard !(window is NSPanel) else { return }
        guard !isSettingsWindow(window) else { return }
        if window.title.localizedCaseInsensitiveContains("Settings") { return }
        if let existing = registeredQueueWindow,
           existing !== window,
           existing.identifier?.rawValue == AppScenes.queueWindowID {
            return
        }
        registeredQueueWindow = window
        window.identifier = NSUserInterfaceItemIdentifier(AppScenes.queueWindowID)
        window.isReleasedWhenClosed = false
        window.delegate = self
    }

    func showQueue(activate: Bool) {
        userRequestedWindow = true
        openQueueScene?()

        if let window = resolvedQueueWindow(), !isSettingsWindow(window) {
            present(window, activate: activate)
            return
        }

        // SwiftUI may create the Window(id: "queue") scene on the next turn.
        presentQueueWhenReady(activate: activate, attemptsRemaining: 8)
    }

    func hideQueue() {
        userRequestedWindow = false
        queueWindows().forEach { $0.orderOut(nil) }
        fallbackWindow?.orderOut(nil)
    }

    func toggleQueue() {
        if let window = resolvedQueueWindow(), window.isVisible, userRequestedWindow {
            hideQueue()
        } else {
            showQueue(activate: true)
        }
    }

    func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        // Prefer a dedicated hosted Settings window. SwiftUI's Settings scene is
        // unreliable from an LSUIElement status menu on some SDKs.
        let window = ensureFallbackSettings()
        window.collectionBehavior.insert(.moveToActiveSpace)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()

        NSApp.sendAction(Selector(("showSettingsWindow:")), to: NSApp, from: nil)
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: NSApp, from: nil)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            for candidate in NSApp.windows where self.isSettingsWindow(candidate) {
                candidate.collectionBehavior.insert(.moveToActiveSpace)
                candidate.makeKeyAndOrderFront(nil)
                candidate.orderFrontRegardless()
            }
        }
    }

    func suppressUnsolicitedWindows() {
        guard !userRequestedWindow else { return }
        queueWindows().forEach { $0.orderOut(nil) }
        fallbackWindow?.orderOut(nil)
    }

    func shouldSuppressUnsolicited(_ window: NSWindow) -> Bool {
        guard !userRequestedWindow else { return false }
        guard Date() < launchSuppressionDeadline else { return false }
        return isQueueWindow(window)
    }

    func attachDelegate() {
        queueWindows().forEach { register($0) }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        if isQueueWindow(sender) {
            userRequestedWindow = false
        }
        return false
    }

    func isQueueWindow(_ window: NSWindow) -> Bool {
        guard !(window is NSPanel) else { return false }
        guard window.level == .normal else { return false }
        guard !isSettingsWindow(window) else { return false }
        if window === registeredQueueWindow || window === fallbackWindow { return true }
        if window.identifier?.rawValue == AppScenes.queueWindowID { return true }
        return window.title == "YTDownloader"
            && !window.title.localizedCaseInsensitiveContains("Settings")
    }

    func isSettingsWindow(_ window: NSWindow) -> Bool {
        if window === fallbackSettingsWindow { return true }
        if window.identifier?.rawValue == "settings" { return true }
        let title = window.title
        return title.localizedCaseInsensitiveContains("Settings")
            || title.localizedCaseInsensitiveContains("Preferences")
    }

    private func existingSettingsWindow() -> NSWindow? {
        NSApp.windows.first(where: { isSettingsWindow($0) }) ?? fallbackSettingsWindow
    }

    private func presentQueueWhenReady(activate: Bool, attemptsRemaining: Int) {
        if let window = resolvedQueueWindow(), !isSettingsWindow(window) {
            present(window, activate: activate)
            return
        }
        guard attemptsRemaining > 0 else {
            present(ensureFallbackWindow(), activate: activate)
            return
        }
        openQueueScene?()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
            self?.presentQueueWhenReady(activate: activate, attemptsRemaining: attemptsRemaining - 1)
        }
    }

    private func present(_ window: NSWindow, activate: Bool) {
        register(window)
        if activate {
            NSApp.activate(ignoringOtherApps: true)
            window.collectionBehavior.insert(.moveToActiveSpace)
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
        } else {
            window.orderFrontRegardless()
        }
    }

    private func resolvedQueueWindow() -> NSWindow? {
        let swiftWindows = queueWindows().filter { $0 !== fallbackWindow }
        if let first = swiftWindows.first {
            if fallbackWindow != nil, fallbackWindow !== first {
                fallbackWindow?.orderOut(nil)
            }
            return first
        }
        if let registered = registeredQueueWindow, registered !== fallbackWindow {
            return registered
        }
        return fallbackWindow
    }

    private func queueWindows() -> [NSWindow] {
        NSApp.windows.filter(isQueueWindow)
    }

    private func ensureFallbackWindow() -> NSWindow {
        if let fallbackWindow { return fallbackWindow }

        let window: NSWindow
        if let downloads = AppSession.shared.downloadManager,
           let binaries = AppSession.shared.binaryManager {
            let root = ContentView()
                .environmentObject(downloads)
                .environmentObject(binaries)
            let hosting = NSHostingController(rootView: root)
            window = NSWindow(contentViewController: hosting)
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 860, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
        }
        window.title = "YTDownloader"
        window.identifier = NSUserInterfaceItemIdentifier(AppScenes.queueWindowID)
        window.setContentSize(NSSize(width: 860, height: 560))
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        fallbackWindow = window
        registeredQueueWindow = window
        return window
    }

    private func ensureFallbackSettings() -> NSWindow {
        if let fallbackSettingsWindow { return fallbackSettingsWindow }
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.identifier = NSUserInterfaceItemIdentifier("settings")
        window.isReleasedWhenClosed = false
        window.delegate = self
        if let downloads = AppSession.shared.downloadManager {
            window.contentViewController = NSHostingController(
                rootView: SettingsView().environmentObject(downloads)
            )
        } else {
            window.contentViewController = NSHostingController(rootView: Text("Settings unavailable"))
        }
        window.setContentSize(NSSize(width: 520, height: 420))
        window.center()
        fallbackSettingsWindow = window
        return window
    }
}

/// Notification-driven helpers for the native status menu (MenuBarExtra).
@MainActor
final class StatusMenuActions {
    static let shared = StatusMenuActions()

    private weak var downloadManager: DownloadManager?

    func install(downloadManager: DownloadManager) {
        self.downloadManager = downloadManager
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(downloadDidEnqueue),
            name: .ytdDownloadDidEnqueue,
            object: nil
        )
    }

    @objc private func downloadDidEnqueue() {
        guard downloadManager?.settings.showWindowOnDownloadStart == true else { return }
        AppWindowController.shared.showQueue(activate: false)
    }

    static func confirmStopAll(_ downloadManager: DownloadManager?) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Stop all downloads?"
        alert.informativeText = "Cancels the active download, removes queued items, and deletes partial files."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Stop all")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            downloadManager?.stopAll()
        }
    }
}

/// Standard system status menu (LM Studio-style): MenuBarExtra(.menu) → plain NSMenu.
struct StatusMenuContent: View {
    @ObservedObject var downloadManager: DownloadManager
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        let model = StatusMenuModel.make(items: downloadManager.queue)

        // Plain Text → system menu label (disabled), not a custom row view.
        Text(model.statusLine)

        Button(StatusMenuSpec.showQueue) {
            bindOpenWindow()
            AppWindowController.shared.showQueue(activate: true)
        }

        Button(StatusMenuSpec.stopAll) {
            StatusMenuActions.confirmStopAll(downloadManager)
        }

        Divider()

        Button(StatusMenuSpec.settings) {
            AppWindowController.shared.showSettings()
        }
        .keyboardShortcut(",", modifiers: .command)

        Divider()

        Button(StatusMenuSpec.quit) {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q", modifiers: .command)
        .onAppear(perform: bindOpenWindow)
    }

    private func bindOpenWindow() {
        AppWindowController.shared.openQueueScene = {
            openWindow(id: AppScenes.queueWindowID)
        }
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    @discardableResult
    static func setEnabled(_ enabled: Bool) -> String? {
        do {
            if enabled {
                if SMAppService.mainApp.status == .enabled { return nil }
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
