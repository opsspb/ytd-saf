import Foundation

/// Spec for the native status-item menu. Titles stay in one place so AppKit
/// and tests cannot drift from the LM Studio-style layout.
public enum StatusMenuSpec {
    public static let showQueue = "Show Queue"
    public static let stopAll = "Stop All"
    public static let settings = "Settings…"
    public static let quit = "Quit YTDownloader"

    public static let actionTitles = [showQueue, stopAll, settings, quit]
}

public struct StatusMenuModel: Equatable, Sendable {
    public let statusLine: String
    public let actions: [String]

    public init(statusLine: String, actions: [String] = StatusMenuSpec.actionTitles) {
        self.statusLine = statusLine
        self.actions = actions
    }

    public static func make(items: [DownloadItem]) -> StatusMenuModel {
        StatusMenuModel(statusLine: MenuBarStatus.line(items: items))
    }
}

/// Disabled first row of the status-item menu.
public enum MenuBarStatus {
    public static func line(items: [DownloadItem]) -> String {
        let outstanding = items.filter { isOutstanding($0.status) }
        guard !outstanding.isEmpty else { return "Idle" }

        let transferring = outstanding.filter { isTransferring($0.status) }
        let current = transferring.first ?? outstanding.first
        let percent = Int(((current?.progress ?? 0) * 100).rounded(.towardZero))

        if transferring.isEmpty {
            if outstanding.contains(where: { $0.status == .retrying }) {
                return outstanding.count == 1
                    ? "Retrying"
                    : "Retrying \(outstanding.count)"
            }
            return outstanding.count == 1
                ? "Queued"
                : "Queued \(outstanding.count)"
        }

        return "Downloading \(transferring.count) of \(outstanding.count) · \(percent)%"
    }

    private static func isOutstanding(_ status: DownloadStatus) -> Bool {
        switch status {
        case .queued, .retrying, .downloading, .merging:
            return true
        case .completed, .failed, .cancelled:
            return false
        }
    }

    private static func isTransferring(_ status: DownloadStatus) -> Bool {
        status == .downloading || status == .merging
    }
}
