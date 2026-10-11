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

    /// Lets yt-dlp download the chosen video+audio formats and remux them to MKV.
    public func downloadMerged(
        url: String,
        videoFormatId: String,
        audioFormatId: String,
        outputPath: String,
        useCookies: Bool,
        fallbackSpec: String? = "bestvideo*+bestaudio/best",
        onProgress: (@Sendable (Double) -> Void)? = nil,
        onMerging: (@Sendable () -> Void)? = nil
    ) throws {
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
                    outputPath: outputPath,
                    useCookies: useCookies,
                    onProgress: onProgress,
                    onMerging: onMerging
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

    public func downloadBest(url: String, outputDirectory: String, useCookies: Bool = false) throws -> DownloadPipelineResult {
        try FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
        let formatList = try listFormats(url: url)
        let info = try fetchInfo(url: url, useCookies: useCookies)
        let formats = try FormatSelector().selectBestFormats(from: info)

        let outputFile = (outputDirectory as NSString).appendingPathComponent(
            OutputFilename.make(title: info.title, videoId: info.id)
        )
        try downloadMerged(
            url: url,
            videoFormatId: formats.video.formatId,
            audioFormatId: formats.audio.formatId,
            outputPath: outputFile,
            useCookies: useCookies
        )

        return DownloadPipelineResult(info: info, formats: formats, outputPath: outputFile, formatList: formatList)
    }

    private func combinedOutput(_ result: ProcessResult) -> String {
        if result.stderr.isEmpty { return result.stdout }
        if result.stdout.isEmpty { return result.stderr }
        return result.stdout + "\n" + result.stderr
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
