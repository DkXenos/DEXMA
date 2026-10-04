import Foundation

/// "just now", "5m ago", "2h ago", "3d ago", and when that text will next change, so the
/// Devices tab can update exactly then instead of on a fixed timer. Pure.
nonisolated enum RelativeTime {
    static func text(since date: Date, now: Date) -> String {
        let seconds = max(now.timeIntervalSince(date), 0)
        switch seconds {
        case ..<60: return "just now"
        case ..<3600: return "\(Int(seconds / 60))m ago"
        case ..<86400: return "\(Int(seconds / 3600))h ago"
        default: return "\(Int(seconds / 86400))d ago"
        }
    }

    /// The first moment after `now` at which `text(since: date, now:)` reads differently.
    static func nextChange(since date: Date, now: Date) -> Date {
        let seconds = max(now.timeIntervalSince(date), 0)
        let unit: TimeInterval = switch seconds {
        case ..<3600: 60
        case ..<86400: 3600
        default: 86400
        }
        return date.addingTimeInterval((floor(seconds / unit) + 1) * unit)
    }
}
