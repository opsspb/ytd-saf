import Foundation

public struct DownloadPipelineResult: Sendable {
    public let info: YTDLPInfo
    public let formats: SelectedFormats
    public let outputPath: String
    public let formatList: String

    public init(info: YTDLPInfo, formats: SelectedFormats, outputPath: String, formatList: String) {
        self.info = info
        self.formats = formats
        self.outputPath = outputPath
        self.formatList = formatList
    }
}

public struct VideoDownloadPipeline: Sendable {
    public let ytdlpPath: String
    public let ffmpegPath: String
    public let aria2cPath: String?
    public var cookieMode: CookieMode
    public var cookieFilePath: String?

    public init(
        ytdlpPath: String,
        ffmpegPath: String,
        cookieMode: CookieMode = .none,
        cookieFilePath: String? = nil,
        aria2cPath: String? = nil
    ) {
        self.ytdlpPath = ytdlpPath
        self.ffmpegPath = ffmpegPath
        self.cookieMode = cookieMode
        self.cookieFilePath = cookieFilePath
        self.aria2cPath = aria2cPath
    }

    public func listFormats(url: String) throws -> String {
        let result = try run(ytdlpPath, arguments: ["-F", "--no-warnings", url])
        if result.status != 0 {
            throw ErrorClassifier().classifyError(from: result.stderr)
        }
        return result.stdout
    }

    public func fetchInfo(url: String, useCookies: Bool) throws -> YTDLPInfo {
        var args = ["-J", "--no-warnings", url]
        args.append(contentsOf: cookieArguments(useCookies: useCookies))
        let result = try run(ytdlpPath, arguments: args)
        if result.status != 0 {
            throw ErrorClassifier().classifyError(from: result.stderr)
        }
        return try JSONDecoder().decode(YTDLPInfo.self, from: Data(result.stdout.utf8))
    }

    public func downloadFormat(
        url: String,
        formatId: String,
        outputPath: String,
        useCookies: Bool,
        fallbackFormat: String? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil,
        onTransfer: (@Sendable (TransferProgress) -> Void)? = nil
    ) throws {
        var lastError: Error = DownloadError.downloadFailed("No format available")
        var candidates = [formatId]
        if let fallbackFormat, fallbackFormat != formatId {
            candidates.append(fallbackFormat)
        }
        for format in candidates {
            do {
                try downloadOnce(
                    url: url,
                    formatId: format,
                    outputPath: outputPath,
                    useCookies: useCookies,
                    onProgress: onProgress,
                    onTransfer: onTransfer
                )
                return
            } catch {
                lastError = error
                let text = (error as? LocalizedError)?.errorDescription?.lowercased() ?? "\(error)".lowercased()
                if text.contains("format is not available") || text.contains("requested format") {
                    continue
                }
                throw error
            }
        }
        throw lastError
    }

    private func downloadOnce(
        url: String,
        formatId: String,
        outputPath: String,
        useCookies: Bool,
        onProgress: (@Sendable (Double) -> Void)?,
        onTransfer: (@Sendable (TransferProgress) -> Void)? = nil
    ) throws {
        var args = [
            "-f", formatId,
            "-o", outputPath,
            "--no-warnings",
            "--no-part"
        ]
        args.append(contentsOf: YTDLPProgress.progressCLIArgs)
        args.append(url)
        args.append(contentsOf: cookieArguments(useCookies: useCookies))
        let session = ProgressSessionBox()
        let result = try run(ytdlpPath, arguments: args, onOutput: { line in
            Self.emitProgress(line: line, session: session, onProgress: onProgress, onTransfer: onTransfer, onMerging: nil)
        })
        if let done = session.finish() {
            onTransfer?(done)
            onProgress?(1)
        }
        if result.status != 0 {
            let output = result.stderr.isEmpty ? result.stdout : result.stderr
            throw ErrorClassifier().classifyError(from: output)
        }
    }

    public func merge(videoPath: String, audioPath: String, outputPath: String) throws {
        let result = try run(ffmpegPath, arguments: [
            "-fflags", "+genpts",
            "-i", videoPath,
            "-i", audioPath,
            "-c", "copy",
            "-y",
            outputPath
        ])
        if result.status != 0 {
            throw DownloadError.mergeFailed(result.stderr)
        }
    }

    /// Downloads video+audio and writes a single MKV.
    ///
    /// yt-dlp's Merger (`ffmpeg -c copy` into matroska) fails on native HLS
    /// mpegts with ffmpeg 9 ("Can't write packet with unknown timestamp").
    /// HLS (or any mpegts) is remuxed to MP4 first, then merged. Work files
    /// stay in a temp directory so `~/Downloads` only gets the final MKV.
    /// `fallbackVideoFormatIds` are same-res/fps next-bitrate candidates.
    public func downloadMerged(
        url: String,
        videoFormatId: String,
        audioFormatId: String,
        outputPath: String,
        useCookies: Bool,
        videoProtocol: String? = nil,
        fallbackVideoFormatIds: [String] = [],
        fallbackSpec: String? = "bestvideo*+bestaudio/best",
        onProgress: (@Sendable (Double) -> Void)? = nil,
        onTransfer: (@Sendable (TransferProgress) -> Void)? = nil,
        onMerging: (@Sendable () -> Void)? = nil
    ) throws {
        defer { removeMergeSidecars(outputPath: outputPath) }

        var candidates = [videoFormatId]
        for extra in fallbackVideoFormatIds where extra != videoFormatId && !candidates.contains(extra) {
            candidates.append(extra)
        }

        var lastError: Error = DownloadError.downloadFailed("No format available")
        for (index, candidate) in candidates.enumerated() {
            do {
                try downloadOneMergedPair(
                    url: url,
                    videoFormatId: candidate,
                    audioFormatId: audioFormatId,
                    outputPath: outputPath,
                    useCookies: useCookies,
                    videoProtocol: index == 0 ? videoProtocol : nil,
                    fallbackSpec: index == 0 ? fallbackSpec : nil,
                    onProgress: onProgress,
                    onTransfer: onTransfer,
                    onMerging: onMerging
                )
                return
            } catch {
                lastError = error
                let text = (error as? LocalizedError)?.errorDescription?.lowercased() ?? "\(error)".lowercased()
                removeMergeSidecars(outputPath: outputPath)
                if isMergeFailure(text) || text.contains("format is not available") || text.contains("requested format") {
                    continue
                }
                throw error
            }
        }
        throw lastError
    }

    private func downloadOneMergedPair(
        url: String,
        videoFormatId: String,
        audioFormatId: String,
        outputPath: String,
        useCookies: Bool,
        videoProtocol: String?,
        fallbackSpec: String?,
        onProgress: (@Sendable (Double) -> Void)?,
        onTransfer: (@Sendable (TransferProgress) -> Void)?,
        onMerging: (@Sendable () -> Void)?
    ) throws {
        if isHLSProtocol(videoProtocol) {
            try downloadSeparatelyAndMerge(
                url: url,
                videoFormatId: videoFormatId,
                audioFormatId: audioFormatId,
                outputPath: outputPath,
                useCookies: useCookies,
                onProgress: onProgress,
                onTransfer: onTransfer,
                onMerging: onMerging
            )
            return
        }

        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("ytd-merge-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }
        let tempOutput = workDir.appendingPathComponent("merged.mkv").path

        var lastError: Error = DownloadError.downloadFailed("No format available")
        var specs = ["\(videoFormatId)+\(audioFormatId)"]
        if let fallbackSpec, fallbackSpec != specs[0] {
            specs.append(fallbackSpec)
        }
        for spec in specs {
            do {
                try downloadMergedOnce(
                    url: url,
                    formatSpec: spec,
                    outputPath: tempOutput,
                    useCookies: useCookies,
                    onProgress: onProgress,
                    onTransfer: onTransfer,
                    onMerging: onMerging
                )
                try installFinalOutput(from: tempOutput, to: outputPath)
                return
            } catch {
                lastError = error
                let text = (error as? LocalizedError)?.errorDescription?.lowercased() ?? "\(error)".lowercased()
                if text.contains("format is not available") || text.contains("requested format") {
                    continue
                }
                if isMergeFailure(text) {
                    try downloadSeparatelyAndMerge(
                        url: url,
                        videoFormatId: videoFormatId,
                        audioFormatId: audioFormatId,
                        outputPath: outputPath,
                        useCookies: useCookies,
                        onProgress: onProgress,
                        onTransfer: onTransfer,
                        onMerging: onMerging
                    )
                    return
                }
                throw error
            }
        }
        throw lastError
    }

    private func installFinalOutput(from tempOutput: String, to outputPath: String) throws {
        if FileManager.default.fileExists(atPath: outputPath) {
            try FileManager.default.removeItem(atPath: outputPath)
        }
        try FileManager.default.copyItem(atPath: tempOutput, toPath: outputPath)
    }

    private func downloadMergedOnce(
        url: String,
        formatSpec: String,
        outputPath: String,
        useCookies: Bool,
        onProgress: (@Sendable (Double) -> Void)?,
        onTransfer: (@Sendable (TransferProgress) -> Void)?,
        onMerging: (@Sendable () -> Void)?
    ) throws {
        var args = [
            "-f", formatSpec,
            "--merge-output-format", "mkv",
            "--ffmpeg-location", ffmpegPath,
            "-o", outputPath,
            "--no-warnings",
            "--no-part",
            "--force-overwrites"
        ]
        args.append(contentsOf: YTDLPProgress.progressCLIArgs)
        args.append(url)
        args.append(contentsOf: cookieArguments(useCookies: useCookies))
        let session = ProgressSessionBox()
        let result = try run(ytdlpPath, arguments: args, onOutput: { line in
            Self.emitProgress(line: line, session: session, onProgress: onProgress, onTransfer: onTransfer, onMerging: onMerging)
        })
        if result.status != 0 {
            let output = combinedOutput(result)
            let lower = output.lowercased()
            if lower.contains("merger") || lower.contains("ffmpeg") || lower.contains("merge") {
                throw DownloadError.mergeFailed(output)
            }
            throw ErrorClassifier().classifyError(from: output)
        }
        guard FileManager.default.fileExists(atPath: outputPath) else {
            throw DownloadError.downloadFailed("yt-dlp finished without writing \(outputPath)")
        }
    }

    private func downloadSeparatelyAndMerge(
        url: String,
        videoFormatId: String,
        audioFormatId: String,
        outputPath: String,
        useCookies: Bool,
        onProgress: (@Sendable (Double) -> Void)?,
        onTransfer: (@Sendable (TransferProgress) -> Void)? = nil,
        onMerging: (@Sendable () -> Void)?
    ) throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ytd-hls-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let videoFile = tempDir.appendingPathComponent("video.mp4").path
        let audioFile = tempDir.appendingPathComponent("audio.m4a").path
        onTransfer?(TransferProgress(fraction: 0, stream: .video))
        try downloadFormat(
            url: url,
            formatId: videoFormatId,
            outputPath: videoFile,
            useCookies: useCookies,
            onProgress: onProgress,
            onTransfer: { transfer in
                var copy = transfer
                if copy.stream == .unknown { copy.stream = .video }
                onTransfer?(copy)
            }
        )
        onTransfer?(TransferProgress(fraction: 1, stream: .video))
        onProgress?(1)
        onTransfer?(TransferProgress(fraction: 0, stream: .audio))
        try downloadFormat(
            url: url,
            formatId: audioFormatId,
            outputPath: audioFile,
            useCookies: useCookies,
            onProgress: onProgress,
            onTransfer: { transfer in
                var copy = transfer
                if copy.stream == .unknown { copy.stream = .audio }
                onTransfer?(copy)
            }
        )
        onTransfer?(TransferProgress(fraction: 1, stream: .audio))
        onProgress?(1)
        onMerging?()
        let remuxed = try remuxCopyToMP4IfNeeded(videoFile)
        try merge(videoPath: remuxed, audioPath: audioFile, outputPath: outputPath)
        guard FileManager.default.fileExists(atPath: outputPath) else {
            throw DownloadError.mergeFailed("Remux/merge finished without writing \(outputPath)")
        }
    }

    func remuxCopyToMP4IfNeeded(_ inputPath: String) throws -> String {
        guard isMpegTS(inputPath) else { return inputPath }
        let dest = inputPath + ".remux.mp4"
        let result = try run(ffmpegPath, arguments: [
            "-y",
            "-i", inputPath,
            "-c", "copy",
            "-f", "mp4",
            dest
        ])
        guard FileManager.default.fileExists(atPath: dest) else {
            throw DownloadError.mergeFailed(result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        return dest
    }

    func isMpegTS(_ path: String) -> Bool {
        let probe = (try? run(ffmpegPath, arguments: ["-hide_banner", "-i", path]))
        let text = ((probe?.stderr ?? "") + "\n" + (probe?.stdout ?? "")).lowercased()
        return text.contains("mpegts")
    }

    func isHLSProtocol(_ protocolName: String?) -> Bool {
        let proto = (protocolName ?? "").lowercased()
        return proto.contains("m3u8") || proto.contains("hls")
    }

    private func isMergeFailure(_ text: String) -> Bool {
        text.contains("conversion failed")
            || text.contains("failed to merge")
            || text.contains("unknown timestamp")
            || text.contains("postprocessing")
    }

    public func cleanupMergeSidecars(around outputPath: String) {
        removeMergeSidecars(outputPath: outputPath)
    }

    private func removeMergeSidecars(outputPath: String) {
        let url = URL(fileURLWithPath: outputPath)
        let directory = url.deletingLastPathComponent()
        let stem = url.deletingPathExtension().lastPathComponent
        guard let items = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            return
        }
        for item in items {
            let name = item.lastPathComponent
            if name.hasPrefix(stem + ".f") || name.hasPrefix(stem + ".temp") {
                try? FileManager.default.removeItem(at: item)
            }
        }
    }

    public func downloadBest(url: String, outputDirectory: String, useCookies: Bool = false) throws -> DownloadPipelineResult {
        let adapter = SiteAdapterRegistry.adapter(for: url)
        if adapter.formatSpec != nil {
            return try downloadBestBySort(url: url, outputDirectory: outputDirectory, adapter: adapter, useCookies: useCookies)
        }
        try FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
        let formatList = try listFormats(url: url)
        let info = try fetchInfo(url: url, useCookies: useCookies)
        let selector = FormatSelector()
        let formats = try selector.selectBestFormats(from: info)
        let fallbackIds = selector.sameResolutionRung(as: formats.video, from: info)
            .map(\.formatId)
            .filter { $0 != formats.video.formatId }

        let outputFile = (outputDirectory as NSString).appendingPathComponent(
            OutputFilename.make(title: info.title, videoId: info.id)
        )
        try downloadMerged(
            url: url,
            videoFormatId: formats.video.formatId,
            audioFormatId: formats.audio.formatId,
            outputPath: outputFile,
            useCookies: useCookies,
            videoProtocol: formats.video.protocolName,
            fallbackVideoFormatIds: fallbackIds
        )

        return DownloadPipelineResult(info: info, formats: formats, outputPath: outputFile, formatList: formatList)
    }

    /// VK (and any adapter with a format spec): let yt-dlp pick formats.
    /// Always re-extracts from the page URL so IP-bound CDN links stay fresh.
    public func downloadBySort(
        url: String,
        outputDirectory: String,
        adapter: SiteAdapterInfo = SiteAdapterRegistry.vk,
        useCookies: Bool = false,
        includeFormatList: Bool = false,
        cancellation: ProcessCancellation? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil,
        onTransfer: (@Sendable (TransferProgress) -> Void)? = nil,
        onMeta: (@Sendable (ParsedFormatChoice) -> Void)? = nil,
        onMerging: (@Sendable () -> Void)? = nil
    ) throws -> DownloadPipelineResult {
        try downloadBestBySort(
            url: url,
            outputDirectory: outputDirectory,
            adapter: adapter,
            useCookies: useCookies,
            includeFormatList: includeFormatList,
            cancellation: cancellation,
            onProgress: onProgress,
            onTransfer: onTransfer,
            onMeta: onMeta,
            onMerging: onMerging
        )
    }

    private func downloadBestBySort(
        url: String,
        outputDirectory: String,
        adapter: SiteAdapterInfo,
        useCookies: Bool,
        includeFormatList: Bool = true,
        cancellation: ProcessCancellation? = nil,
        onProgress: (@Sendable (Double) -> Void)? = nil,
        onTransfer: (@Sendable (TransferProgress) -> Void)? = nil,
        onMeta: (@Sendable (ParsedFormatChoice) -> Void)? = nil,
        onMerging: (@Sendable () -> Void)? = nil
    ) throws -> DownloadPipelineResult {
        try FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
        let formatList = includeFormatList ? (try listFormats(url: url)) : ""
        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("ytd-sort-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }
        let tempOutput = workDir.appendingPathComponent("sorted.mkv").path

        let choice: ParsedFormatChoice
        do {
            choice = try downloadSortedOnce(
                url: url,
                adapter: adapter,
                outputPath: tempOutput,
                useCookies: useCookies,
                useExternalDownloader: true,
                cancellation: cancellation,
                onProgress: onProgress,
                onTransfer: onTransfer,
                onMeta: onMeta,
                onMerging: onMerging
            )
        } catch {
            let text = (error as? LocalizedError)?.errorDescription ?? "\(error)"
            if (error as? DownloadError) == .cancelled { throw error }
            if isExternalDownloaderFailure(text) {
                choice = try downloadSortedOnce(
                    url: url,
                    adapter: adapter,
                    outputPath: tempOutput,
                    useCookies: useCookies,
                    useExternalDownloader: false,
                    cancellation: cancellation,
                    onProgress: onProgress,
                    onTransfer: onTransfer,
                    onMeta: onMeta,
                    onMerging: onMerging
                )
            } else {
                guard isMergeFailure(text.lowercased()),
                      let recovered = YTDLPOutputParser.parseMeta(from: text) else {
                    throw error
                }
                if let audioId = recovered.audioFormatId {
                    try downloadSeparatelyAndMerge(
                        url: url,
                        videoFormatId: recovered.videoFormatId,
                        audioFormatId: audioId,
                        outputPath: tempOutput,
                        useCookies: useCookies,
                        onProgress: onProgress,
                        onTransfer: onTransfer,
                        onMerging: onMerging
                    )
                    choice = recovered
                } else {
                    throw error
                }
            }
        }

        if choice.extractor.lowercased() == "youtube" {
            throw DownloadError.unsupportedMedia
        }

        let info = YTDLPInfo(id: choice.id, title: choice.title, formats: [])
        let formats = SelectedFormats(
            video: VideoFormat(
                formatId: choice.videoFormatId,
                ext: "mp4",
                resolution: choice.resolution,
                fps: choice.fps
            ),
            audio: VideoFormat(
                formatId: choice.audioFormatId ?? choice.videoFormatId,
                ext: "m4a"
            )
        )
        let outputFile = (outputDirectory as NSString).appendingPathComponent(
            OutputFilename.make(title: choice.title.isEmpty ? "video" : choice.title, videoId: choice.id.isEmpty ? "vk" : choice.id)
        )
        try installFinalOutput(from: tempOutput, to: outputFile)
        return DownloadPipelineResult(info: info, formats: formats, outputPath: outputFile, formatList: formatList)
    }

    private func isExternalDownloaderFailure(_ text: String) -> Bool {
        let lower = text.lowercased()
        return lower.contains("aria2")
            || lower.contains("external downloader")
            || (lower.contains("downloader") && lower.contains("not found"))
    }

    private func downloadSortedOnce(
        url: String,
        adapter: SiteAdapterInfo,
        outputPath: String,
        useCookies: Bool,
        useExternalDownloader: Bool = true,
        cancellation: ProcessCancellation? = nil,
        onProgress: (@Sendable (Double) -> Void)?,
        onTransfer: (@Sendable (TransferProgress) -> Void)? = nil,
        onMeta: (@Sendable (ParsedFormatChoice) -> Void)? = nil,
        onMerging: (@Sendable () -> Void)?
    ) throws -> ParsedFormatChoice {
        guard let formatSpec = adapter.formatSpec, let formatSort = adapter.formatSort else {
            throw DownloadError.invalidURL
        }
        let captured = LockedText()
        var args = [
            "-f", formatSpec,
            "-S", formatSort,
            "--merge-output-format", "mkv",
            "--remux-video", "mkv",
            "--ffmpeg-location", ffmpegPath,
            "-o", outputPath,
            "--no-warnings",
            "--no-part",
            "--force-overwrites",
            "--no-simulate"
        ]
        args.append(contentsOf: YTDLPProgress.progressCLIArgs)
        args.append(contentsOf: ["--print", YTDLPOutputParser.metaPrintTemplate(), url])
        let aria2c = useExternalDownloader ? aria2cPath : nil
        args.insert(contentsOf: adapter.downloadArgs(aria2cPath: aria2c), at: args.count - 1)
        args.append(contentsOf: cookieArguments(useCookies: useCookies))
        let workDir = (outputPath as NSString).deletingLastPathComponent
        let expected = LockedBytes()
        let session = ProgressSessionBox()
        let result = try run(ytdlpPath, arguments: args, cancellation: cancellation, onOutput: { line in
            captured.append(line)
            if let meta = YTDLPOutputParser.parseMeta(from: line) {
                onMeta?(meta)
            }
            Self.emitProgress(line: line, session: session, onProgress: onProgress, onTransfer: { transfer in
                if let bytes = transfer.expectedBytes { expected.set(bytes) }
                onTransfer?(transfer)
            }, onMerging: onMerging)
        }, onTick: {
            let wrote = YTDLPProgress.allocatedBytes(in: workDir)
            guard wrote > 0 else { return }
            let total = expected.value
            let stream = YTDLPProgress.activeStream(in: workDir)
            if total > 0 {
                let fraction = min(Double(wrote) / Double(total), 0.99)
                let transfer = session.noteDisk(
                    fraction: fraction,
                    wrote: wrote,
                    total: total,
                    stream: stream,
                    sizeText: bytePair(wrote, total)
                )
                onProgress?(transfer.fraction ?? fraction)
                onTransfer?(transfer)
            } else if wrote > 1_000_000 {
                onTransfer?(TransferProgress(downloadedBytes: wrote, stream: stream == .unknown ? .video : stream))
            }
        })
        let output = combinedOutput(result) + "\n" + captured.value
        if result.status != 0 {
            let lower = output.lowercased()
            if lower.contains("merger") || lower.contains("ffmpeg") || lower.contains("merge") || lower.contains("remux") {
                if let choice = YTDLPOutputParser.parseMeta(from: output) {
                    throw DownloadError.mergeFailed("\(choice.formatId)\n\(output)")
                }
                throw DownloadError.mergeFailed(output)
            }
            throw ErrorClassifier().classifyError(from: output)
        }
        if !FileManager.default.fileExists(atPath: outputPath) {
            if let found = firstMediaFile(in: (outputPath as NSString).deletingLastPathComponent) {
                try FileManager.default.moveItem(atPath: found, toPath: outputPath)
            }
        }
        guard FileManager.default.fileExists(atPath: outputPath) else {
            throw DownloadError.downloadFailed("yt-dlp finished without writing \(outputPath)\n\(output)")
        }
        guard let choice = YTDLPOutputParser.parseMeta(from: output) else {
            return ParsedFormatChoice(extractor: "vk", id: "", title: "", formatId: "bv*+ba")
        }
        return choice
    }

    private func combinedOutput(_ result: ProcessResult) -> String {
        if result.stderr.isEmpty { return result.stdout }
        if result.stdout.isEmpty { return result.stderr }
        return result.stdout + "\n" + result.stderr
    }

    private func firstMediaFile(in directory: String) -> String? {
        let exts = ["mkv", "mp4", "webm", "m4a"]
        guard let items = try? FileManager.default.contentsOfDirectory(atPath: directory) else {
            return nil
        }
        return items
            .filter { name in exts.contains((name as NSString).pathExtension.lowercased()) }
            .map { (directory as NSString).appendingPathComponent($0) }
            .first
    }

    private final class LockedText: @unchecked Sendable {
        private let lock = NSLock()
        private var storage = ""
        func append(_ line: String) {
            lock.lock()
            storage += line + "\n"
            lock.unlock()
        }
        var value: String {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    private final class LockedBytes: @unchecked Sendable {
        private let lock = NSLock()
        private var storage: Int64 = 0
        func set(_ value: Int64) {
            lock.lock()
            storage = value
            lock.unlock()
        }
        var value: Int64 {
            lock.lock()
            defer { lock.unlock() }
            return storage
        }
    }

    private func bytePair(_ got: Int64, _ total: Int64) -> String {
        func fmt(_ n: Int64) -> String {
            let kb = Double(n) / 1024
            if kb < 1024 { return String(format: "%.0fKiB", kb) }
            let mb = kb / 1024
            if mb < 1024 { return String(format: "%.1fMiB", mb) }
            return String(format: "%.2fGiB", mb / 1024)
        }
        return "\(fmt(got))/\(fmt(total))"
    }

    private func cookieArguments(useCookies: Bool) -> [String] {
        guard useCookies else { return [] }
        switch cookieMode {
        case .safari:
            return ["--cookies-from-browser", "safari"]
        case .file:
            if let cookieFilePath {
                return ["--cookies", cookieFilePath]
            }
            return []
        case .none:
            return []
        }
    }

    private struct ProcessResult {
        let stdout: String
        let stderr: String
        let status: Int32
    }

    private func run(
        _ executable: String,
        arguments: [String],
        cancellation: ProcessCancellation? = nil,
        onOutput: (@Sendable (String) -> Void)? = nil,
        onTick: (@Sendable () -> Void)? = nil
    ) throws -> ProcessResult {
        let timeout = Self.ytdlpTimeout(for: arguments)
        let result = try ProcessRunner.run(
            executable: executable,
            arguments: arguments,
            timeout: timeout,
            cancellation: cancellation,
            onOutput: onOutput,
            onTick: onTick
        )
        if result.cancelled {
            throw DownloadError.cancelled
        }
        if result.timedOut {
            throw DownloadError.unknown("Timed out running \(executable)")
        }
        return ProcessResult(stdout: result.stdout, stderr: result.stderr, status: result.status)
    }

    /// Metadata probes stay short. Media download/merge must outlast a 4K VK file
    /// (this URL is ~5.4 GiB; 600s killed aria2c mid-transfer).
    static func ytdlpTimeout(for arguments: [String]) -> TimeInterval {
        if arguments.contains("-J") || arguments.contains("-F") {
            return 90
        }
        return 12 * 60 * 60
    }

    private final class ProgressSessionBox: @unchecked Sendable {
        private let lock = NSLock()
        private var session = DownloadProgressSession()

        func finish() -> TransferProgress? {
            lock.lock()
            defer { lock.unlock() }
            return session.finishCurrentStream()
        }

        func noteDisk(
            fraction: Double,
            wrote: Int64,
            total: Int64,
            stream: TransferProgress.StreamKind,
            sizeText: String
        ) -> TransferProgress {
            lock.lock()
            defer { lock.unlock() }
            return session.noteTransfer(TransferProgress(
                fraction: fraction,
                sizeText: sizeText,
                expectedBytes: total,
                downloadedBytes: wrote,
                stream: stream == .unknown ? session.stream : stream
            ))
        }

        func handle(_ line: String) -> (transfers: [TransferProgress], merging: Bool) {
            lock.lock()
            defer { lock.unlock() }
            return session.events(for: line)
        }
    }

    private static func emitProgress(
        line: String,
        session: ProgressSessionBox,
        onProgress: (@Sendable (Double) -> Void)?,
        onTransfer: (@Sendable (TransferProgress) -> Void)?,
        onMerging: (@Sendable () -> Void)?
    ) {
        let result = session.handle(line)
        for transfer in result.transfers {
            if let fraction = transfer.fraction {
                onProgress?(fraction)
            }
            onTransfer?(transfer)
        }
        if result.merging {
            onMerging?()
        }
    }
}
