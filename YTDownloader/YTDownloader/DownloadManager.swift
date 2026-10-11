import Foundation
import Combine
import YTDownloaderCore

@MainActor
class DownloadManager: ObservableObject {
    @Published var queue: [DownloadItem] = []
    @Published var selectedItem: DownloadItem?
    @Published var settings = DownloadSettings()
    
    private let formatSelector = FormatSelector()
    private let retryStrategy = RetryStrategy()
    
    private var activeDownloads = 0
    private var retryStates: [UUID: RetryState] = [:]
    
    private let queueFile: URL
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let appFolder = appSupport.appendingPathComponent("YTDownloader")
        try? FileManager.default.createDirectory(at: appFolder, withIntermediateDirectories: true)
        
        queueFile = appFolder.appendingPathComponent("queue.json")
        
        loadSettings()
        loadQueue()
    }
    
    func addDownload(videoId: String, url: String) {
        if queue.contains(where: { item in
            item.videoId == videoId && (item.status == .queued || item.status == .downloading || item.status == .merging)
        }) {
            return
        }

        let item = DownloadItem(videoId: videoId, url: url)
        queue.append(item)
        saveQueue()
        processQueue()
    }
    
    func updateItemStatus(id: UUID, status: DownloadStatus, progress: Double = 0, error: String? = nil, outputPath: String? = nil) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        
        var item = queue[index]
        item.status = status
        item.progress = progress
        item.error = error
        item.outputPath = outputPath
        
        if status == .completed || status == .failed {
            item.completedAt = Date()
        }
        
        queue[index] = item
        saveQueue()
        
        if status == .completed || status == .failed {
            activeDownloads -= 1
            processQueue()
        }
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
        updateItemStatus(id: item.id, status: .downloading)
        
        do {
            let pipeline = try makePipeline()
            let info = try pipeline.fetchInfo(url: item.url, useCookies: false)
            
            updateTitle(id: item.id, title: info.title)
            
            let formats = try formatSelector.selectBestFormats(from: info)
            
            try await downloadAndMerge(
                item: item,
                info: info,
                formats: formats,
                pipeline: pipeline
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
            let pipeline = try makePipeline()
            let info = try pipeline.fetchInfo(url: item.url, useCookies: true)
            let formats = try formatSelector.selectBestFormats(from: info)
            
            try await downloadAndMerge(
                item: item,
                info: info,
                formats: formats,
                pipeline: pipeline,
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
    
    private func makePipeline() throws -> VideoDownloadPipeline {
        guard let paths = BinaryBootstrap().locateExisting() else {
            throw DownloadError.ytdlpNotFound
        }
        return VideoDownloadPipeline(
            ytdlpPath: paths.ytdlp,
            ffmpegPath: paths.ffmpeg,
            cookieMode: settings.cookieMode,
            cookieFilePath: settings.cookieFilePath
        )
    }
    
    private func downloadAndMerge(
        item: DownloadItem,
        info: YTDLPInfo,
        formats: SelectedFormats,
        pipeline: VideoDownloadPipeline,
        useCookies: Bool = false
    ) async throws {
        let downloadDir = (settings.downloadDirectory as NSString).expandingTildeInPath
        try FileManager.default.createDirectory(atPath: downloadDir, withIntermediateDirectories: true)
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ytd-\(item.videoId)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let videoFile = tempDir.appendingPathComponent("video.\(formats.video.ext)").path
        let audioFile = tempDir.appendingPathComponent("audio.\(formats.audio.ext)").path
        
        try pipeline.downloadFormat(
            url: item.url,
            formatId: formats.video.formatId,
            outputPath: videoFile,
            useCookies: useCookies
        )
        
        try pipeline.downloadFormat(
            url: item.url,
            formatId: formats.audio.formatId,
            outputPath: audioFile,
            useCookies: useCookies
        )
        
        updateItemStatus(id: item.id, status: .merging)
        
        let sanitizedTitle = info.title.replacingOccurrences(of: "[^a-zA-Z0-9_\\-\\s]", with: "", options: .regularExpression)
        let outputFile = (downloadDir as NSString).appendingPathComponent("\(sanitizedTitle)_\(item.videoId).mkv")
        
        try pipeline.merge(videoPath: videoFile, audioPath: audioFile, outputPath: outputFile)
        
        updateItemStatus(id: item.id, status: .completed, progress: 1.0, outputPath: outputFile)
    }
    
    private func loadSettings() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let settingsFile = appSupport.appendingPathComponent("YTDownloader/settings.json")
        
        guard let data = try? Data(contentsOf: settingsFile) else { return }
        guard let loaded = try? JSONDecoder().decode(DownloadSettings.self, from: data) else { return }
        
        settings = loaded
    }
    
    func saveSettings() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let settingsFile = appSupport.appendingPathComponent("YTDownloader/settings.json")
        
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: settingsFile)
    }
    
    private func loadQueue() {
        guard let data = try? Data(contentsOf: queueFile) else { return }
        guard let loaded = try? JSONDecoder().decode([DownloadItem].self, from: data) else { return }
        
        queue = loaded
    }
    
    private func saveQueue() {
        guard let data = try? JSONEncoder().encode(queue) else { return }
        try? data.write(to: queueFile)
    }
}
