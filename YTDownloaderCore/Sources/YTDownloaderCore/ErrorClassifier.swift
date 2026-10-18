import Foundation

public struct ErrorClassifier {
    public init() {}
    
    /// Classify error from yt-dlp output
    public func classifyError(from output: String) -> DownloadError {
        let lowercased = output.lowercased()

        // Cookie DB / TCC failures before treating as a generic unknown.
        if CookieAccessDiagnoser.looksLikeCookieStorePermissionError(output) {
            return .fullDiskAccessRequired
        }
        
        if containsAny(lowercased, [
            "sign in", "login", "log in", "registered users",
            "войдите", "войти", "авторизуйт", "авторизац", "зарегистрир", "логин"
        ]) {
            return .cookiesRequired
        }

        if containsAny(lowercased, [
            "age-restricted", "age restricted",
            "возраст", "подтвердите возраст"
        ]) {
            return .ageRestricted
        }

        if containsAny(lowercased, [
            "members-only", "members only", "available to members", "join this channel"
        ]) {
            return .membersOnly
        }

        if containsAny(lowercased, [
            "captcha", "confirm you're not a bot", "confirm you are not a bot",
            "капча", "каптча", "не робот"
        ]) {
            return .captchaRequired
        }

        if containsAny(lowercased, ["429", "too many requests", "слишком много запросов", "418"]) {
            return .tooManyRequests
        }

        if containsAny(lowercased, [
            "403", "forbidden", "access denied", "not available in your region",
            "запрещено", "доступ запрещен", "отказано в доступе", "доступ закрыт"
        ]) {
            return .forbidden
        }

        if containsAny(lowercased, [
            "connection", "network", "timed out", "timeout",
            "temporarily unavailable", "временно недоступно",
            "ошибка сети", "ошибка соединения", "нет соединения",
            "таймаут", "истекло время", "не удалось подключиться",
            "ссылка истекла", "url has expired", "expired"
        ]) {
            return .networkError(output)
        }

        if containsAny(lowercased, [
            "no video formats", "no suitable formats",
            "нет подходящих форматов", "форматы не найдены", "нет видеоформат"
        ]) {
            return .noSuitableFormats
        }

        if containsAny(lowercased, [
            "requested format is not available", "format is not available",
            "формат недоступен", "запрошенный формат"
        ]) {
            return .downloadFailed(output)
        }

        if containsAny(lowercased, [
            "live streams and playlists are not supported",
            "playlist", "is a live",
            "прямой эфир", "плейлист не поддерживается"
        ]) && containsAny(lowercased, ["unsupported", "not supported", "не поддержива"]) {
            return .unsupportedMedia
        }

        return .unknown(output)
    }

    private func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}
