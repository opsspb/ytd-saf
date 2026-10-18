import Foundation

/// Hidden debug aids for cookie-jar / format-picker investigations.
public enum CookieJarDebug {
    /// When true, the last per-download Netscape jar is copied into Application Support (mode 0600)
    /// instead of only deleting the temp file. Default off.
    public static let keepLastCookieJarKey = "YTDKeepLastCookieJar"

    public static func keepLastCookieJar(
        defaults: UserDefaults = .standard
    ) -> Bool {
        defaults.bool(forKey: keepLastCookieJarKey)
    }

    /// Copy `tempCookieURL` to `supportDirectory/last-cookie-jar.txt` (0600), then remove the temp file.
    /// When the flag is off, only deletes the temp file.
    public static func disposeTempCookieFile(
        _ tempCookieURL: URL,
        supportDirectory: URL,
        defaults: UserDefaults = .standard,
        fileManager: FileManager = .default
    ) {
        if keepLastCookieJar(defaults: defaults) {
            let dest = supportDirectory.appendingPathComponent("last-cookie-jar.txt")
            try? fileManager.createDirectory(at: supportDirectory, withIntermediateDirectories: true)
            try? fileManager.removeItem(at: dest)
            do {
                try fileManager.copyItem(at: tempCookieURL, to: dest)
                try fileManager.setAttributes(
                    [.posixPermissions: NSNumber(value: Int16(0o600))],
                    ofItemAtPath: dest.path
                )
            } catch {
                // Best-effort debug aid; still remove the temp file below.
            }
        }
        try? fileManager.removeItem(at: tempCookieURL)
    }
}
