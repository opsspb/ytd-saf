import Foundation

public struct FormatSelector {
    public init() {}
    
    /// Selects the best video and audio formats according to the priority rules:
    /// Video: (a) highest resolution, (b) highest fps, (c) progressive/DASH over HLS, (d) highest video bitrate
    /// Audio: original language track with highest audio bitrate, preferring DASH/https over HLS
    public func selectBestFormats(from info: YTDLPInfo) throws -> SelectedFormats {
        let videoFormats = info.formats.filter { isDownloadableVideo($0) }
        let audioFormats = info.formats.filter { isDownloadableAudio($0) }
        
        guard !videoFormats.isEmpty else {
            throw DownloadError.noSuitableFormats
        }
        
        guard !audioFormats.isEmpty else {
            throw DownloadError.noSuitableFormats
        }
        
        let bestVideo = selectBestVideo(from: videoFormats)
        let bestAudio = selectBestAudio(from: audioFormats)
        
        return SelectedFormats(video: bestVideo, audio: bestAudio)
    }
    
    private func selectBestVideo(from formats: [VideoFormat]) -> VideoFormat {
        let sorted = formats.sorted { format1, format2 in
            let height1 = resolvedHeight(format1)
            let height2 = resolvedHeight(format2)
            
            if height1 != height2 {
                return height1 > height2
            }
            
            let fps1 = format1.fps ?? 0
            let fps2 = format2.fps ?? 0
            
            if fps1 != fps2 {
                return fps1 > fps2
            }

            let proto1 = protocolQuality(format1)
            let proto2 = protocolQuality(format2)
            if proto1 != proto2 {
                return proto1 > proto2
            }
            
            return videoBitrate(format1) > videoBitrate(format2)
        }
        
        return sorted[0]
    }
    
    private func selectBestAudio(from formats: [VideoFormat]) -> VideoFormat {
        let originalLanguageFormats = formats.filter { format in
            if let langPref = format.languagePreference {
                return langPref >= 0
            }
            return true
        }
        
        let formatsToConsider = originalLanguageFormats.isEmpty ? formats : originalLanguageFormats
        
        let sorted = formatsToConsider.sorted { format1, format2 in
            let langPref1 = format1.languagePreference ?? -1
            let langPref2 = format2.languagePreference ?? -1
            
            if langPref1 != langPref2 {
                return langPref1 > langPref2
            }

            let proto1 = protocolQuality(format1)
            let proto2 = protocolQuality(format2)
            if proto1 != proto2 {
                return proto1 > proto2
            }
            
            let abr1 = format1.abr ?? format1.tbr ?? 0
            let abr2 = format2.abr ?? format2.tbr ?? 0
            if abr1 != abr2 {
                return abr1 > abr2
            }

            let drc1 = isDRC(format1)
            let drc2 = isDRC(format2)
            if drc1 != drc2 {
                return !drc1
            }
            return false
        }
        
        return sorted[0]
    }

    private func isDownloadableVideo(_ format: VideoFormat) -> Bool {
        guard format.hasVideo && format.isVideoOnly else { return false }
        guard resolvedHeight(format) > 0 else { return false }
        return isConcreteMedia(format)
    }

    private func isDownloadableAudio(_ format: VideoFormat) -> Bool {
        guard format.hasAudio && format.isAudioOnly else { return false }
        return isConcreteMedia(format)
    }

    private func isConcreteMedia(_ format: VideoFormat) -> Bool {
        let ext = format.ext.lowercased()
        if ext == "mhtml" || ext.hasPrefix("sb") { return false }
        let note = (format.formatNote ?? "").lowercased()
        if note.contains("storyboard") || note.contains("preview") { return false }
        return true
    }

    /// Prefer progressive/DASH (`https`, `http_dash_segments`) over HLS (`m3u8_native`).
    /// HLS often advertises a higher tbr at the same resolution and downloads as mpegts.
    func protocolQuality(_ format: VideoFormat) -> Int {
        let proto = (format.protocolName ?? "").lowercased()
        if proto.contains("m3u8") || proto.contains("hls") {
            return 0
        }
        if proto.contains("dash") || proto == "https" || proto == "http" {
            return 2
        }
        let note = (format.formatNote ?? "").lowercased()
        if note.contains("dash") {
            return 2
        }
        return proto.isEmpty ? 1 : 1
    }

    func resolvedHeight(_ format: VideoFormat) -> Int {
        if let height = format.height, height > 0 {
            return height
        }
        guard let resolution = format.resolution?.lowercased() else { return 0 }
        let parts = resolution.split(separator: "x")
        if parts.count == 2, let height = Int(parts[1]) {
            return height
        }
        if resolution.hasSuffix("p"), let height = Int(resolution.dropLast()) {
            return height
        }
        return 0
    }

    private func videoBitrate(_ format: VideoFormat) -> Double {
        format.vbr ?? format.tbr ?? 0
    }

    private func isDRC(_ format: VideoFormat) -> Bool {
        format.formatId.lowercased().contains("drc")
            || (format.formatNote ?? "").lowercased().contains("drc")
    }
}
