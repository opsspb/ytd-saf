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
    public let ffprobePath: String?
    public let aria2cPath: String?
    public var cookieMode: CookieMode
    public var cookieFilePath: String?

    public init(
        ytdlpPath: String,
        ffmpegPath: String,
        cookieMode: CookieMode = .none,
        cookieFilePath: String? = nil,
        aria2cPath: String? = nil,
        ffprobePath: String? = nil
    ) {
        self.ytdlpPath = ytdlpPath
        self.ffmpegPath = ffmpegPath
        self.cookieMode = cookieMode
        self.cookieFilePath = cookieFilePath
        self.aria2cPath = aria2cPath
        if let ffprobePath, !ffprobePath.isEmpty {
            self.ffprobePath = ffprobePath
        } else {
            let sibling = (ffmpegPath as NSString).deletingLastPathComponent
                .appending("/ffprobe")
            self.ffprobePath = FileManager.default.isExecutableFile(atPath: sibling) ? sibling : nil
        }
    }

    public func listFormats(url: String) throws -> String {
        let result = try run(ytdlpPath, arguments: ["-F", "--no-warnings", url])
        if result.status != 0 {
            throw ErrorClassifier().classifyError(from: result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        return result.stdout
    }

    /// Arguments for `yt-dlp -J` (same auth flags as the download step).
    public func infoArguments(url: String, useCookies: Bool) -> [String] {
        var args = ["-J", "--no-warnings"]
        args.append(contentsOf: authArguments(url: url, useCookies: useCookies))
        args.append(url)
        return args
    }

    /// Arguments for a format-spec download (muxed id or `bv*+ba/b`).
    public func formatSpecDownloadArguments(
        url: String,
        formatSpec: String,
        outputPath: String,
        useCookies: Bool
    ) -> [String] {
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
        args.append(contentsOf: authArguments(url: url, useCookies: useCookies))
        args.append(url)
        return args
    }

    /// `--extractor-args` + `--cookies` / `--cookies-from-browser` shared by -J and download.
    public func authArguments(url: String, useCookies: Bool) -> [String] {
        Self.youtubeExtractorArgs(for: url, useCookies: useCookies)
            + cookieArguments(useCookies: useCookies)
    }

    public func fetchInfo(url: String, useCookies: Bool) throws -> YTDLPInfo {
        let args = infoArguments(url: url, useCookies: useCookies)
        let result = try run(ytdlpPath, arguments: args, netscapeForLog: useCookies ? cookieFileNetscape() : nil)
        if result.status != 0 {
            throw ErrorClassifier().classifyError(from: result.stderr.isEmpty ? result.stdout : result.stderr)
        }
        do {
            return try JSONDecoder().decode(YTDLPInfo.self, from: Data(result.stdout.utf8))
        } catch {
            throw DownloadError.fetchInfoFailed(Self.describeDecodeError(error))
        }
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
        args.append(contentsOf: authArguments(url: url, useCookies: useCookies))
        args.append(url)
        let session = ProgressSessionBox()
        let result = try run(
            ytdlpPath,
            arguments: args,
            netscapeForLog: useCookies ? cookieFileNetscape() : nil,
            onOutput: { line in
                Self.emitProgress(line: line, session: session, onProgress: onProgress, onTransfer: onTransfer, onMerging: nil)
            }
        )
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
        let args = formatSpecDownloadArguments(
            url: url,
            formatSpec: formatSpec,
            outputPath: outputPath,
            useCookies: useCookies
        )
        let session = ProgressSessionBox()
        let result = try run(
            ytdlpPath,
            arguments: args,
            netscapeForLog: useCookies ? cookieFileNetscape() : nil,
            onOutput: { line in
                Self.emitProgress(line: line, session: session, onProgress: onProgress, onTransfer: onTransfer, onMerging: onMerging)
            }
        )
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

    /// Download using a precomputed `FormatPick` (separable, muxed, or yt-dlp fallback).
    public func downloadPicked(
        url: String,
        info: YTDLPInfo,
        pick: FormatPick,
        outputPath: String,
        useCookies: Bool,
        onProgress: (@Sendable (Double) -> Void)? = nil,
        onTransfer: (@Sendable (TransferProgress) -> Void)? = nil,
        onMerging: (@Sendable () -> Void)? = nil
    ) throws {
        if !pick.usedSeparablePicker, let spec = pick.fallbackSpec {
            YTDLPDiagnostics.writeFormatPickerFallbackLog(info: info, fallbackSpec: spec)
        }

        switch pick {
        case .separate(let formats, let fallbackIds):
            try downloadMerged(
                url: url,
                videoFormatId: formats.video.formatId,
                audioFormatId: formats.audio.formatId,
                outputPath: outputPath,
                useCookies: useCookies,
                videoProtocol: formats.video.protocolName,
                fallbackVideoFormatIds: fallbackIds,
                onProgress: onProgress,
                onTransfer: onTransfer,
                onMerging: onMerging
            )
        case .muxed(let format):
            try downloadByFormatSpec(
                url: url,
                formatSpec: format.formatId,
                outputPath: outputPath,
                useCookies: useCookies,
                onProgress: onProgress,
                onTransfer: onTransfer,
                onMerging: onMerging
            )
        case .ytDlpFallback(let spec):
            try downloadByFormatSpec(
                url: url,
                formatSpec: spec,
                outputPath: outputPath,
                useCookies: useCookies,
                onProgress: onProgress,
                onTransfer: onTransfer,
                onMerging: onMerging
            )
        }

        try verifyOutputHasVideoAndAudio(at: outputPath)
    }

    /// Single-spec download into `outputPath` (MKV), reusing the same cookie / extractor-args as `-J`.
    public func downloadByFormatSpec(
        url: String,
        formatSpec: String,
        outputPath: String,
        useCookies: Bool,
        onProgress: (@Sendable (Double) -> Void)? = nil,
        onTransfer: (@Sendable (TransferProgress) -> Void)? = nil,
        onMerging: (@Sendable () -> Void)? = nil
    ) throws {
        defer { removeMergeSidecars(outputPath: outputPath) }
        let workDir = FileManager.default.temporaryDirectory.appendingPathComponent("ytd-spec-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: workDir) }
        let tempOutput = workDir.appendingPathComponent("out.mkv").path
        try downloadMergedOnce(
            url: url,
            formatSpec: formatSpec,
            outputPath: tempOutput,
            useCookies: useCookies,
            onProgress: onProgress,
            onTransfer: onTransfer,
            onMerging: onMerging
        )
        try installFinalOutput(from: tempOutput, to: outputPath)
    }

    /// Best-effort ffprobe check: require ≥1 video and ≥1 audio stream.
    public func verifyOutputHasVideoAndAudio(at outputPath: String) throws {
        guard let ffprobePath, FileManager.default.isExecutableFile(atPath: ffprobePath) else {
            return
        }
        let result = try run(ffprobePath, arguments: [
            "-v", "error",
            "-show_entries", "stream=codec_type",
            "-of", "csv=p=0",
            outputPath
        ])
        if result.status != 0 {
            // Probe failure should not mask a successful download unless streams are clearly wrong.
            return
        }
        let lines = result.stdout
            .split(omittingEmptySubsequences: true, whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        let hasVideo = lines.contains { $0 == "video" || $0.hasPrefix("video") }
        let hasAudio = lines.contains { $0 == "audio" || $0.hasPrefix("audio") }
        if !hasVideo {
            throw DownloadError.downloadFailed("Downloaded file is missing a video stream")
        }
        if !hasAudio {
            throw DownloadError.downloadFailed("Downloaded file is missing an audio stream")
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
        let pick = FormatSelector().pickFormats(from: info)

        let outputFile = (outputDirectory as NSString).appendingPathComponent(
            OutputFilename.make(title: info.title, videoId: info.id)
        )
        try downloadPicked(
            url: url,
            info: info,
            pick: pick,
            outputPath: outputFile,
            useCookies: useCookies
        )

        return DownloadPipelineResult(
            info: info,
            formats: pick.selectedFormats,
            outputPath: outputFile,
            formatList: formatList
        )
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
        try verifyOutputHasVideoAndAudio(at: outputFile)
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
        args.append(contentsOf: authArguments(url: url, useCookies: useCookies))
        args.append(contentsOf: ["--print", YTDLPOutputParser.metaPrintTemplate(), url])
        let aria2c = useExternalDownloader ? aria2cPath : nil
        args.insert(contentsOf: adapter.downloadArgs(aria2cPath: aria2c), at: args.count - 1)
        let workDir = (outputPath as NSString).deletingLastPathComponent
        let expected = LockedBytes()
        let session = ProgressSessionBox()
        let result = try run(
            ytdlpPath,
            arguments: args,
            cancellation: cancellation,
            netscapeForLog: useCookies ? cookieFileNetscape() : nil,
            onOutput: { line in
                captured.append(line)
                if let meta = YTDLPOutputParser.parseMeta(from: line) {
                    onMeta?(meta)
                }
                Self.emitProgress(line: line, session: session, onProgress: onProgress, onTransfer: { transfer in
                    if let bytes = transfer.expectedBytes { expected.set(bytes) }
                    onTransfer?(transfer)
                }, onMerging: onMerging)
            },
            onTick: {
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
            }
        )
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
        var args: [String] = []
        // Per-download Netscape file (extension cookies) wins over Safari store.
        if let cookieFilePath, !cookieFilePath.isEmpty {
            args.append(contentsOf: ["--cookies", cookieFilePath])
        } else {
            switch cookieMode {
            case .safari:
                args.append(contentsOf: ["--cookies-from-browser", "safari"])
            case .file, .none:
                break
            }
        }
        return args
    }

    /// YouTube player clients that work well with browser cookies (no hardcoded user data).
    static func youtubeExtractorArgs(for url: String, useCookies: Bool) -> [String] {
        guard useCookies, isYouTubeURL(url) else { return [] }
        return ["--extractor-args", "youtube:player_client=default,web_safari"]
    }

    static func isYouTubeURL(_ url: String) -> Bool {
        let lower = url.lowercased()
        return lower.contains("youtube.com") || lower.contains("youtu.be")
    }

    static func describeDecodeError(_ error: Error) -> String {
        if let decoding = error as? DecodingError {
            switch decoding {
            case .dataCorrupted(let context):
                return "JSON decode failed: \(context.debugDescription) @ \(codingPath(context.codingPath))"
            case .keyNotFound(let key, let context):
                return "JSON decode failed: missing key \(key.stringValue) @ \(codingPath(context.codingPath))"
            case .typeMismatch(let type, let context):
                return "JSON decode failed: type mismatch \(type) @ \(codingPath(context.codingPath)) (\(context.debugDescription))"
            case .valueNotFound(let type, let context):
                return "JSON decode failed: value not found \(type) @ \(codingPath(context.codingPath))"
            @unknown default:
                return "JSON decode failed: \(decoding)"
            }
        }
        return "JSON decode failed: \(error.localizedDescription)"
    }

    private static func codingPath(_ path: [CodingKey]) -> String {
        path.map(\.stringValue).joined(separator: ".")
    }

    private struct ProcessResult {
        let stdout: String
        let stderr: String
        let status: Int32
    }

    private func cookieFileNetscape() -> String? {
        guard let cookieFilePath, !cookieFilePath.isEmpty,
              let data = try? Data(contentsOf: URL(fileURLWithPath: cookieFilePath)),
              let text = String(data: data, encoding: .utf8),
              !text.isEmpty else {
            return nil
        }
        return text
    }

    private func run(
        _ executable: String,
        arguments: [String],
        cancellation: ProcessCancellation? = nil,
        netscapeForLog: String? = nil,
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
        if executable == ytdlpPath {
            let cookiePath: String?
            if let idx = arguments.firstIndex(of: "--cookies"), idx + 1 < arguments.count {
                cookiePath = arguments[idx + 1]
            } else {
                cookiePath = nil
            }
            YTDLPDiagnostics.writeRunLog(
                executable: executable,
                arguments: arguments,
                stderr: result.stderr,
                cookieFilePath: cookiePath,
                netscapeText: netscapeForLog,
                exitCode: result.status,
                stdoutByteCount: result.stdout.utf8.count
            )
        }
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
