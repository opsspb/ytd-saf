import Foundation
import YTDownloaderCore

@MainActor
class BinaryManager: ObservableObject {
    @Published var isReady = false
    @Published var setupStatus = "Checking binaries..."
    @Published var setupProgress: Double = 0
    @Published var setupError: String?

    private var paths: BinaryPaths?

    func setup() async {
        setupError = nil
        isReady = false
        setupStatus = "Checking binaries..."
        setupProgress = 0.05

        var bootstrap = BinaryBootstrap()
        bootstrap.onProgress = { status, progress in
            Task { @MainActor in
                self.setupStatus = status
                self.setupProgress = progress
            }
        }

        do {
            let result = try await bootstrap.setup()
            paths = result
            isReady = true
            setupError = nil
            setupStatus = result.source == .homebrew ? "Using Homebrew binaries" : "Ready"
            setupProgress = 1.0
        } catch {
            paths = nil
            isReady = false
            setupProgress = 0
            setupError = error.localizedDescription
            setupStatus = "Setup failed"
        }
    }

    func ytdlpPath() async -> String? {
        paths?.ytdlp ?? BinaryBootstrap().locateExisting()?.ytdlp
    }

    func ffmpegPath() async -> String? {
        paths?.ffmpeg ?? BinaryBootstrap().locateExisting()?.ffmpeg
    }

    func ffprobePath() async -> String? {
        paths?.ffprobe ?? BinaryBootstrap().locateExisting()?.ffprobe
    }
}
