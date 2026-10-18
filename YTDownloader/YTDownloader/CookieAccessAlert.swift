import AppKit
import YTDownloaderCore

/// Presents the macOS alert when sign-in cookies cannot be obtained.
enum CookieAccessAlert {
    @MainActor
    static func present(_ guidance: CookieFailureGuidance) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = guidance.alertTitle
        alert.informativeText = guidance.alertMessage
        if guidance.showsOpenSettings {
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "Cancel")
        } else {
            alert.addButton(withTitle: "OK")
        }

        let response = alert.runModal()
        if guidance.showsOpenSettings, response == .alertFirstButtonReturn {
            if let url = URL(string: CookieAccessDiagnoser.fullDiskAccessSettingsURL) {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
