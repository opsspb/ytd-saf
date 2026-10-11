import Foundation

public struct ErrorClassifier {
    public init() {}
    
    /// Classify error from yt-dlp output
    public func classifyError(from output: String) -> DownloadError {
        let lowercased = output.lowercased()
        
        if lowercased.contains("sign in") || lowercased.contains("login") {
            return .cookiesRequired
        }
        
        if lowercased.contains("age-restricted") || lowercased.contains("age restricted") {
            return .ageRestricted
        }
        
        if lowercased.contains("members-only") || lowercased.contains("members only") || lowercased.contains("available to members") || lowercased.contains("join this channel") {
            return .membersOnly
        }
        
        if lowercased.contains("captcha") || lowercased.contains("confirm you're not a bot") || lowercased.contains("confirm you are not a bot") {
            return .captchaRequired
        }
        
        if lowercased.contains("403") || lowercased.contains("forbidden") {
            return .forbidden
        }
        
        if lowercased.contains("429") || lowercased.contains("too many requests") {
            return .tooManyRequests
        }
        
        if lowercased.contains("connection") || lowercased.contains("network") || lowercased.contains("timed out") || lowercased.contains("timeout") {
            return .networkError(output)
        }
        
        if lowercased.contains("no video formats") || lowercased.contains("no suitable formats") {
            return .noSuitableFormats
        }
        
        return .unknown(output)
    }
}
