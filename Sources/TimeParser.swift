import Foundation

/// Time zones offered for reading a typed wall-clock time.
struct ZoneOption: Identifiable, Hashable {
    let id: String
    let label: String

    var timeZone: TimeZone { TimeZone(identifier: id) ?? .current }

    static let all: [ZoneOption] = [
        .init(id: "America/New_York", label: "Eastern"),
        .init(id: "America/Chicago", label: "Central"),
        .init(id: "America/Denver", label: "Mountain"),
        .init(id: "America/Los_Angeles", label: "Pacific"),
        .init(id: "UTC", label: "UTC"),
    ]

    static func named(_ id: String) -> ZoneOption {
        all.first { $0.id == id } ?? all[0]
    }
}

enum TimeParser {
    private static let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue)

    /// Reads free text — "tomorrow 9:30am", "fri 2pm", "10/14 7pm", a Unix timestamp,
    /// or an existing `<t:…>` tag — as a moment. Wall-clock times are read in `zone`
    /// unless the text names its own zone.
    static func parse(_ text: String, in zone: TimeZone) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let tag = trimmed.firstMatch(of: #/<t:(-?\d+)(?::[tTdDfFR])?>/#), let seconds = Int(tag.1) {
            return Date(timeIntervalSince1970: TimeInterval(seconds))
        }
        if trimmed.count >= 9, let seconds = Int(trimmed) {
            return Date(timeIntervalSince1970: TimeInterval(seconds))
        }

        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard let match = detector?.firstMatch(in: trimmed, range: range), let found = match.date else {
            return nil
        }

        var date = found
        // The detector reads times in the Mac's own zone; re-read the same wall clock in `zone`.
        if match.timeZone == nil, zone.identifier != TimeZone.current.identifier {
            var local = Calendar(identifier: .gregorian)
            local.timeZone = .current
            let parts = local.dateComponents([.year, .month, .day, .hour, .minute], from: found)
            var target = local
            target.timeZone = zone
            date = target.date(from: parts) ?? found
        }
        return floorToMinute(date)
    }

    static func floorToMinute(_ date: Date) -> Date {
        let seconds = date.timeIntervalSince1970
        return Date(timeIntervalSince1970: (seconds / 60).rounded(.down) * 60)
    }
}

/// Discord's `<t:unix:style>` timestamp styles, in the order the panel lists them (⌘1–⌘9).
/// Names follow Discord's developer docs; `f` is the style Discord uses when none is given.
enum DiscordStyle: String, CaseIterable, Identifiable {
    case fullDateShortTime = "F"
    case longDateShortTime = "f"
    case shortDateShortTime = "s"
    case shortTime = "t"
    case relative = "R"
    case longDate = "D"
    case shortDate = "d"
    case mediumTime = "T"
    case shortDateMediumTime = "S"

    var id: String { rawValue }

    var name: String {
        switch self {
        case .fullDateShortTime: "Full date, short time"
        case .longDateShortTime: "Long date, short time (default)"
        case .shortDateShortTime: "Short date, short time"
        case .shortTime: "Short time"
        case .relative: "Relative time"
        case .longDate: "Long date"
        case .shortDate: "Short date"
        case .mediumTime: "Medium time"
        case .shortDateMediumTime: "Short date, medium time"
        }
    }

    func code(for date: Date) -> String {
        "<t:\(Int(date.timeIntervalSince1970)):\(rawValue)>"
    }

    /// Roughly what Discord renders for a viewer in this Mac's time zone.
    func preview(for date: Date, now: Date = .now) -> String {
        switch self {
        case .fullDateShortTime:
            date.formatted(.dateTime.weekday(.wide).month(.wide).day().year().hour().minute())
        case .longDateShortTime:
            date.formatted(date: .long, time: .shortened)
        case .shortDateShortTime:
            date.formatted(date: .numeric, time: .shortened)
        case .shortTime:
            date.formatted(date: .omitted, time: .shortened)
        case .relative:
            abs(date.timeIntervalSince(now)) < 60
                ? "now"
                : Self.relativeFormatter.localizedString(for: date, relativeTo: now)
        case .longDate:
            date.formatted(date: .long, time: .omitted)
        case .shortDate:
            date.formatted(date: .numeric, time: .omitted)
        case .mediumTime:
            date.formatted(date: .omitted, time: .standard)
        case .shortDateMediumTime:
            date.formatted(date: .numeric, time: .standard)
        }
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}
