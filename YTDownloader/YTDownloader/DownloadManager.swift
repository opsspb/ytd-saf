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
    private var cancellations: [UUID: ProcessCancellation] = [:]
    /// In-memory only — never persist or log cookie values.
    private var extensionCookiePayloads: [UUID: String] = [:]
    private let supportDirectory: URL
    private let queueFile: URL
    private let settingsFile: URL
    private static let fixtureVideoIDs: Set<String> = [
        "clickIsoVid", "lockupVid12", "modernWatch1"
    ]

    var selectedItem: DownloadItem? {
        guard let selectedItemID else { return nil }
        return queue.first(where: { $0.id == selectedItemID })
    }

    var menuBarStatusLine: String {
        MenuBarStatus.line(items: queue)
    }

    init(supportDirectory: URL? = nil) {
        let root = supportDirectory ?? AppSupport.directory()
        self.supportDirectory = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        queueFile = AppSupport.queueFile(in: root)
        settingsFile = AppSupport.settingsFile(in: root)
        loadSettings()
        loadQueue()
    }

    func addDownload(videoId: String, url: String, cookiesPayload: String? = nil) {
        if Self.fixtureVideoIDs.contains(videoId) { return }
        var resolvedId = videoId
        var resolvedURL = url
        if let ref = SiteURL.resolve(url) {
            if !ref.isDownloadable {
                let failed = DownloadItem(
                    videoId: videoId.isEmpty ? (ref.id.isEmpty ? url : ref.id) : videoId,
                    url: url,
                    status: .failed,
                    error: DownloadError.unsupportedMedia.errorDescription
                )
                if !queue.contains(where: { $0.videoId == failed.videoId && $0.status == .failed }) {
                    queue.append(failed)
                    saveQueue()
                }
                return
            }
            if ref.site == .vk {
                resolvedId = ref.id
                resolvedURL = ref.url
            }
        }

        if let existing = queue.first(where: { $0.videoId == resolvedId && isActive($0.status) }) {
            // Attach cookies to an in-flight item if a later handoff includes them.
            if let cookiesPayload, !cookiesPayload.isEmpty {
                extensionCookiePayloads[existing.id] = cookiesPayload
            }
            return
        }

        if let index = queue.firstIndex(where: { $0.videoId == resolvedId && $0.status == .failed }) {
            var item = queue[index]
            item.status = .queued
            item.progress = 0
            item.error = nil
            item.completedAt = nil
            queue[index] = item
            if let cookiesPayload, !cookiesPayload.isEmpty {
                extensionCookiePayloads[item.id] = cookiesPayload
            }
            saveQueue()
            processQueue()
            NotificationCenter.default.post(name: .ytdDownloadDidEnqueue, object: nil)
            return
        }

        let item = DownloadItem(
            videoId: resolvedId,
            url: resolvedURL,
            title: nil,
            stage: .fetching
        )
        if let cookiesPayload, !cookiesPayload.isEmpty {
            extensionCookiePayloads[item.id] = cookiesPayload
        }
        queue.append(item)
        saveQueue()
        processQueue()
        NotificationCenter.default.post(name: .ytdDownloadDidEnqueue, object: nil)
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
        item.applyStatus(status, progress: progress, error: error, outputPath: outputPath)
        queue[index] = item
        saveQueue()

        if status == .completed || status == .failed || status == .cancelled {
            activeDownloads = max(0, activeDownloads - 1)
            cancellations[id] = nil
            extensionCookiePayloads[id] = nil
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
        status == .queued || status == .retrying || status == .downloading || status == .merging
    }

    func cancelItem(id: UUID) {
        cancellations[id]?.cancel()
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        var item = queue[index]
        if item.status == .completed { return }
        let wasRunning = isActive(item.status)
        item.applyStatus(.cancelled, progress: item.progress)
        item.stage = .cancelled
        queue[index] = item
        if wasRunning {
            activeDownloads = max(0, activeDownloads - 1)
        }
        cancellations[id] = nil
        extensionCookiePayloads[id] = nil
        saveQueue()
        processQueue()
    }

    func stopAll() {
        let ids = queue.map(\.id)
        for id in ids {
            cancellations[id]?.cancel()
        }
        cancellations.removeAll()
        extensionCookiePayloads.removeAll()
        let kept = queue.filter { $0.status == .completed }
        queue = kept
        if let selectedItemID, kept.contains(where: { $0.id == selectedItemID }) == false {
            self.selectedItemID = nil
        }
        activeDownloads = 0
        retryStates.removeAll()
        saveQueue()
        cleanPartialWorkDirs()
    }

    private func cleanPartialWorkDirs() {
        let tmp = FileManager.default.temporaryDirectory
        guard let items = try? FileManager.default.contentsOfDirectory(at: tmp, includingPropertiesForKeys: nil) else {
            return
        }
        for item in items where item.lastPathComponent.hasPrefix("ytd-sort-") || item.lastPathComponent.hasPrefix("ytd-merge-") {
            try? FileManager.default.removeItem(at: item)
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
        let token = ProcessCancellation()
        cancellations[item.id] = token
        applyStage(id: item.id, status: .downloading, stage: .fetching, progress: 0)

        do {
            try await runDownload(item, useCookies: false, cancellation: token)
        } catch DownloadError.cancelled {
            updateItemStatus(id: item.id, status: .cancelled)
        } catch let error as DownloadError where error.requiresCookies {
            await retryWithCookies(item: item, error: error)
        } catch let error as DownloadError where error.isTransient {
            await retryIfPossible(item: item, error: error)
        } catch {
            let downloadError = error as? DownloadError ?? .unknown(error.localizedDescription)
            updateItemStatus(id: item.id, status: .failed, error: downloadError.errorDescription)
        }
    }

    private func runDownload(
        _ item: DownloadItem,
        useCookies: Bool,
        cookieMode: CookieMode? = nil,
        cookieFilePath: String? = nil,
        cancellation: ProcessCancellation? = nil
    ) async throws {
        let mode = cookieMode ?? settings.cookieMode
        let path = cookieFilePath ?? settings.cookieFilePath
        let adapter = SiteAdapterRegistry.adapter(for: item.url)
        if adapter.formatSpec != nil {
            try await downloadBySort(
                item,
                adapter: adapter,
                useCookies: useCookies,
                cookieMode: mode,
                cookieFilePath: path,
                cancellation: cancellation
            )
            return
        }
        try await downloadYouTube(
            item,
            useCookies: useCookies,
            cookieMode: mode,
            cookieFilePath: path
        )
    }

    private func downloadYouTube(
        _ item: DownloadItem,
        useCookies: Bool,
        cookieMode: CookieMode,
        cookieFilePath: String?
    ) async throws {
        let result = try await Task.detached(priority: .userInitiated) { [formatSelector] in
            guard let paths = BinaryBootstrap().locateExisting() else {
                throw DownloadError.ytdlpNotFound
            }
            let pipeline = VideoDownloadPipeline(
                ytdlpPath: paths.ytdlp,
                ffmpegPath: paths.ffmpeg,
                cookieMode: cookieMode,
                cookieFilePath: cookieFilePath
            )
            let info = try pipeline.fetchInfo(url: item.url, useCookies: useCookies)
            let formats = try formatSelector.selectBestFormats(from: info)
            let fallbackIds = formatSelector.sameResolutionRung(as: formats.video, from: info)
                .map(\.formatId)
                .filter { $0 != formats.video.formatId }
            return (pipeline, info, formats, fallbackIds)
        }.value

        let info = result.1
        let formats = result.2
        updateTitle(id: item.id, title: info.title)
        applyStage(
            id: item.id,
            status: .downloading,
            stage: .formatChosen,
            title: info.title,
            formatSummary: formats.formatSummary
        )

        try await downloadAndMerge(
            item: item,
            info: info,
            formats: formats,
            pipeline: result.0,
            useCookies: useCookies,
            fallbackVideoFormatIds: result.3
        )
    }

    /// Re-extracts on every attempt: VK CDN URLs are IP-bound and expire.
    private func downloadBySort(
        _ item: DownloadItem,
        adapter: SiteAdapterInfo,
        useCookies: Bool,
        cookieMode: CookieMode,
        cookieFilePath: String?,
        cancellation: ProcessCancellation?
    ) async throws {
        let downloadDir = (settings.downloadDirectory as NSString).expandingTildeInPath
        let itemID = item.id
        let url = item.url

        let result = try await Task.detached(priority: .userInitiated) { () async throws -> DownloadPipelineResult in
            guard let paths = BinaryBootstrap().locateExisting() else {
                throw DownloadError.ytdlpNotFound
            }
            let pipeline = VideoDownloadPipeline(
                ytdlpPath: paths.ytdlp,
                ffmpegPath: paths.ffmpeg,
                cookieMode: cookieMode,
                cookieFilePath: cookieFilePath,
                aria2cPath: paths.aria2c
            )
            return try pipeline.downloadBySort(
                url: url,
                outputDirectory: downloadDir,
                adapter: adapter,
                useCookies: useCookies,
                includeFormatList: false,
                cancellation: cancellation,
                onProgress: { progress in
                    Task { @MainActor in
                        DownloadProgressBridge.shared.update(id: itemID, fraction: progress)
                    }
                },
                onTransfer: { transfer in
                    Task { @MainActor in
                        DownloadProgressBridge.shared.transfer(id: itemID, transfer: transfer)
                    }
                },
                onMeta: { choice in
                    Task { @MainActor in
                        DownloadProgressBridge.shared.meta(id: itemID, choice: choice)
                    }
                },
                onMerging: {
                    Task { @MainActor in
                        DownloadProgressBridge.shared.merging(id: itemID)
                    }
                }
            )
        }.value

        if !result.info.title.isEmpty {
            updateTitle(id: item.id, title: result.info.title)
        }
        await MainActor.run {
            DownloadProgressBridge.shared.completed(id: itemID, path: result.outputPath)
        }
    }

    private func retryWithCookies(item: DownloadItem, error: DownloadError) async {
        let payload = extensionCookiePayloads[item.id]
        let netscape = payload.flatMap { ExtensionCookiePayload.netscapeText(fromURLPayload: $0) }
        let hasExtensionCookies = netscape != nil
        let canUseSettingsCookies = settings.cookieMode != .none
            && !(settings.cookieMode == .file && (settings.cookieFilePath?.isEmpty ?? true))

        guard hasExtensionCookies || canUseSettingsCookies else {
            failWithCookieGuidance(
                item: item,
                original: error,
                hadExtensionCookies: false,
                usedCookies: false,
                netscapeText: nil
            )
            return
        }

        var tempCookieURL: URL?
        defer {
            if let tempCookieURL {
                try? FileManager.default.removeItem(at: tempCookieURL)
            }
        }

        var mode = settings.cookieMode
        var path = settings.cookieFilePath
        if let netscape {
            do {
                let fileURL = try ExtensionCookiePayload.writeTempCookieFile(netscapeText: netscape)
                tempCookieURL = fileURL
                mode = .file
                path = fileURL.path
            } catch {
                // Fall through to Safari / settings file if temp write fails.
            }
        }

        // Prefer extension file; only then --cookies-from-browser safari / settings file.
        if tempCookieURL == nil, !canUseSettingsCookies {
            failWithCookieGuidance(
                item: item,
                original: error,
                hadExtensionCookies: false,
                usedCookies: false,
                netscapeText: netscape
            )
            return
        }

        do {
            let cancellation = cancellations[item.id]
            try await runDownload(
                item,
                useCookies: true,
                cookieMode: mode,
                cookieFilePath: path,
                cancellation: cancellation
            )
        } catch {
            let downloadError = error as? DownloadError ?? .unknown(error.localizedDescription)
            failWithCookieGuidance(
                item: item,
                original: downloadError,
                hadExtensionCookies: hasExtensionCookies,
                usedCookies: true,
                stderr: downloadError.technicalDetail ?? downloadError.errorDescription,
                netscapeText: netscape
            )
        }
    }

    private func failWithCookieGuidance(
        item: DownloadItem,
        original: DownloadError,
        hadExtensionCookies: Bool,
        usedCookies: Bool,
        stderr: String? = nil,
        netscapeText: String? = nil
    ) {
        let guidance = CookieAccessDiagnoser.guidance(
            hadExtensionCookies: hadExtensionCookies,
            cookieMode: settings.cookieMode,
            usedCookies: usedCookies,
            lastError: original,
            stderr: stderr,
            netscapeText: netscapeText
        )
        let status: String
        if guidance.kind == .fullDiskAccessRequired {
            status = guidance.statusText
        } else if guidance.kind == .cookiesInsufficient {
            // Prefer concrete yt-dlp ERROR / missing-cookie detail over the generic title.
            status = guidance.statusText
        } else if original.requiresCookies {
            status = guidance.statusText
        } else {
            status = original.errorDescription ?? guidance.statusText
        }
        updateItemStatus(id: item.id, status: .failed, error: status)
        CookieAccessAlert.present(guidance)
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
        let note = DownloadItem.retryStatusLine(
            delay: delay,
            attempt: state.attempt,
            maxAttempts: retryStrategy.maxAttempts
        )
        if let index = queue.firstIndex(where: { $0.id == item.id }) {
            var waiting = queue[index]
            waiting.applyStatus(
                .retrying,
                retryNote: note,
                appendLog: error.errorDescription
            )
            queue[index] = waiting
            saveQueue()
        }
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
        useCookies: Bool = false,
        fallbackVideoFormatIds: [String] = []
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
                videoProtocol: formats.video.protocolName,
                fallbackVideoFormatIds: fallbackVideoFormatIds,
                onProgress: { progress in
                    Task { @MainActor in
                        DownloadProgressBridge.shared.update(id: itemID, fraction: progress)
                    }
                },
                onTransfer: { transfer in
                    Task { @MainActor in
                        DownloadProgressBridge.shared.transfer(id: itemID, transfer: transfer)
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
        let removedIDs = Set(queue.filter { $0.status == .completed || $0.status == .failed || $0.status == .cancelled }.map(\.id))
        guard !removedIDs.isEmpty else { return }
        queue.removeAll { removedIDs.contains($0.id) }
        if let selectedItemID, removedIDs.contains(selectedItemID) {
            self.selectedItemID = nil
        }
        saveQueue()
    }

    var hasFinishedItems: Bool {
        queue.contains { $0.status == .completed || $0.status == .failed || $0.status == .cancelled }
    }

    func attachProgressBridge() {
        DownloadProgressBridge.shared.handler = { [weak self] id, status, progress, path in
            guard let self else { return }
            if status == .completed {
                self.updateItemStatus(id: id, status: .completed, progress: 1, outputPath: path)
            } else if status == .merging {
                self.applyStage(id: id, status: .merging, stage: .merging, progress: progress)
            } else {
                let current = self.queue.first(where: { $0.id == id })?.stage
                if current == nil || current == .fetching || current == .formatChosen {
                    self.applyStage(id: id, status: .downloading, stage: .downloadingVideo, progress: progress)
                } else {
                    self.updateProgress(id: id, progress: progress)
                }
            }
        }
        DownloadProgressBridge.shared.metaHandler = { [weak self] id, choice in
            self?.applyStage(
                id: id,
                status: .downloading,
                stage: .formatChosen,
                title: choice.title,
                formatSummary: choice.summary
            )
        }
        DownloadProgressBridge.shared.transferHandler = { [weak self] id, transfer in
            guard let self else { return }
            let stage: DownloadStage
            switch transfer.stream {
            case .audio: stage = .downloadingAudio
            case .video: stage = .downloadingVideo
            case .unknown:
                if let current = self.queue.first(where: { $0.id == id })?.stage,
                   current == .downloadingAudio || current == .downloadingVideo {
                    stage = current
                } else {
                    stage = .downloadingVideo
                }
            }
            self.applyStage(
                id: id,
                status: .downloading,
                stage: stage,
                progress: transfer.fraction,
                speedText: transfer.speed,
                etaText: transfer.eta,
                sizeText: transfer.sizeText
            )
        }
    }

    func resumeQueue() {
        processQueue()
    }

    private func applyStage(
        id: UUID,
        status: DownloadStatus? = nil,
        stage: DownloadStage? = nil,
        progress: Double? = nil,
        title: String? = nil,
        formatSummary: String? = nil,
        speedText: String? = nil,
        etaText: String? = nil,
        sizeText: String? = nil
    ) {
        guard let index = queue.firstIndex(where: { $0.id == id }) else { return }
        var item = queue[index]
        let stageChanging = stage != nil && stage != item.stage
        if let status {
            item.applyStatus(status, progress: nil)
        }
        if let stage {
            item.stage = stage
        }
        if let progress {
            let clamped = min(max(progress, 0), 1)
            if stageChanging {
                item.progress = clamped
            } else {
                item.progress = min(max(clamped, item.progress), 1)
            }
        } else if stageChanging, stage == .downloadingVideo || stage == .downloadingAudio {
            item.progress = 0
        }
        if let title, !title.isEmpty { item.title = title }
        if let formatSummary, !formatSummary.isEmpty { item.formatSummary = formatSummary }
        if let speedText { item.speedText = speedText }
        if let etaText { item.etaText = etaText }
        if let sizeText { item.sizeText = sizeText }
        queue[index] = item
        if Date().timeIntervalSince(lastProgressSave) >= 0.4 {
            lastProgressSave = Date()
            saveQueue()
        }
    }

    private func loadSettings() {
        guard let data = try? Data(contentsOf: settingsFile),
              let loaded = try? JSONDecoder().decode(DownloadSettings.self, from: data) else {
            return
        }
        settings = loaded
    }

    func saveSettings() {
        guard let data = try? JSONEncoder().encode(settings) else { return }
        try? data.write(to: settingsFile)
    }

    private func loadQueue() {
        guard let data = try? Data(contentsOf: queueFile),
              let loaded = try? JSONDecoder().decode([DownloadItem].self, from: data) else {
            return
        }
        queue = loaded.map { item in
            var copy = item
            copy.sanitizeAfterLoad()
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
    var metaHandler: ((UUID, ParsedFormatChoice) -> Void)?
    var transferHandler: ((UUID, TransferProgress) -> Void)?

    func update(id: UUID, fraction: Double) {
        handler?(id, .downloading, fraction, nil)
    }

    func merging(id: UUID) {
        handler?(id, .merging, 1, nil)
    }

    func completed(id: UUID, path: String) {
        handler?(id, .completed, 1, path)
    }

    func meta(id: UUID, choice: ParsedFormatChoice) {
        metaHandler?(id, choice)
    }

    func transfer(id: UUID, transfer: TransferProgress) {
        transferHandler?(id, transfer)
    }
}
