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

    public func downloadFormat(url: String, formatId: String, outputPath: String, useCookies: Bool) throws {
        var args = ["-f", formatId, "-o", outputPath, "--no-warnings", "--no-part", url]
        args.append(contentsOf: cookieArguments(useCookies: useCookies))
        let result = try run(ytdlpPath, arguments: args)
        if result.status != 0 {
            throw ErrorClassifier().classifyError(from: result.stderr)
        }
    }

    public func merge(videoPath: String, audioPath: String, outputPath: String) throws {
        let result = try run(ffmpegPath, arguments: [
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

    public func downloadBest(url: String, outputDirectory: String, useCookies: Bool = false) throws -> DownloadPipelineResult {
        try FileManager.default.createDirectory(atPath: outputDirectory, withIntermediateDirectories: true)
        let formatList = try listFormats(url: url)
        let info = try fetchInfo(url: url, useCookies: useCookies)
        let formats = try FormatSelector().selectBestFormats(from: info)

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("ytd-dl-\(info.id)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let videoFile = tempDir.appendingPathComponent("video.\(formats.video.ext)").path
        let audioFile = tempDir.appendingPathComponent("audio.\(formats.audio.ext)").path

        try downloadFormat(url: url, formatId: formats.video.formatId, outputPath: videoFile, useCookies: useCookies)
        try downloadFormat(url: url, formatId: formats.audio.formatId, outputPath: audioFile, useCookies: useCookies)

        let sanitizedTitle = info.title.replacingOccurrences(of: "[^a-zA-Z0-9_\\-\\s]", with: "", options: .regularExpression)
        let outputFile = (outputDirectory as NSString).appendingPathComponent("\(sanitizedTitle)_\(info.id).mkv")
        try merge(videoPath: videoFile, audioPath: audioFile, outputPath: outputFile)

        return DownloadPipelineResult(info: info, formats: formats, outputPath: outputFile, formatList: formatList)
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

    private func run(_ executable: String, arguments: [String]) throws -> ProcessResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        return ProcessResult(
            stdout: String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            stderr: String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? "",
            status: process.terminationStatus
        )
    }
}
