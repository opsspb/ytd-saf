import SwiftUI
import YTDownloaderCore

struct ContentView: View {
    @EnvironmentObject var downloadManager: DownloadManager
    @EnvironmentObject var binaryManager: BinaryManager
    @State private var showOnboarding = false
    
    var body: some View {
        NavigationSplitView {
            VStack(alignment: .leading, spacing: 0) {
                if !binaryManager.isReady {
                    SetupView()
                } else if !hasExtensionEnabled() {
                    OnboardingView(showOnboarding: $showOnboarding)
                } else {
                    DownloadQueueView()
                }
            }
            .frame(minWidth: 300)
        } detail: {
            if let selectedItem = downloadManager.selectedItem {
                DownloadDetailView(item: selectedItem)
            } else {
                Text("Select a download to view details")
                    .foregroundColor(.secondary)
            }
        }
        .navigationTitle("YTDownloader")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showOnboarding = true
                } label: {
                    Image(systemName: "gearshape")
                }
            }
        }
        .sheet(isPresented: $showOnboarding) {
            SettingsView()
                .environmentObject(downloadManager)
        }
    }
    
    private func hasExtensionEnabled() -> Bool {
        true
    }
}

struct SetupView: View {
    @EnvironmentObject var binaryManager: BinaryManager
    
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 48))
                .foregroundColor(.blue)
            
            Text("Setting up YTDownloader")
                .font(.headline)
            
            Text(binaryManager.setupStatus)
                .font(.caption)
                .foregroundColor(.secondary)
            
            if binaryManager.setupProgress > 0 {
                ProgressView(value: binaryManager.setupProgress, total: 1.0)
                    .frame(width: 200)
            } else {
                ProgressView()
            }
        }
        .padding(40)
    }
}

struct OnboardingView: View {
    @Binding var showOnboarding: Bool
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "safari")
                .font(.system(size: 64))
                .foregroundColor(.blue)
            
            Text("Enable Safari Extension")
                .font(.title)
            
            VStack(alignment: .leading, spacing: 12) {
                InstructionRow(number: "1", text: "Open Safari Preferences")
                InstructionRow(number: "2", text: "Go to Extensions tab")
                InstructionRow(number: "3", text: "Enable YTDownloader")
                InstructionRow(number: "4", text: "Allow unsigned extensions (Developer menu)")
            }
            .padding()
            
            Button("Open Safari Preferences") {
                openSafariPreferences()
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(40)
    }
    
    private func openSafariPreferences() {
        let url = URL(string: "x-apple.systempreferences:com.apple.Safari-Settings.extension")!
        NSWorkspace.shared.open(url)
    }
}

struct InstructionRow: View {
    let number: String
    let text: String
    
    var body: some View {
        HStack(spacing: 12) {
            Text(number)
                .font(.headline)
                .foregroundColor(.white)
                .frame(width: 28, height: 28)
                .background(Color.blue)
                .clipShape(Circle())
            
            Text(text)
        }
    }
}

struct DownloadQueueView: View {
    @EnvironmentObject var downloadManager: DownloadManager
    
    var body: some View {
        List(selection: $downloadManager.selectedItem) {
            ForEach(downloadManager.queue) { item in
                DownloadItemRow(item: item)
                    .tag(item)
            }
        }
        .listStyle(.sidebar)
        .overlay {
            if downloadManager.queue.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 48))
                        .foregroundColor(.secondary)
                    Text("No downloads")
                        .foregroundColor(.secondary)
                    Text("Click the YD button on any YouTube video to start downloading")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                }
            }
        }
    }
}

struct DownloadItemRow: View {
    let item: DownloadItem
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title ?? item.videoId)
                    .lineLimit(1)
                
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            statusIcon
        }
        .padding(.vertical, 4)
    }
    
    private var statusText: String {
        switch item.status {
        case .queued:
            return "Queued"
        case .downloading:
            return String(format: "Downloading %.0f%%", item.progress * 100)
        case .merging:
            return "Merging..."
        case .completed:
            return "Completed"
        case .failed:
            return "Failed"
        }
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .queued:
            Image(systemName: "clock")
                .foregroundColor(.secondary)
        case .downloading, .merging:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
        }
    }
}

struct DownloadDetailView: View {
    let item: DownloadItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(item.title ?? item.videoId)
                .font(.title2)
            
            LabeledContent("Status", value: item.status.rawValue.capitalized)
            LabeledContent("Video ID", value: item.videoId)
            LabeledContent("URL", value: item.url)
            
            if item.status == .downloading || item.status == .merging {
                ProgressView(value: item.progress, total: 1.0)
                    .frame(maxWidth: 300)
            }
            
            if let error = item.error {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Error")
                        .font(.headline)
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
            
            if let outputPath = item.outputPath {
                Button("Show in Finder") {
                    showInFinder(path: outputPath)
                }
                .buttonStyle(.borderedProminent)
            }
            
            Spacer()
        }
        .padding()
    }
    
    private func showInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
