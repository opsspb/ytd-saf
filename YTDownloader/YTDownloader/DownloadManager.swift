import Foundation
import Combine
import YTDownloaderCore

@MainActor
class DownloadManager: ObservableObject {
    @Published var queue: [DownloadItem] = []
    @Published var selectedItem: DownloadItem?
    @Published var settings = DownloadSettings()
    
    private let binaryManager = BinaryManager()
    private let formatSelector = FormatSelector()
    private let retryStrategy = RetryStrategy()
    private let errorClassifier = ErrorClassifier()
    
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
            let ytdlpPath = await binaryManager.ytdlpPath()
            let ffmpegPath = await binaryManager.ffmpegPath()
            
            guard let ytdlp = ytdlpPath, let ffmpeg = ffmpegPath else {
                throw DownloadError.ytdlpNotFound
            }
            
            let info = try await fetchVideoInfo(url: item.url, ytdlpPath: ytdlp, useCookies: false)
            
            updateTitle(id: item.id, title: info.title)
            
            let formats = try formatSelector.selectBestFormats(from: info)
            
            try await downloadAndMerge(
                item: item,
                info: info,
                formats: formats,
                ytdlpPath: ytdlp,
                ffmpegPath: ffmpeg
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
            let ytdlpPath = await binaryManager.ytdlpPath()
            let ffmpegPath = await binaryManager.ffmpegPath()
            
            guard let ytdlp = ytdlpPath, let ffmpeg = ffmpegPath else {
                throw DownloadError.ytdlpNotFound
            }
            
            let info = try await fetchVideoInfo(url: item.url, ytdlpPath: ytdlp, useCookies: true)
            let formats = try formatSelector.selectBestFormats(from: info)
            
            try await downloadAndMerge(
                item: item,
                info: info,
                formats: formats,
                ytdlpPath: ytdlp,
                ffmpegPath: ffmpeg,
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
    
    private func fetchVideoInfo(url: String, ytdlpPath: String, useCookies: Bool) async throws -> YTDLPInfo {
        var args = ["-J", "--no-warnings", url]
        
        if useCookies {
            switch settings.cookieMode {
            case .safari:
                args.append(contentsOf: ["--cookies-from-browser", "safari"])
            case .file:
                if let cookiePath = settings.cookieFilePath {
                    args.append(contentsOf: ["--cookies", cookiePath])
                }
            case .none:
                break
            }
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlpPath)
        process.arguments = args
        
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            throw errorClassifier.classifyError(from: errorOutput)
        }
        
        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        
        let decoder = JSONDecoder()
        return try decoder.decode(YTDLPInfo.self, from: outputData)
    }
    
    private func downloadAndMerge(
        item: DownloadItem,
        info: YTDLPInfo,
        formats: SelectedFormats,
        ytdlpPath: String,
        ffmpegPath: String,
        useCookies: Bool = false
    ) async throws {
        let downloadDir = (settings.downloadDirectory as NSString).expandingTildeInPath
        let tempDir = FileManager.default.temporaryDirectory
        
        let videoFile = tempDir.appendingPathComponent("\(item.videoId)_video.\(formats.video.ext)")
        let audioFile = tempDir.appendingPathComponent("\(item.videoId)_audio.\(formats.audio.ext)")
        
        try await downloadFormat(
            url: item.url,
            formatId: formats.video.formatId,
            outputPath: videoFile.path,
            ytdlpPath: ytdlpPath,
            useCookies: useCookies,
            itemId: item.id
        )
        
        try await downloadFormat(
            url: item.url,
            formatId: formats.audio.formatId,
            outputPath: audioFile.path,
            ytdlpPath: ytdlpPath,
            useCookies: useCookies,
            itemId: item.id
        )
        
        updateItemStatus(id: item.id, status: .merging)
        
        let sanitizedTitle = info.title.replacingOccurrences(of: "[^a-zA-Z0-9_\\-\\s]", with: "", options: .regularExpression)
        let outputFile = "\(downloadDir)/\(sanitizedTitle)_\(item.videoId).mkv"
        
        try await mergeFiles(
            videoPath: videoFile.path,
            audioPath: audioFile.path,
            outputPath: outputFile,
            ffmpegPath: ffmpegPath
        )
        
        try? FileManager.default.removeItem(at: videoFile)
        try? FileManager.default.removeItem(at: audioFile)
        
        updateItemStatus(id: item.id, status: .completed, progress: 1.0, outputPath: outputFile)
    }
    
    private func downloadFormat(
        url: String,
        formatId: String,
        outputPath: String,
        ytdlpPath: String,
        useCookies: Bool,
        itemId: UUID
    ) async throws {
        var args = ["-f", formatId, "-o", outputPath, "--no-warnings", url]
        
        if useCookies {
            switch settings.cookieMode {
            case .safari:
                args.append(contentsOf: ["--cookies-from-browser", "safari"])
            case .file:
                if let cookiePath = settings.cookieFilePath {
                    args.append(contentsOf: ["--cookies", cookiePath])
                }
            case .none:
                break
            }
        }
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ytdlpPath)
        process.arguments = args
        
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            throw errorClassifier.classifyError(from: errorOutput)
        }
    }
    
    private func mergeFiles(
        videoPath: String,
        audioPath: String,
        outputPath: String,
        ffmpegPath: String
    ) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffmpegPath)
        process.arguments = [
            "-i", videoPath,
            "-i", audioPath,
            "-c", "copy",
            "-y",
            outputPath
        ]
        
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        try process.run()
        process.waitUntilExit()
        
        if process.terminationStatus != 0 {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorOutput = String(data: errorData, encoding: .utf8) ?? ""
            throw DownloadError.mergeFailed(errorOutput)
        }
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
