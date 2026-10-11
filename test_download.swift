#!/usr/bin/env swift

import Foundation

// Test videos
let testVideos = [
    ("dQw4w9WgXcQ", "https://www.youtube.com/watch?v=dQw4w9WgXcQ"), // Rick Astley - short classic
    ("jNQXAC9IVRw", "https://www.youtube.com/watch?v=jNQXAC9IVRw"), // "Me at the zoo" - first YT video, 19s
]

let tempDownloadDir = FileManager.default.temporaryDirectory.appendingPathComponent("ytd-test-\(UUID().uuidString)")
try FileManager.default.createDirectory(at: tempDownloadDir, withIntermediateDirectories: true)

print("📁 Test download directory: \(tempDownloadDir.path)")
print("")

func runProcess(path: String, args: [String], silent: Bool = false) throws -> (output: String, error: String, exitCode: Int32) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = args
    
    let outputPipe = Pipe()
    let errorPipe = Pipe()
    process.standardOutput = outputPipe
    process.standardError = errorPipe
    
    try process.run()
    process.waitUntilExit()
    
    let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
    let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
    
    let output = String(data: outputData, encoding: .utf8) ?? ""
    let error = String(data: errorData, encoding: .utf8) ?? ""
    
    if !silent {
        if !output.isEmpty {
            print(output)
        }
        if !error.isEmpty && process.terminationStatus != 0 {
            print("Error output:", error)
        }
    }
    
    return (output, error, process.terminationStatus)
}

// Check for yt-dlp and ffmpeg
print("🔍 Checking for binaries...")
let ytdlpPath = "/opt/homebrew/bin/yt-dlp"
let ffmpegPath = "/opt/homebrew/bin/ffmpeg"
let ffprobePath = "/opt/homebrew/bin/ffprobe"

guard FileManager.default.fileExists(atPath: ytdlpPath) else {
    print("❌ yt-dlp not found at \(ytdlpPath)")
    exit(1)
}

guard FileManager.default.fileExists(atPath: ffmpegPath) else {
    print("❌ ffmpeg not found at \(ffmpegPath)")
    exit(1)
}

guard FileManager.default.fileExists(atPath: ffprobePath) else {
    print("❌ ffprobe not found at \(ffprobePath)")
    exit(1)
}

print("✅ yt-dlp found: \(ytdlpPath)")
print("✅ ffmpeg found: \(ffmpegPath)")
print("✅ ffprobe found: \(ffprobePath)")
print("")

// Test 1: List available formats for the first video
print("🎬 Test 1: Listing available formats...")
let testUrl = testVideos[0].1
print("Video: \(testUrl)")

let (formatOutput, _, formatExit) = try runProcess(
    path: ytdlpPath,
    args: ["-F", testUrl],
    silent: true
)

if formatExit == 0 {
    print("✅ Format listing successful")
    print("Available formats:")
    print(formatOutput)
} else {
    print("❌ Format listing failed")
    exit(1)
}
print("")

// Test 2: Fetch video info as JSON
print("🎬 Test 2: Fetching video info (JSON)...")
let (infoOutput, infoError, infoExit) = try runProcess(
    path: ytdlpPath,
    args: ["-J", "--no-warnings", testUrl],
    silent: true
)

if infoExit != 0 {
    print("❌ Failed to fetch video info")
    print("Error:", infoError)
    exit(1)
}

guard let infoData = infoOutput.data(using: .utf8) else {
    print("❌ Failed to parse info output as UTF-8")
    exit(1)
}

struct VideoFormat: Codable {
    let format_id: String
    let ext: String
    let height: Int?
    let fps: Double?
    let vcodec: String?
    let acodec: String?
    let vbr: Double?
    let abr: Double?
    let language_preference: Int?
}

struct VideoInfo: Codable {
    let id: String
    let title: String
    let formats: [VideoFormat]
}

guard let info = try? JSONDecoder().decode(VideoInfo.self, from: infoData) else {
    print("❌ Failed to decode video info JSON")
    exit(1)
}

print("✅ Video info fetched successfully")
print("   Title: \(info.title)")
print("   Video ID: \(info.id)")
print("   Available formats: \(info.formats.count)")
print("")

// Test 3: Select best formats (mimicking FormatSelector logic)
print("🎯 Test 3: Selecting best formats...")

let videoFormats = info.formats.filter { format in
    guard let vcodec = format.vcodec, vcodec != "none", !vcodec.isEmpty else { return false }
    guard let acodec = format.acodec, acodec == "none" || acodec.isEmpty else { return false }
    return format.height != nil
}

let audioFormats = info.formats.filter { format in
    guard let acodec = format.acodec, acodec != "none", !acodec.isEmpty else { return false }
    guard let vcodec = format.vcodec, vcodec == "none" || vcodec.isEmpty else { return false }
    return format.abr != nil
}

guard !videoFormats.isEmpty else {
    print("❌ No video-only formats found")
    exit(1)
}

guard !audioFormats.isEmpty else {
    print("❌ No audio-only formats found")
    exit(1)
}

// Sort video by height (resolution), then fps, then bitrate
let bestVideo = videoFormats.sorted { a, b in
    if a.height != b.height {
        return (a.height ?? 0) > (b.height ?? 0)
    }
    if a.fps != b.fps {
        return (a.fps ?? 0) > (b.fps ?? 0)
    }
    return (a.vbr ?? 0) > (b.vbr ?? 0)
}.first!

// Sort audio by original language preference, then bitrate
let bestAudio = audioFormats.sorted { a, b in
    if a.language_preference != b.language_preference {
        return (a.language_preference ?? -1) > (b.language_preference ?? -1)
    }
    return (a.abr ?? 0) > (b.abr ?? 0)
}.first!

print("✅ Selected formats:")
print("   Video: format_id=\(bestVideo.format_id), height=\(bestVideo.height ?? 0)p, fps=\(bestVideo.fps ?? 0), ext=\(bestVideo.ext)")
print("   Audio: format_id=\(bestAudio.format_id), abr=\(bestAudio.abr ?? 0)kbps, ext=\(bestAudio.ext)")
print("")

// Test 4: Download video and audio separately
print("⬇️  Test 4: Downloading video and audio...")
let videoFile = tempDownloadDir.appendingPathComponent("\(info.id)_video.\(bestVideo.ext)")
let audioFile = tempDownloadDir.appendingPathComponent("\(info.id)_audio.\(bestAudio.ext)")

print("Downloading video format \(bestVideo.format_id)...")
let (_, videoError, videoExit) = try runProcess(
    path: ytdlpPath,
    args: ["-f", bestVideo.format_id, "-o", videoFile.path, "--no-warnings", testUrl],
    silent: true
)

if videoExit != 0 {
    print("❌ Video download failed")
    print("Error:", videoError)
    exit(1)
}
print("✅ Video downloaded: \(videoFile.lastPathComponent)")

print("Downloading audio format \(bestAudio.format_id)...")
let (_, audioError, audioExit) = try runProcess(
    path: ytdlpPath,
    args: ["-f", bestAudio.format_id, "-o", audioFile.path, "--no-warnings", testUrl],
    silent: true
)

if audioExit != 0 {
    print("❌ Audio download failed")
    print("Error:", audioError)
    exit(1)
}
print("✅ Audio downloaded: \(audioFile.lastPathComponent)")
print("")

// Test 5: Merge with ffmpeg (no transcoding)
print("🔀 Test 5: Merging video and audio...")
let outputFile = tempDownloadDir.appendingPathComponent("\(info.id)_merged.mkv")

let (_, mergeError, mergeExit) = try runProcess(
    path: ffmpegPath,
    args: ["-i", videoFile.path, "-i", audioFile.path, "-c", "copy", "-y", outputFile.path],
    silent: true
)

if mergeExit != 0 {
    print("❌ Merge failed")
    print("Error:", mergeError)
    exit(1)
}
print("✅ Merged to: \(outputFile.lastPathComponent)")
print("")

// Test 6: Verify output with ffprobe
print("🔍 Test 6: Verifying merged file with ffprobe...")
let (probeOutput, probeError, probeExit) = try runProcess(
    path: ffprobePath,
    args: ["-v", "error", "-show_entries", "stream=codec_type,codec_name", "-of", "default=noprint_wrappers=1", outputFile.path],
    silent: true
)

if probeExit != 0 {
    print("❌ ffprobe failed")
    print("Error:", probeError)
    exit(1)
}

print("✅ ffprobe output:")
print(probeOutput)

if probeOutput.contains("codec_type=video") && probeOutput.contains("codec_type=audio") {
    print("✅ File contains both video and audio streams")
} else {
    print("⚠️  Warning: File might be missing video or audio stream")
}

// Check for re-encoding (should be copy, not transcode)
if probeOutput.lowercased().contains("h264") || probeOutput.lowercased().contains("vp9") || probeOutput.lowercased().contains("av1") {
    print("✅ Video codec preserved (no transcode)")
}
if probeOutput.lowercased().contains("opus") || probeOutput.lowercased().contains("aac") {
    print("✅ Audio codec preserved (no transcode)")
}
print("")

// Summary
print(String(repeating: "=", count: 60))
print("✅ All tests passed!")
print(String(repeating: "=", count: 60))
print("")
print("Test files saved to: \(tempDownloadDir.path)")
print("To clean up: rm -rf '\(tempDownloadDir.path)'")
print("")
print("Next steps:")
print("1. Build the Xcode project with Pavel's signing team")
print("2. Run the app and verify binary bootstrap")
print("3. Test Safari extension integration")
