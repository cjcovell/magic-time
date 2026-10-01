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

/// What a piece of text means: a moment, a reason we won't pick one, or nothing recognizable.
enum Reading: Equatable {
    case moment(Date)
    case note(String)
    case nothing

    var date: Date? { if case .moment(let d) = self { d } else { nil } }
}

enum TimeParser {
    /// Reads free text — "tomorrow 9:30am", "3rd friday in may 6pm", "lunar new year 7pm PT",
    /// a Unix timestamp, or an existing `<t:…>` tag. Wall-clock times are read in `zone` unless
    /// the text names its own. Never guesses: anything it can't fully account for is `.nothing`.
    static func interpret(_ text: String, in zone: TimeZone, now: Date = .now) -> Reading {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .nothing }

        if let tag = trimmed.firstMatch(of: #/<t:(-?\d+)(?::[tTdDfFsSR])?>/#), let seconds = Int(tag.1) {
            return .moment(Date(timeIntervalSince1970: TimeInterval(seconds)))
        }
        if trimmed.count >= 9, let seconds = Int(trimmed) {
            return .moment(Date(timeIntervalSince1970: TimeInterval(seconds)))
        }

        switch NaturalTime(zone: zone, now: now).parse(trimmed) {
        case .moment(let date): return .moment(floorToMinute(date))
        case let other: return other
        }
    }

    static func parse(_ text: String, in zone: TimeZone, now: Date = .now) -> Date? {
        interpret(text, in: zone, now: now).date
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
