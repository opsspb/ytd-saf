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

@MainActor
final class AppWindowController: NSObject, NSWindowDelegate {
    static let shared = AppWindowController()

    private(set) var userRequestedWindow = false

    func showQueue(activate: Bool) {
        userRequestedWindow = true
        guard let window = queueWindows().first else { return }
        window.delegate = self
        if activate {
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFrontRegardless()
        }
    }

    func hideQueue() {
        userRequestedWindow = false
        queueWindows().forEach { $0.orderOut(nil) }
    }

    func toggleQueue() {
        if let window = queueWindows().first, window.isVisible, userRequestedWindow {
            hideQueue()
        } else {
            showQueue(activate: true)
        }
    }

    func showSettings() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }

    func suppressUnsolicitedWindows() {
        guard !userRequestedWindow else { return }
        queueWindows().forEach { $0.orderOut(nil) }
    }

    func attachDelegate() {
        queueWindows().forEach { $0.delegate = self }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        userRequestedWindow = false
        return false
    }

    func isQueueWindow(_ window: NSWindow) -> Bool {
        window.canBecomeMain
            && !(window is NSPanel)
            && window.level == .normal
            && !window.title.localizedCaseInsensitiveContains("Settings")
            && !window.title.localizedCaseInsensitiveContains("Preferences")
    }

    private func queueWindows() -> [NSWindow] {
        NSApp.windows.filter(isQueueWindow)
    }
}

@MainActor
final class StatusItemController: NSObject {
    static let shared = StatusItemController()

    private var statusItem: NSStatusItem?
    private var menu: NSMenu?
    private weak var downloadManager: DownloadManager?

    func install(downloadManager: DownloadManager) {
        self.downloadManager = downloadManager
        if statusItem == nil {
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            if let button = item.button {
                button.image = Self.templateIcon()
                button.toolTip = "YTDownloader"
                button.target = self
                button.action = #selector(statusItemClicked(_:))
                button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            }
            statusItem = item
            menu = buildMenu()
        }
        NotificationCenter.default.removeObserver(self)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(downloadDidEnqueue),
            name: .ytdDownloadDidEnqueue,
            object: nil
        )
    }

    @objc private func statusItemClicked(_ sender: Any?) {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.option) == true {
            if let button = statusItem?.button, let menu {
                menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
            }
            return
        }
        AppWindowController.shared.toggleQueue()
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

    private func buildMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Queue", action: #selector(showQueue(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Stop all", action: #selector(stopAll(_:)), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit YTDownloader", action: #selector(quit(_:)), keyEquivalent: "q"))
        menu.items.forEach { $0.target = self }
        return menu
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
