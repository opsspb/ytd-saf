import Foundation
import YTDownloaderCore

@main
struct YTDE2E {
    static func main() async {
        var outputDir = FileManager.default.temporaryDirectory.appendingPathComponent("ytd-e2e-\(UUID().uuidString)").path
        var skipHomebrew = false
        var urls: [String] = []
        var args = Array(CommandLine.arguments.dropFirst())
        while let arg = args.first {
            args.removeFirst()
            if arg == "--output", let dir = args.first {
                outputDir = dir
                args.removeFirst()
            } else if arg == "--skip-homebrew" {
                skipHomebrew = true
            } else if arg.hasPrefix("-") {
                fputs("Unknown flag: \(arg)\n", stderr)
                exit(2)
            } else {
                urls.append(arg)
            }
        }

        setbuf(stdout, nil)
        setbuf(stderr, nil)

        if urls.isEmpty {
            urls = [
                "https://www.youtube.com/watch?v=jNQXAC9IVRw",
                "https://www.youtube.com/watch?v=LXb3EKWsInQ"
            ]
        }

        do {
            try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)
            print("Output: \(outputDir)")

            var bootstrap = BinaryBootstrap(preferHomebrew: !skipHomebrew)
            bootstrap.onProgress = { status, progress in
                print(String(format: "[bootstrap %.0f%%] %@", progress * 100, status))
            }
            let paths = try await bootstrap.setup()
            print("Using binaries from \(paths.source.rawValue)")
            print("  yt-dlp: \(paths.ytdlp)")
            print("  ffmpeg: \(paths.ffmpeg)")
            print("  ffprobe: \(paths.ffprobe)")

            let pipeline = VideoDownloadPipeline(ytdlpPath: paths.ytdlp, ffmpegPath: paths.ffmpeg)
            var failures = 0

            for url in urls {
                print("\n========== \(url) ==========")
                do {
                    let result = try pipeline.downloadBest(url: url, outputDirectory: outputDir)
                    print("Title: \(result.info.title)")
                    print("Chosen video: \(result.formats.video.formatId) \(result.formats.video.resolution ?? "?") \(result.formats.video.fps ?? 0)fps \(result.formats.video.vcodec ?? "")")
                    print("Chosen audio: \(result.formats.audio.formatId) \(result.formats.audio.abr ?? 0)kbps lang=\(result.formats.audio.language ?? "?") pref=\(result.formats.audio.languagePreference.map(String.init) ?? "?") \(result.formats.audio.acodec ?? "")")
                    print("yt-dlp -F:\n\(result.formatList)")
                    print("Output: \(result.outputPath)")
                    try probe(result.outputPath, ffprobe: paths.ffprobe)
                } catch {
                    failures += 1
                    print("FAILED: \(error)")
                }
            }

            if failures > 0 {
                exit(1)
            }
            print("\nAll downloads succeeded.")
        } catch {
            fputs("E2E failed: \(error)\n", stderr)
            exit(1)
        }
    }

    static func probe(_ path: String, ffprobe: String) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: ffprobe)
        process.arguments = [
            "-v", "error",
            "-show_entries", "format=format_name:stream=index,codec_type,codec_name,width,height,r_frame_rate",
            "-of", "json",
            path
        ]
        let out = Pipe()
        let err = Pipe()
        process.standardOutput = out
        process.standardError = err
        try process.run()
        process.waitUntilExit()
        let json = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        print("ffprobe:\n\(json)")
        if !json.contains("matroska") && !json.contains("\"format_name\"") {
            throw DownloadError.mergeFailed("ffprobe did not report a matroska/mkv container")
        }
        if !json.contains("\"codec_type\": \"video\"") || !json.contains("\"codec_type\": \"audio\"") {
            throw DownloadError.mergeFailed("merged file missing video or audio stream")
        }
    }
}
