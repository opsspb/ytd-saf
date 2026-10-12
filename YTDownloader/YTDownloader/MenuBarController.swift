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
        StatusItemController.shared.install(downloadManager: downloads)
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
        if let window = resolvedQueueWindow(), !isSettingsWindow(window) {
            present(window, activate: activate)
            return
        }

        openQueueScene?()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let window = self.resolvedQueueWindow() {
                self.present(window, activate: activate)
                return
            }
            self.present(self.ensureFallbackWindow(), activate: activate)
        }
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
        if let window = existingSettingsWindow() {
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
            return
        }
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: NSApp, from: nil)
        NSApp.sendAction(Selector(("showPreferencesWindow:")), to: NSApp, from: nil)
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if let window = self.existingSettingsWindow() {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self else { return }
            let window = self.existingSettingsWindow() ?? self.ensureFallbackSettings()
            window.makeKeyAndOrderFront(nil)
            window.orderFrontRegardless()
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
        return window.title == "YTDownloader" && !window.title.localizedCaseInsensitiveContains("Settings")
    }

    func isSettingsWindow(_ window: NSWindow) -> Bool {
        if window === fallbackSettingsWindow { return true }
        if window.identifier?.rawValue == "settings" { return true }
        let title = window.title
        return title.localizedCaseInsensitiveContains("Settings")
            || title.localizedCaseInsensitiveContains("Preferences")
    }

    private func existingSettingsWindow() -> NSWindow? {
        if let fallbackSettingsWindow, fallbackSettingsWindow.isVisible {
            return fallbackSettingsWindow
        }
        let extras = NSApp.windows.filter { window in
            guard window !== registeredQueueWindow else { return false }
            guard window !== fallbackWindow else { return false }
            guard window.identifier?.rawValue != AppScenes.queueWindowID else { return false }
            if isSettingsWindow(window) { return true }
            let style = window.styleMask
            return style.contains(.titled)
                && window.level == .normal
                && window.frame.width < 700
        }
        return extras.first ?? fallbackSettingsWindow
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
        let window: NSWindow
        if let downloads = AppSession.shared.downloadManager {
            let hosting = NSHostingController(
                rootView: SettingsView().environmentObject(downloads)
            )
            window = NSWindow(contentViewController: hosting)
        } else {
            window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                styleMask: [.titled, .closable, .resizable],
                backing: .buffered,
                defer: false
            )
        }
        window.title = "Settings"
        window.identifier = NSUserInterfaceItemIdentifier("settings")
        window.setContentSize(NSSize(width: 520, height: 420))
        window.styleMask = [.titled, .closable, .resizable]
        window.isReleasedWhenClosed = false
        window.center()
        window.delegate = self
        fallbackSettingsWindow = window
        return window
    }
}

/// Standard `NSMenu` on `NSStatusItem` so left- and right-click both open the
/// system status menu (LM Studio). No custom row views, no `popUp`.
@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private let menu = NSMenu()
    private weak var downloadManager: DownloadManager?

    func install(downloadManager: DownloadManager) {
        self.downloadManager = downloadManager
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                button.image = Self.templateIcon()
                button.toolTip = "YTDownloader"
            }
            menu.delegate = self
            item.menu = menu
            statusItem = item
        }
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(downloadDidEnqueue),
            name: .ytdDownloadDidEnqueue,
            object: nil
        )
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        rebuildMenu(menu)
    }

    @objc private func downloadDidEnqueue() {
        guard downloadManager?.settings.showWindowOnDownloadStart == true else { return }
        AppWindowController.shared.showQueue(activate: false)
    }

    @objc private func showQueue(_ sender: Any?) {
        AppWindowController.shared.showQueue(activate: true)
    }

    @objc private func showSettings(_ sender: Any?) {
        AppWindowController.shared.showSettings()
    }

    @objc private func stopAll(_ sender: Any?) {
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

    @objc private func quit(_ sender: Any?) {
        NSApp.terminate(nil)
    }

    private func rebuildMenu(_ menu: NSMenu) {
        menu.removeAllItems()

        let model = StatusMenuModel.make(items: downloadManager?.queue ?? [])
        let status = NSMenuItem(title: model.statusLine, action: nil, keyEquivalent: "")
        status.isEnabled = false
        menu.addItem(status)

        let show = NSMenuItem(
            title: StatusMenuSpec.showQueue,
            action: #selector(showQueue(_:)),
            keyEquivalent: ""
        )
        show.target = self
        menu.addItem(show)

        let stop = NSMenuItem(
            title: StatusMenuSpec.stopAll,
            action: #selector(stopAll(_:)),
            keyEquivalent: ""
        )
        stop.target = self
        menu.addItem(stop)

        menu.addItem(.separator())

        let settings = NSMenuItem(
            title: StatusMenuSpec.settings,
            action: #selector(showSettings(_:)),
            keyEquivalent: ","
        )
        settings.target = self
        settings.keyEquivalentModifierMask = [.command]
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(
            title: StatusMenuSpec.quit,
            action: #selector(quit(_:)),
            keyEquivalent: "q"
        )
        quit.target = self
        menu.addItem(quit)
    }

    static func templateIcon() -> NSImage {
        let size = NSSize(width: 18, height: 18)
        let image = NSImage(size: size, flipped: false) { rect in
            let text = "YD" as NSString
            let attrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .bold),
                .foregroundColor: NSColor.black
            ]
            let textSize = text.size(withAttributes: attrs)
            let origin = NSPoint(
                x: ((rect.width - textSize.width) / 2).rounded(.toNearestOrAwayFromZero),
                y: ((rect.height - textSize.height) / 2).rounded(.toNearestOrAwayFromZero)
            )
            text.draw(at: origin, withAttributes: attrs)
            return true
        }
        image.isTemplate = true
        return image
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
