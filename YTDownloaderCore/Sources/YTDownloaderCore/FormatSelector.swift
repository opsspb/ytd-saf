import Foundation

public struct FormatSelector {
    public init() {}
    
    /// Selects the best video and audio formats according to the priority rules:
    /// Video: (a) highest resolution, (b) highest fps, (c) highest video bitrate
    /// Audio: original language track with highest audio bitrate
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
            let height1 = format1.height ?? 0
            let height2 = format2.height ?? 0
            
            if height1 != height2 {
                return height1 > height2
            }
            
            let fps1 = format1.fps ?? 0
            let fps2 = format2.fps ?? 0
            
            if fps1 != fps2 {
                return fps1 > fps2
            }
            
            let vbr1 = format1.vbr ?? format1.tbr ?? 0
            let vbr2 = format2.vbr ?? format2.tbr ?? 0
            
            return vbr1 > vbr2
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
            
            let abr1 = format1.abr ?? format1.tbr ?? 0
            let abr2 = format2.abr ?? format2.tbr ?? 0
            
            return abr1 > abr2
        }
        
        return sorted[0]
    }

    private func isDownloadableVideo(_ format: VideoFormat) -> Bool {
        guard format.hasVideo && format.isVideoOnly else { return false }
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
}
