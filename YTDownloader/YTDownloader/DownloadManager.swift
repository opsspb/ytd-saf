import Foundation
import Combine
import YTDownloaderCore

@MainActor
class DownloadManager: ObservableObject {
    @Published var queue: [DownloadItem] = []
    @Published var selectedItemID: UUID?
    @Published var settings = DownloadSettings()

    private let formatSelector = FormatSelector()
    private let retryStrategy = RetryStrategy()

    private var activeDownloads = 0
    private var retryStates: [UUID: RetryState] = [:]
    private var lastProgressSave = Date.distantPast
    private let queueFile: URL

    var selectedItem: DownloadItem? {
        guard let selectedItemID else { return nil }
        return queue.first(where: { $0.id == selectedItemID })
    }

    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appFolder = appSupport.appendingPathComponent("YTDownloader")
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        queueFile = appFolder.appendingPathComponent("queue.json")
        loadSettings()
        loadQueue()
    }

    func addDownload(videoId: String, url: String) {
        if queue.contains(where: { $0.videoId == videoId && isActive($0.status) }) {
            return
        }

        if let index = queue.firstIndex(where: { $0.videoId == videoId && $0.status == .failed }) {
            var item = queue[index]
            item.status = .queued
            item.progress = 0
            item.error = nil
            item.completedAt = nil
            queue[index] = item
            saveQueue()
            processQueue()
            return
        }

        let item = DownloadItem(videoId: videoId, url: url)
        queue.append(item)
        saveQueue()
        processQueue()
    }

    func updateItemStatus(
        id: UUID,
        status: DownloadStatus,
        progress: Double? = nil,
        error: String? = nil,
        outputPath: String? = nil
    ) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }

        var item = queue[index]
        item.status = status
        if let progress {
            item.progress = progress
        }
        if let error {
            item.error = error
        }
        if let outputPath {
            item.outputPath = outputPath
        }

        if status == .completed || status == .failed {
            item.completedAt = Date()
        }

        queue[index] = item
        saveQueue()

        if status == .completed || status == .failed {
            activeDownloads = max(0, activeDownloads - 1)
            processQueue()
        }
    }

    func updateProgress(id: UUID, progress: Double) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        var item = queue[index]
        item.progress = min(max(progress, item.progress), 1)
        queue[index] = item
        if Date().timeIntervalSince(lastProgressSave) >= 0.4 {
            lastProgressSave = Date()
            saveQueue()
        }
    }

    private func isActive(_ status: DownloadStatus) -> Bool {
        status == .queued || status == .downloading || status == .merging
    }

    private func processQueue() {
        let maxConcurrent = settings.maxConcurrentDownloads
        guard activeDownloads < maxConcurrent else { return }
        guard let nextItem = queue.first(where: { $0.status == .queued }) else { return }

        activeDownloads += 1
        Task {
            await downloadItem(nextItem)
        }
    }

    private func downloadItem(_ item: DownloadItem) async {
        updateItemStatus(id: item.id, status: .downloading, progress: 0)

        do {
            let settings = self.settings
            let result = try await Task.detached(priority: .userInitiated) { [formatSelector] in
                guard let paths = BinaryBootstrap().locateExisting() else {
                    throw DownloadError.ytdlpNotFound
                }
                let pipeline = VideoDownloadPipeline(
                    ytdlpPath: paths.ytdlp,
                    ffmpegPath: paths.ffmpeg,
                    cookieMode: settings.cookieMode,
                    cookieFilePath: settings.cookieFilePath
                )
                let info = try pipeline.fetchInfo(url: item.url, useCookies: false)
                let formats = try formatSelector.selectBestFormats(from: info)
                return (pipeline, info, formats)
            }.value

            updateTitle(id: item.id, title: result.1.title)

            try await downloadAndMerge(
                item: item,
                info: result.1,
                formats: result.2,
                pipeline: result.0
            )
        } catch let error as DownloadError where error.requiresCookies {
            await retryWithCookies(item: item, error: error)
        } catch let error as DownloadError where error.isTransient {
            await retryIfPossible(item: item, error: error)
        } catch {
            let downloadError = error as? DownloadError ?? .unknown(error.localizedDescription)
            updateItemStatus(id: item.id, status: .failed, error: downloadError.errorDescription)
        }
    }

    private func retryWithCookies(item: DownloadItem, error: DownloadError) async {
        guard settings.cookieMode != .none else {
            updateItemStatus(id: item.id, status: .failed, error: error.errorDescription)
            return
        }

        do {
            let settings = self.settings
            let result = try await Task.detached(priority: .userInitiated) { [formatSelector] in
                guard let paths = BinaryBootstrap().locateExisting() else {
                    throw DownloadError.ytdlpNotFound
                }
                let pipeline = VideoDownloadPipeline(
                    ytdlpPath: paths.ytdlp,
                    ffmpegPath: paths.ffmpeg,
                    cookieMode: settings.cookieMode,
                    cookieFilePath: settings.cookieFilePath
                )
                let info = try pipeline.fetchInfo(url: item.url, useCookies: true)
                let formats = try formatSelector.selectBestFormats(from: info)
                return (pipeline, info, formats)
            }.value

            try await downloadAndMerge(
                item: item,
                info: result.1,
                formats: result.2,
                pipeline: result.0,
                useCookies: true
            )
        } catch {
            let downloadError = error as? DownloadError ?? .unknown(error.localizedDescription)
            updateItemStatus(id: item.id, status: .failed, error: downloadError.errorDescription)
        }
    }

    private func retryIfPossible(item: DownloadItem, error: DownloadError) async {
        var state = retryStates[item.id] ?? RetryState()
        state.recordAttempt(error: error)
        retryStates[item.id] = state

        guard retryStrategy.shouldRetry(error: error, attempt: state.attempt) else {
            updateItemStatus(id: item.id, status: .failed, error: error.errorDescription)
            return
        }

        let delay = retryStrategy.delay(forAttempt: state.attempt)
        try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
        await downloadItem(item)
    }

    private func updateTitle(id: UUID, title: String) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        var item = queue[index]
        item.title = title
        queue[index] = item
        saveQueue()
    }

    private func downloadAndMerge(
        item: DownloadItem,
        info: YTDLPInfo,
        formats: SelectedFormats,
        pipeline: VideoDownloadPipeline,
        useCookies: Bool = false
    ) async throws {
        let downloadDir = (settings.downloadDirectory as NSString).expandingTildeInPath
        let itemID = item.id
        let url = item.url
        let videoId = item.videoId

        try await Task.detached(priority: .userInitiated) { () async throws in
            try FileManager.default.createDirectory(atPath: downloadDir, withIntermediateDirectories: true)
            let outputFile = (downloadDir as NSString).appendingPathComponent(
                OutputFilename.make(title: info.title, videoId: videoId)
            )
            try pipeline.downloadMerged(
                url: url,
                videoFormatId: formats.video.formatId,
                audioFormatId: formats.audio.formatId,
                outputPath: outputFile,
                useCookies: useCookies,
                onProgress: { progress in
                    Task { @MainActor in
                        DownloadProgressBridge.shared.update(id: itemID, fraction: progress)
                    }
                },
                onMerging: {
                    Task { @MainActor in
                        DownloadProgressBridge.shared.merging(id: itemID)
                    }
                }
            )

            await MainActor.run {
                DownloadProgressBridge.shared.completed(id: itemID, path: outputFile)
            }
        }.value
    }

    func clearFinished() {
        let removedIDs = Set(queue.filter { $0.status == .completed || $0.status == .failed }.map(\.id))
        guard !removedIDs.isEmpty else { return }
        queue.removeAll { removedIDs.contains($0.id) }
        if let selectedItemID, removedIDs.contains(selectedItemID) {
            self.selectedItemID = nil
        }
        saveQueue()
    }

    var hasFinishedItems: Bool {
        queue.contains { $0.status == .completed || $0.status == .failed }
    }

    func attachProgressBridge() {
        DownloadProgressBridge.shared.handler = { [weak self] id, status, progress, path in
            guard let self else { return }
            if status == .completed {
                self.updateItemStatus(id: id, status: .completed, progress: 1, outputPath: path)
            } else if status == .merging {
                self.updateItemStatus(id: id, status: .merging, progress: progress)
            } else {
                self.updateProgress(id: id, progress: progress)
            }
        }
    }

    func resumeQueue() {
        processQueue()
    }

    private func loadSettings() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let settingsFile = appSupport.appendingPathComponent("YTDownloader/settings.json")
        guard let data = try? Data(contentsOf: settingsFile),
              let loaded = try? JSONDecoder().decode(DownloadSettings.self, from: data) else {
            return
        }
        settings = loaded
    }

    func saveSettings() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let settingsFile = appSupport.appendingPathComponent("YTDownloader/settings.json")
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: settingsFile)
    }

    private func loadQueue() {
        guard let data = try? Data(contentsOf: queueFile),
              let loaded = try? JSONDecoder().decode([DownloadItem].self, from: data) else {
            return
        }
        queue = loaded.map { item in
            guard item.status == .downloading || item.status == .merging else { return item }
            var copy = item
            copy.status = .queued
            copy.progress = 0
            copy.error = "Interrupted; retrying"
            return copy
        }
        saveQueue()
    }

    private func saveQueue() {
        guard let data = try? JSONEncoder().encode(queue) else { return }
        try? data.write(to: queueFile)
    }
}

/// Lets detached download work hop back to the live manager without capturing it.
@MainActor
final class DownloadProgressBridge {
    static let shared = DownloadProgressBridge()
    var handler: ((UUID, DownloadStatus, Double, String?) -> Void)?

    func update(id: UUID, fraction: Double) {
        handler?(id, .downloading, fraction, nil)
    }

    func merging(id: UUID) {
        handler?(id, .merging, 0.92, nil)
    }

    func completed(id: UUID, path: String) {
        handler?(id, .completed, 1, path)
    }
}
