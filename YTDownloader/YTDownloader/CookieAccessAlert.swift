import AppKit
import YTDownloaderCore

/// Presents a native macOS alert when sign-in cookies cannot be obtained.
enum CookieAccessAlert {
    @MainActor
    static func present(_ guidance: CookieFailureGuidance) {
        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = guidance.alertTitle
        alert.informativeText = guidance.alertMessage

        if let primary = guidance.primaryButtonTitle {
            alert.addButton(withTitle: primary)
            alert.addButton(withTitle: "Cancel")
        } else {
            alert.addButton(withTitle: "OK")
        }

        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }

        switch guidance.primaryAction {
        case .openFullDiskAccessSettings:
            openURL(CookieAccessDiagnoser.fullDiskAccessSettingsURL)
        case .openSafariExtensionSettings:
            if !openURL(CookieAccessDiagnoser.safariExtensionSettingsURL) {
                // Older macOS: open Safari; user can open Settings → Extensions.
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Safari.app"))
            }
        case .none:
            break
        }
    }

    @discardableResult
    private static func openURL(_ string: String) -> Bool {
        guard let url = URL(string: string) else { return false }
        return NSWorkspace.shared.open(url)
    }
}
