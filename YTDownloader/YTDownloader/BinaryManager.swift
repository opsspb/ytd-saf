import Foundation
import YTDownloaderCore

@MainActor
class BinaryManager: ObservableObject {
    @Published var isReady = false
    @Published var setupStatus = "Checking binaries..."
    @Published var setupProgress: Double = 0
    @Published var setupError: String?

    private var paths: BinaryPaths?
    private var inFlight: Task<Void, Never>?

    func setup() async {
        if isReady, setupError == nil { return }
        if let inFlight {
            await inFlight.value
            return
        }

        let task = Task { await self.performSetup() }
        inFlight = task
        await task.value
        inFlight = nil
    }

    private func performSetup() async {
        setupError = nil
        isReady = false
        setupStatus = "Checking binaries..."
        setupProgress = 0.05

        do {
            let result = try await Task.detached(priority: .userInitiated) {
                try await BinaryBootstrap().setup()
            }.value

            paths = result
            isReady = true
            setupError = nil
            setupStatus = "Ready"
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
