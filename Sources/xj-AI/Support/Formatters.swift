import Foundation

enum TimeFormatters {
    static func clock(_ interval: TimeInterval) -> String {
        let seconds = max(0, Int(interval.rounded(.down)))
        return String(format: "%02d:%02d:%02d", seconds / 3600, (seconds / 60) % 60, seconds % 60)
    }

    static func subtitle(_ interval: TimeInterval, separator: Character = ",") -> String {
        let milliseconds = max(0, Int((interval * 1000).rounded()))
        return String(
            format: "%02d:%02d:%02d%c%03d",
            milliseconds / 3_600_000,
            (milliseconds / 60_000) % 60,
            (milliseconds / 1_000) % 60,
            String(separator).utf8.first ?? 44,
            milliseconds % 1_000
        )
    }
}

extension Date {
    var xjShortStamp: String {
        formatted(.dateTime.month(.abbreviated).day().hour().minute())
    }
}
