import SwiftUI
import YTDownloaderCore

struct SettingsView: View {
    @EnvironmentObject var downloadManager: DownloadManager
    @State private var downloadDirectory: String = ""
    @State private var cookieMode: CookieMode = .none
    @State private var cookieFilePath: String = ""
    @State private var maxConcurrentDownloads: Int = 1
    @State private var showWindowOnDownloadStart = false
    @State private var launchAtLogin = false
    @State private var launchAtLoginError: String?

    var body: some View {
        Form {
            Section("Download Location") {
                HStack {
                    TextField("Download Directory", text: $downloadDirectory)
                    Button("Browse...") {
                        selectDownloadDirectory()
                    }
                }
            }
            
            Section("Cookies") {
                Text("Primary: click YD in Safari — allow host access when prompted; cookies are handed off via the extension. Fallback modes below use the app process.")
                    .font(.caption)
                    .foregroundColor(.secondary)

                Picker("Cookie Mode", selection: $cookieMode) {
                    Text("None").tag(CookieMode.none)
                    Text("Safari (requires Full Disk Access)").tag(CookieMode.safari)
                    Text("Cookies File").tag(CookieMode.file)
                }
                .pickerStyle(.segmented)
                
                if cookieMode == .safari {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Fallback only — Safari’s cookie DB needs Full Disk Access:")
                            .font(.caption)
                        Text("1. Open System Settings → Privacy & Security")
                            .font(.caption)
                        Text("2. Go to Full Disk Access")
                            .font(.caption)
                        Text("3. Enable YTDownloader, then restart the app")
                            .font(.caption)
                        
                        Button("Open Privacy Settings") {
                            openPrivacySettings()
                        }
                        .buttonStyle(.link)
                    }
                    .padding(.top, 4)
                }
                
                if cookieMode == .file {
                    HStack {
                        TextField("Cookies File Path", text: $cookieFilePath)
                        Button("Browse...") {
                            selectCookieFile()
                        }
                    }
                }
            }
            
            Section("Performance") {
                Stepper("Concurrent Downloads: \(maxConcurrentDownloads)", value: $maxConcurrentDownloads, in: 1...5)
            }

            Section("Menu Bar") {
                Toggle("Show window when a download starts", isOn: $showWindowOnDownloadStart)
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { enabled in
                        launchAtLoginError = LaunchAtLogin.setEnabled(enabled)
                        launchAtLogin = LaunchAtLogin.isEnabled
                    }
                if let launchAtLoginError {
                    Text(launchAtLoginError)
                        .font(.caption)
                        .foregroundColor(.red)
                }
                Text("The queue stays hidden until you click the YD menu-bar icon, unless the toggle above is on.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Section {
                Button("Save Settings") {
                    saveSettings()
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .formStyle(.grouped)
        .frame(width: 500, height: 520)
        .onAppear {
            loadSettings()
        }
    }
    
    private func loadSettings() {
        downloadDirectory = downloadManager.settings.downloadDirectory
        cookieMode = downloadManager.settings.cookieMode
        cookieFilePath = downloadManager.settings.cookieFilePath ?? ""
        maxConcurrentDownloads = downloadManager.settings.maxConcurrentDownloads
        showWindowOnDownloadStart = downloadManager.settings.showWindowOnDownloadStart
        launchAtLogin = LaunchAtLogin.isEnabled
    }
    
    private func saveSettings() {
        downloadManager.settings.downloadDirectory = downloadDirectory
        downloadManager.settings.cookieMode = cookieMode
        downloadManager.settings.cookieFilePath = cookieFilePath.isEmpty ? nil : cookieFilePath
        downloadManager.settings.maxConcurrentDownloads = maxConcurrentDownloads
        downloadManager.settings.showWindowOnDownloadStart = showWindowOnDownloadStart
        downloadManager.settings.launchAtLogin = LaunchAtLogin.isEnabled

        downloadManager.saveSettings()
    }
    
    private func selectDownloadDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        
        if panel.runModal() == .OK, let url = panel.url {
            downloadDirectory = url.path
        }
    }
    
    private func selectCookieFile() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.text]
        
        if panel.runModal() == .OK, let url = panel.url {
            cookieFilePath = url.path
        }
    }
    
    private func openPrivacySettings() {
        let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")!
        NSWorkspace.shared.open(url)
    }
}
