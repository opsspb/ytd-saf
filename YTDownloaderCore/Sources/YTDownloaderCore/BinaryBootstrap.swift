import Foundation

public enum BinarySource: String, Equatable, Sendable {
    case homebrew
    case installed
    case downloaded
}

public enum DownloadedFileKind: Equatable, Sendable {
    case zip
    case xz
    case macho
    case html
    case unknown

    public static func detect(data: Data) -> DownloadedFileKind {
        guard !data.isEmpty else { return .unknown }
        if data.starts(with: [0x50, 0x4B, 0x03, 0x04]) || data.starts(with: [0x50, 0x4B, 0x05, 0x06]) {
            return .zip
        }
        if data.starts(with: [0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00]) {
            return .xz
        }
        let machoMagics: [[UInt8]] = [
            [0xCF, 0xFA, 0xED, 0xFE],
            [0xCE, 0xFA, 0xED, 0xFE],
            [0xFE, 0xED, 0xFA, 0xCF],
            [0xFE, 0xED, 0xFA, 0xCE],
            [0xCA, 0xFE, 0xBA, 0xBE],
            [0xBE, 0xBA, 0xFE, 0xCA]
        ]
        for magic in machoMagics {
            if data.starts(with: magic) { return .macho }
        }
        if let prefix = String(data: data.prefix(64), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased() {
            if prefix.hasPrefix("<!doctype") || prefix.hasPrefix("<html") || prefix.contains("too many requests") {
                return .html
            }
        }
        return .unknown
    }
}

public struct BinaryPaths: Equatable, Sendable {
    public let ytdlp: String
    public let ffmpeg: String
    public let ffprobe: String
    public let aria2c: String?
    public let source: BinarySource

    public init(ytdlp: String, ffmpeg: String, ffprobe: String, source: BinarySource, aria2c: String? = nil) {
        self.ytdlp = ytdlp
        self.ffmpeg = ffmpeg
        self.ffprobe = ffprobe
        self.aria2c = aria2c
        self.source = source
    }
}

public struct BinaryBootstrap: Sendable {
    public let binariesDirectory: URL
    public let preferHomebrew: Bool
    public let maxAttempts: Int
    public var onProgress: (@Sendable (String, Double) -> Void)?

    public init(
        binariesDirectory: URL? = nil,
        preferHomebrew: Bool = true,
        maxAttempts: Int = 3,
        onProgress: (@Sendable (String, Double) -> Void)? = nil
    ) {
        if let binariesDirectory {
            self.binariesDirectory = binariesDirectory
        } else {
            let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            self.binariesDirectory = appSupport.appendingPathComponent("YTDownloader/bin")
        }
        self.preferHomebrew = preferHomebrew
        self.maxAttempts = maxAttempts
        self.onProgress = onProgress
    }

    public static func cpuArchitecture() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0) ?? "unknown"
            }
        }
        return machine.hasPrefix("arm64") ? "arm64" : "amd64"
    }

    public static func martinRiedlURL(tool: String, arch: String = cpuArchitecture(), channel: String) -> URL {
        URL(string: "https://ffmpeg.martin-riedl.de/redirect/latest/macos/\(arch)/\(channel)/\(tool).zip")!
    }

    public static func evermeetURL(tool: String) -> URL {
        URL(string: "https://evermeet.cx/ffmpeg/getrelease/\(tool)/zip")!
    }

    public static func ytdlpURL() -> URL {
        URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
    }

    /// Static aria2 1.37.0 macOS build (official GitHub releases ship Windows/Android only).
    public static func aria2cURL(arch: String = cpuArchitecture()) -> URL {
        let suffix = arch == "arm64" ? "macos-arm64" : "macos-x64"
        return URL(string: "https://github.com/jingjingxyk/build-static-aria2/releases/download/v1.0.0/aria2c-1.37.0-\(suffix).tar.xz")!
    }

    public func locateExisting() -> BinaryPaths? {
        var candidates: [BinaryPaths] = []
        if let installed = locateInstalled() {
            candidates.append(installed)
        }
        if preferHomebrew, let brew = locateHomebrew() {
            candidates.append(brew)
        }
        return Self.preferNewestYTDLP(among: candidates)
    }

    /// Compare `yt-dlp --version` strings (e.g. `2026.08.19`) and keep the newest.
    public static func preferNewestYTDLP(among candidates: [BinaryPaths]) -> BinaryPaths? {
        guard !candidates.isEmpty else { return nil }
        if candidates.count == 1 { return candidates[0] }
        return candidates.max { a, b in
            compareYTDLPVersions(version(of: a.ytdlp), version(of: b.ytdlp)) == .orderedAscending
        }
    }

    public static func parseYTDLPVersion(_ raw: String) -> [Int] {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let head = trimmed.split(whereSeparator: { $0.isWhitespace || $0 == "\n" }).first.map(String.init) ?? trimmed
        return head.split(separator: ".").compactMap { Int($0) }
    }

    public static func compareYTDLPVersions(_ lhs: [Int], _ rhs: [Int]) -> ComparisonResult {
        let count = max(lhs.count, rhs.count)
        for i in 0..<count {
            let l = i < lhs.count ? lhs[i] : 0
            let r = i < rhs.count ? rhs[i] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func version(of ytdlpPath: String) -> [Int] {
        do {
            let result = try ProcessRunner.run(
                executable: ytdlpPath,
                arguments: ["--version"],
                timeout: 4
            )
            guard !result.timedOut, result.status == 0 else { return [] }
            return parseYTDLPVersion(result.stdout.isEmpty ? result.stderr : result.stdout)
        } catch {
            return []
        }
    }

    public func setup() async throws -> BinaryPaths {
        try FileManager.default.createDirectory(at: binariesDirectory, withIntermediateDirectories: true)

        report("Checking installed / Homebrew binaries...", 0.1)
        if var paths = locateExisting(), quickVersionCheck(paths, timeout: 4) {
            if paths.aria2c == nil {
                report("Downloading aria2c...", 0.5)
                if let aria2c = await installAria2cBestEffort() {
                    paths = BinaryPaths(
                        ytdlp: paths.ytdlp,
                        ffmpeg: paths.ffmpeg,
                        ffprobe: paths.ffprobe,
                        source: paths.source,
                        aria2c: aria2c
                    )
                }
            }
            report(paths.source == .homebrew ? "Using Homebrew binaries" : "Using installed binaries", 1.0)
            return paths
        }

        report("Downloading yt-dlp...", 0.3)
        let ytdlp = try await installYTDLP()

        report("Downloading ffmpeg...", 0.55)
        let ffmpeg = try await installFFmpegTool(named: "ffmpeg")

        report("Downloading ffprobe...", 0.8)
        let ffprobe = try await installFFmpegTool(named: "ffprobe")

        report("Downloading aria2c...", 0.88)
        let aria2c = await installAria2cBestEffort()

        report("Verifying binaries...", 0.95)
        let paths = BinaryPaths(ytdlp: ytdlp, ffmpeg: ffmpeg, ffprobe: ffprobe, source: .downloaded, aria2c: aria2c)
        guard quickVersionCheck(paths, timeout: 8) else {
            throw DownloadError.bootstrapFailed(
                "Downloaded yt-dlp/ffmpeg/ffprobe could not be executed. Check Gatekeeper or try again."
            )
        }

        report("Ready", 1.0)
        return paths
    }

    private func locateHomebrew() -> BinaryPaths? {
        for base in ["/opt/homebrew/bin", "/usr/local/bin"] {
            let ytdlp = "\(base)/yt-dlp"
            let ffmpeg = "\(base)/ffmpeg"
            let ffprobe = "\(base)/ffprobe"
            if FileManager.default.isExecutableFile(atPath: ytdlp),
               FileManager.default.isExecutableFile(atPath: ffmpeg),
               FileManager.default.isExecutableFile(atPath: ffprobe) {
                return BinaryPaths(
                    ytdlp: ytdlp,
                    ffmpeg: ffmpeg,
                    ffprobe: ffprobe,
                    source: .homebrew,
                    aria2c: optionalExecutable("\(base)/aria2c")
                )
            }
        }
        return nil
    }

    private func locateInstalled() -> BinaryPaths? {
        let ytdlp = binariesDirectory.appendingPathComponent("yt-dlp").path
        let ffmpeg = binariesDirectory.appendingPathComponent("ffmpeg").path
        let ffprobe = binariesDirectory.appendingPathComponent("ffprobe").path
        guard FileManager.default.isExecutableFile(atPath: ytdlp),
              FileManager.default.isExecutableFile(atPath: ffmpeg),
              FileManager.default.isExecutableFile(atPath: ffprobe) else {
            return nil
        }
        return BinaryPaths(
            ytdlp: ytdlp,
            ffmpeg: ffmpeg,
            ffprobe: ffprobe,
            source: .installed,
            aria2c: optionalExecutable(binariesDirectory.appendingPathComponent("aria2c").path)
        )
    }

    private func installYTDLP() async throws -> String {
        let destination = binariesDirectory.appendingPathComponent("yt-dlp")
        let temp = try await downloadWithRetry(from: Self.ytdlpURL(), label: "yt-dlp")
        try installExecutable(from: temp, to: destination)
        return destination.path
    }

    private func installFFmpegTool(named tool: String) async throws -> String {
        let destination = binariesDirectory.appendingPathComponent(tool)
        var errors: [String] = []
        let arch = Self.cpuArchitecture()
        let sources: [(String, URL)] = [
            ("evermeet.cx", Self.evermeetURL(tool: tool)),
            ("martin-riedl.de \(arch) release", Self.martinRiedlURL(tool: tool, arch: arch, channel: "release")),
            ("martin-riedl.de \(arch) snapshot", Self.martinRiedlURL(tool: tool, arch: arch, channel: "snapshot"))
        ]

        for (label, url) in sources {
            do {
                report("Downloading \(tool) from \(label)...", tool == "ffmpeg" ? 0.6 : 0.85)
                let downloaded = try await downloadWithRetry(from: url, label: "\(tool) (\(label))")
                let executable = try materializeExecutable(from: downloaded, named: tool)
                try installExecutable(from: executable, to: destination)
                return destination.path
            } catch {
                errors.append("\(label): \(error.localizedDescription)")
            }
        }

        throw DownloadError.bootstrapFailed(
            "Could not download \(tool). Tried evermeet.cx and martin-riedl.de. \(errors.joined(separator: " | "))"
        )
    }

    private func downloadWithRetry(from url: URL, label: String) async throws -> URL {
        var lastError: Error = DownloadError.bootstrapFailed("Download failed: \(label)")
        for attempt in 1...maxAttempts {
            do {
                return try await downloadOnce(from: url, label: label)
            } catch {
                lastError = error
                if attempt < maxAttempts {
                    let delay = pow(2.0, Double(attempt))
                    report("\(label) failed (attempt \(attempt)/\(maxAttempts)), retrying in \(Int(delay))s...", 0.4)
                    try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }
        throw lastError
    }

    private func downloadOnce(from url: URL, label: String) async throws -> URL {
        let (tempURL, response) = try await URLSession.shared.download(from: url)
        if let http = response as? HTTPURLResponse {
            if http.statusCode == 429 || (500...599).contains(http.statusCode) {
                throw DownloadError.bootstrapFailed("\(label): HTTP \(http.statusCode)")
            }
            guard (200...299).contains(http.statusCode) else {
                throw DownloadError.bootstrapFailed("\(label): HTTP \(http.statusCode)")
            }
        }

        let data = try Data(contentsOf: tempURL, options: [.mappedIfSafe])
        let kind = DownloadedFileKind.detect(data: data)
        if kind == .html {
            throw DownloadError.bootstrapFailed("\(label): server returned an HTML error page (rate limited or blocked)")
        }
        if data.count < 1024 {
            throw DownloadError.bootstrapFailed("\(label): download too small (\(data.count) bytes)")
        }
        return tempURL
    }

    private func materializeExecutable(from downloaded: URL, named tool: String) throws -> URL {
        let data = try Data(contentsOf: downloaded, options: [.mappedIfSafe])
        switch DownloadedFileKind.detect(data: data) {
        case .macho:
            return downloaded
        case .zip:
            let extractDir = FileManager.default.temporaryDirectory.appendingPathComponent("ytd-unzip-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
            try unzip(downloaded, to: extractDir)
            if let found = findFile(named: tool, under: extractDir) {
                return found
            }
            throw DownloadError.bootstrapFailed("Zip did not contain \(tool)")
        case .xz:
            let extractDir = FileManager.default.temporaryDirectory.appendingPathComponent("ytd-untar-\(UUID().uuidString)")
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
            try untarXZ(downloaded, to: extractDir)
            if let found = findFile(named: tool, under: extractDir) {
                return found
            }
            throw DownloadError.bootstrapFailed("Archive did not contain \(tool)")
        case .html:
            throw DownloadError.bootstrapFailed("Download was an HTML error page")
        case .unknown:
            throw DownloadError.bootstrapFailed("Downloaded \(tool) was not a zip, xz, or Mach-O binary")
        }
    }

    private func installExecutable(from source: URL, to destination: URL) throws {
        try? FileManager.default.removeItem(at: destination)
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destination.path)
        clearQuarantine(at: destination.path)
    }

    private func optionalExecutable(_ path: String) -> String? {
        FileManager.default.isExecutableFile(atPath: path) ? path : nil
    }

    private func installAria2cBestEffort() async -> String? {
        let destination = binariesDirectory.appendingPathComponent("aria2c")
        if FileManager.default.isExecutableFile(atPath: destination.path),
           runs(destination.path, arguments: ["-v"], timeout: 4) {
            return destination.path
        }
        do {
            let downloaded = try await downloadWithRetry(from: Self.aria2cURL(), label: "aria2c")
            let executable = try materializeExecutable(from: downloaded, named: "aria2c")
            try installExecutable(from: executable, to: destination)
            if runs(destination.path, arguments: ["-v"], timeout: 4) {
                return destination.path
            }
        } catch {
            report("aria2c download skipped: \(error.localizedDescription)", 0.9)
        }
        for base in ["/opt/homebrew/bin", "/usr/local/bin"] {
            if let path = optionalExecutable("\(base)/aria2c") {
                return path
            }
        }
        return nil
    }

    private func unzip(_ zipURL: URL, to destinationURL: URL) throws {
        let result = try ProcessRunner.run(
            executable: "/usr/bin/unzip",
            arguments: ["-o", zipURL.path, "-d", destinationURL.path],
            timeout: 60
        )
        guard !result.timedOut, result.status == 0 else {
            throw DownloadError.bootstrapFailed("Failed to unzip \(zipURL.lastPathComponent)")
        }
    }

    private func untarXZ(_ archiveURL: URL, to destinationURL: URL) throws {
        let result = try ProcessRunner.run(
            executable: "/usr/bin/tar",
            arguments: ["-xJf", archiveURL.path, "-C", destinationURL.path],
            timeout: 60
        )
        guard !result.timedOut, result.status == 0 else {
            throw DownloadError.bootstrapFailed("Failed to extract \(archiveURL.lastPathComponent)")
        }
    }

    private func findFile(named name: String, under directory: URL) -> URL? {
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        while let file = enumerator?.nextObject() as? URL {
            if file.lastPathComponent == name {
                return file
            }
        }
        return directory.appendingPathComponent(name)
    }

    private func clearQuarantine(at path: String) {
        _ = try? ProcessRunner.run(
            executable: "/usr/bin/xattr",
            arguments: ["-dr", "com.apple.quarantine", path],
            timeout: 3
        )
    }

    public func sanityCheck(_ paths: BinaryPaths) -> Bool {
        quickVersionCheck(paths, timeout: 8)
    }

    @discardableResult
    private func quickVersionCheck(_ paths: BinaryPaths, timeout: TimeInterval) -> Bool {
        runs(paths.ytdlp, arguments: ["--version"], timeout: timeout)
            && runs(paths.ffmpeg, arguments: ["-version"], timeout: timeout)
            && runs(paths.ffprobe, arguments: ["-version"], timeout: timeout)
    }

    private func runs(_ executable: String, arguments: [String], timeout: TimeInterval) -> Bool {
        do {
            let result = try ProcessRunner.run(executable: executable, arguments: arguments, timeout: timeout)
            return !result.timedOut && result.status == 0
        } catch {
            return false
        }
    }

    private func report(_ status: String, _ progress: Double) {
        onProgress?(status, progress)
    }
}
