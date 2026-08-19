import Foundation

nonisolated enum ServerDateParser {
    static func date(from value: String?) -> Date? {
        guard let value else {
            return nil
        }

        return fractionalISO8601DateFormatter.date(from: value)
            ?? iso8601DateFormatter.date(from: value)
            ?? dateWithoutTimeZone(from: value)
    }
}

private extension ServerDateParser {
    static let iso8601DateFormatter = ISO8601DateFormatter()

    static let fractionalISO8601DateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    static func dateWithoutTimeZone(from value: String) -> Date? {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)

        for format in [
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS",
            "yyyy-MM-dd'T'HH:mm:ss.SSS",
            "yyyy-MM-dd'T'HH:mm:ss"
        ] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }

        return nil
    }
}
