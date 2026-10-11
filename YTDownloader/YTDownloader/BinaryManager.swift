import Foundation

@MainActor
class BinaryManager: ObservableObject {
    @Published var isReady = false
    @Published var setupStatus = "Checking binaries..."
    @Published var setupProgress: Double = 0
    
    private let appSupportDir: URL
    private let binariesDir: URL
    
    private var _ytdlpPath: String?
    private var _ffmpegPath: String?
    private var _ffprobePath: String?
    
    init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        appSupportDir = appSupport.appendingPathComponent("YTDownloader")
        binariesDir = appSupportDir.appendingPathComponent("bin")
        
        try? FileManager.default.createDirectory(at: binariesDir, withIntermediateDirectories: true)
    }
    
    func setup() async {
        setupStatus = "Checking for Homebrew binaries..."
        setupProgress = 0.1
        
        if await checkHomebrewBinaries() {
            isReady = true
            setupStatus = "Using Homebrew binaries"
            setupProgress = 1.0
            return
        }
        
        setupStatus = "Checking downloaded binaries..."
        setupProgress = 0.2
        
        if await checkDownloadedBinaries() {
            isReady = true
            setupStatus = "Ready"
            setupProgress = 1.0
            return
        }
        
        setupStatus = "Downloading yt-dlp..."
        setupProgress = 0.3
        
        do {
            try await downloadYTDLP()
            
            setupStatus = "Downloading ffmpeg..."
            setupProgress = 0.6
            
            try await downloadFFmpeg()
            
            setupStatus = "Ready"
            setupProgress = 1.0
            isReady = true
        } catch {
            setupStatus = "Setup failed: \(error.localizedDescription)"
            setupProgress = 0
        }
    }
    
    func ytdlpPath() async -> String? {
        return _ytdlpPath
    }
    
    func ffmpegPath() async -> String? {
        return _ffmpegPath
    }
    
    func ffprobePath() async -> String? {
        return _ffprobePath
    }
    
    private func checkHomebrewBinaries() async -> Bool {
        let homebrewPaths = [
            "/opt/homebrew/bin",
            "/usr/local/bin"
        ]
        
        for basePath in homebrewPaths {
            let ytdlp = "\(basePath)/yt-dlp"
            let ffmpeg = "\(basePath)/ffmpeg"
            let ffprobe = "\(basePath)/ffprobe"
            
            if FileManager.default.fileExists(atPath: ytdlp) &&
               FileManager.default.fileExists(atPath: ffmpeg) &&
               FileManager.default.fileExists(atPath: ffprobe) {
                _ytdlpPath = ytdlp
                _ffmpegPath = ffmpeg
                _ffprobePath = ffprobe
                return true
            }
        }
        
        return false
    }
    
    private func checkDownloadedBinaries() async -> Bool {
        let ytdlp = binariesDir.appendingPathComponent("yt-dlp").path
        let ffmpeg = binariesDir.appendingPathComponent("ffmpeg").path
        let ffprobe = binariesDir.appendingPathComponent("ffprobe").path
        
        guard FileManager.default.fileExists(atPath: ytdlp) &&
              FileManager.default.fileExists(atPath: ffmpeg) &&
              FileManager.default.fileExists(atPath: ffprobe) else {
            return false
        }
        
        _ytdlpPath = ytdlp
        _ffmpegPath = ffmpeg
        _ffprobePath = ffprobe
        
        return true
    }
    
    private func downloadYTDLP() async throws {
        let url = URL(string: "https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos")!
        let destinationURL = binariesDir.appendingPathComponent("yt-dlp")
        
        let (tempURL, _) = try await URLSession.shared.download(from: url)
        
        try? FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: tempURL, to: destinationURL)
        
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destinationURL.path)
        
        _ytdlpPath = destinationURL.path
    }
    
    private func downloadFFmpeg() async throws {
        let arch = getArchitecture()
        let ffmpegURL: URL
        
        if arch == "arm64" {
            ffmpegURL = URL(string: "https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip")!
        } else {
            ffmpegURL = URL(string: "https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip")!
        }
        
        let (tempZipURL, _) = try await URLSession.shared.download(from: ffmpegURL)
        
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        try await unzip(tempZipURL, to: tempDir)
        
        let ffmpegSource = tempDir.appendingPathComponent("ffmpeg")
        let ffmpegDest = binariesDir.appendingPathComponent("ffmpeg")
        
        try? FileManager.default.removeItem(at: ffmpegDest)
        try FileManager.default.moveItem(at: ffmpegSource, to: ffmpegDest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ffmpegDest.path)
        
        _ffmpegPath = ffmpegDest.path
        
        let ffprobeURL: URL
        if arch == "arm64" {
            ffprobeURL = URL(string: "https://evermeet.cx/ffmpeg/getrelease/ffprobe/zip")!
        } else {
            ffprobeURL = URL(string: "https://evermeet.cx/ffmpeg/getrelease/ffprobe/zip")!
        }
        
        let (tempProbeZipURL, _) = try await URLSession.shared.download(from: ffprobeURL)
        let tempProbeDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempProbeDir, withIntermediateDirectories: true)
        
        try await unzip(tempProbeZipURL, to: tempProbeDir)
        
        let ffprobeSource = tempProbeDir.appendingPathComponent("ffprobe")
        let ffprobeDest = binariesDir.appendingPathComponent("ffprobe")
        
        try? FileManager.default.removeItem(at: ffprobeDest)
        try FileManager.default.moveItem(at: ffprobeSource, to: ffprobeDest)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: ffprobeDest.path)
        
        _ffprobePath = ffprobeDest.path
        
        try? FileManager.default.removeItem(at: tempDir)
        try? FileManager.default.removeItem(at: tempProbeDir)
    }
    
    private func unzip(_ zipURL: URL, to destinationURL: URL) async throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-o", zipURL.path, "-d", destinationURL.path]
        
        try process.run()
        process.waitUntilExit()
        
        guard process.terminationStatus == 0 else {
            throw NSError(domain: "BinaryManager", code: 1, userInfo: [NSLocalizedDescriptionKey: "Failed to unzip"])
        }
    }
    
    private func getArchitecture() -> String {
        var systemInfo = utsname()
        uname(&systemInfo)
        let machine = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(validatingUTF8: $0)
            }
        }
        return machine ?? "unknown"
    }
}
