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
    public var cookieMode: CookieMode
    public var cookieFilePath: String?

    public init(
        ytdlpPath: String,
        ffmpegPath: String,
        cookieMode: CookieMode = .none,
        cookieFilePath: String? = nil
    ) {
        self.ytdlpPath = ytdlpPath
        self.ffmpegPath = ffmpegPath
        self.cookieMode = cookieMode
        self.cookieFilePath = cookieFilePath
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
        onProgress: (@Sendable (Double) -> Void)? = nil
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
                    onProgress: onProgress
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
        onProgress: (@Sendable (Double) -> Void)?
    ) throws {
        var args = [
            "-f", formatId,
            "-o", outputPath,
            "--no-warnings",
            "--no-part",
            "--newline",
            "--progress",
            "--progress-delta", "0.2",
            "--progress-template", "download:%(progress._percent_str)s",
            url
        ]
        args.append(contentsOf: cookieArguments(useCookies: useCookies))
        let result = try run(ytdlpPath, arguments: args, onOutput: { line in
            if let progress = YTDLPProgress.parse(line) {
                onProgress?(progress)
            }
        })
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
        onMerging: (@Sendable () -> Void)?
    ) throws {
        var args = [
            "-f", formatSpec,
            "--merge-output-format", "mkv",
            "--ffmpeg-location", ffmpegPath,
            "-o", outputPath,
            "--no-warnings",
            "--no-part",
            "--force-overwrites",
            "--newline",
            "--progress",
            "--progress-delta", "0.2",
            "--progress-template", "download:%(progress._percent_str)s",
            url
        ]
        args.append(contentsOf: cookieArguments(useCookies: useCookies))
        let result = try run(ytdlpPath, arguments: args, onOutput: { line in
            if line.contains("[Merger]") || line.contains("[Fixup]") {
                onMerging?()
            }
            if let progress = YTDLPProgress.parse(line) {
                onProgress?(progress)
            }
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
        onMerging: (@Sendable () -> Void)?
    ) throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ytd-hls-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let videoFile = tempDir.appendingPathComponent("video.mp4").path
        let audioFile = tempDir.appendingPathComponent("audio.m4a").path
        try downloadFormat(
            url: url,
            formatId: videoFormatId,
            outputPath: videoFile,
            useCookies: useCookies,
            onProgress: { onProgress?($0 * 0.7) }
        )
        try downloadFormat(
            url: url,
            formatId: audioFormatId,
            outputPath: audioFile,
            useCookies: useCookies,
            onProgress: { onProgress?(0.7 + $0 * 0.2) }
        )
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
        onProgress: (@Sendable (Double) -> Void)? = nil,
        onMerging: (@Sendable () -> Void)? = nil
    ) throws -> DownloadPipelineResult {
        try downloadBestBySort(
            url: url,
            outputDirectory: outputDirectory,
            adapter: adapter,
            useCookies: useCookies,
            includeFormatList: includeFormatList,
            onProgress: onProgress,
            onMerging: onMerging
        )
    }

    private func downloadBestBySort(
        url: String,
        outputDirectory: String,
        adapter: SiteAdapterInfo,
        useCookies: Bool,
        includeFormatList: Bool = true,
        onProgress: (@Sendable (Double) -> Void)? = nil,
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
                onProgress: onProgress,
                onMerging: onMerging
            )
        } catch {
            let text = (error as? LocalizedError)?.errorDescription ?? "\(error)"
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
                    onMerging: onMerging
                )
                choice = recovered
            } else {
                throw error
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

    private func downloadSortedOnce(
        url: String,
        adapter: SiteAdapterInfo,
        outputPath: String,
        useCookies: Bool,
        onProgress: (@Sendable (Double) -> Void)?,
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
            "--no-simulate",
            "--newline",
            "--progress",
            "--progress-delta", "0.2",
            "--progress-template", "download:%(progress._percent_str)s",
            "--print", YTDLPOutputParser.metaPrintTemplate(),
            url
        ]
        args.insert(contentsOf: adapter.extraArgs, at: args.count - 1)
        args.append(contentsOf: cookieArguments(useCookies: useCookies))
        let result = try run(ytdlpPath, arguments: args, onOutput: { line in
            captured.append(line)
            if line.contains("[Merger]") || line.contains("[Fixup]") || line.contains("[Remux]") {
                onMerging?()
            }
            if let progress = YTDLPProgress.parse(line) {
                onProgress?(progress)
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
        onOutput: (@Sendable (String) -> Void)? = nil
    ) throws -> ProcessResult {
        let timeout: TimeInterval = arguments.contains("-J") || arguments.contains("-F") ? 90 : 600
        let result = try ProcessRunner.run(
            executable: executable,
            arguments: arguments,
            timeout: timeout,
            onOutput: onOutput
        )
        if result.timedOut {
            throw DownloadError.unknown("Timed out running \(executable)")
        }
        return ProcessResult(stdout: result.stdout, stderr: result.stderr, status: result.status)
    }
}
