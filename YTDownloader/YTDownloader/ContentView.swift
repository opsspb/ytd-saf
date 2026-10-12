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
                    .id(selectedItem.id)
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
            
            if let error = binaryManager.setupError {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 360)
                Button("Retry Setup") {
                    Task { await binaryManager.setup() }
                }
                .buttonStyle(.borderedProminent)
            } else if binaryManager.setupProgress > 0 {
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
    @State private var confirmStopAll = false
    
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                if downloadManager.queue.contains(where: { $0.status != .completed }) {
                    Button("Stop all") {
                        confirmStopAll = true
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                    .foregroundColor(.red)
                }
                Spacer()
                if downloadManager.hasFinishedItems {
                    Button("Clear finished/failed") {
                        downloadManager.clearFinished()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .confirmationDialog("Stop all downloads?", isPresented: $confirmStopAll, titleVisibility: .visible) {
                Button("Stop all", role: .destructive) {
                    downloadManager.stopAll()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Cancels the active download, removes queued items, and deletes partial files.")
            }
            List(selection: $downloadManager.selectedItemID) {
                ForEach(downloadManager.queue) { item in
                    DownloadItemRow(item: item)
                        .tag(item.id)
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
}

struct DownloadItemRow: View {
    @EnvironmentObject var downloadManager: DownloadManager
    let item: DownloadItem
    
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.displayTitle)
                    .lineLimit(1)
                
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            
            Spacer()
            
            if item.status != .completed {
                Button {
                    downloadManager.cancelItem(id: item.id)
                } label: {
                    Image(systemName: "xmark.circle")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.borderless)
                .help("Cancel")
            }
            statusIcon
        }
        .padding(.vertical, 4)
    }
    
    private var statusText: String {
        item.listStatusText
    }
    
    @ViewBuilder
    private var statusIcon: some View {
        switch item.status {
        case .queued, .retrying:
            Image(systemName: "clock")
                .foregroundColor(.secondary)
        case .downloading, .merging:
            ProgressView()
                .controlSize(.small)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .cancelled:
            Image(systemName: "stop.circle")
                .foregroundColor(.secondary)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
        }
    }
}

struct DownloadDetailView: View {
    @EnvironmentObject var downloadManager: DownloadManager
    let item: DownloadItem
    
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(item.displayTitle)
                .font(.title2)
            
            LabeledContent("Status", value: item.listStatusText)
            if let formatSummary = item.formatSummary, !formatSummary.isEmpty {
                LabeledContent("Format", value: formatSummary)
            }
            LabeledContent("Video ID", value: item.videoId)
            LabeledContent("URL", value: item.url)

            VStack(alignment: .leading, spacing: 4) {
                Text("Stages")
                    .font(.caption)
                    .foregroundColor(.secondary)
                ForEach(item.stageSteps, id: \.self) { step in
                    Text(step)
                        .font(.caption)
                        .foregroundColor(step.hasPrefix("→") ? .primary : .secondary)
                }
            }

            if item.status != .completed {
                Button("Cancel this download", role: .destructive) {
                    downloadManager.cancelItem(id: item.id)
                }
            }
            
            if item.status == .downloading || item.status == .merging {
                ProgressView(value: item.progress, total: 1.0)
                    .frame(maxWidth: 300)
            }

            if item.status == .retrying, let retryNote = item.retryNote, !retryNote.isEmpty {
                Text(retryNote)
                    .foregroundColor(.secondary)
            }
            
            if item.showsFailureUI, let error = item.error {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Error")
                        .font(.headline)
                    Text(DownloadError.shortDisplayLine(from: error))
                        .foregroundColor(.red)
                    if DownloadError.hasTechnicalDetails(error) || !(item.log ?? "").isEmpty {
                        DisclosureGroup("Technical details") {
                            Text(technicalDetails(error: error, log: item.log))
                                .font(.system(.caption, design: .monospaced))
                                .foregroundColor(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            } else if let log = item.log, !log.isEmpty {
                DisclosureGroup("Technical details") {
                    Text(log)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundColor(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
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
    
    private func technicalDetails(error: String, log: String?) -> String {
        if let log, !log.isEmpty, log != error {
            return log + "\n" + error
        }
        return error
    }

    private func showInFinder(path: String) {
        let url = URL(fileURLWithPath: path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
