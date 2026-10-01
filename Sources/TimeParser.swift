import Foundation

/// Time zones offered for reading a typed wall-clock time. The saved choice is an IANA identifier,
/// or `localID` to follow the device as it moves between zones.
struct ZoneOption: Identifiable, Hashable {
    let id: String
    let label: String

    static let localID = "local"
    /// Someone who hasn't picked a zone gets their own.
    static let defaultID = localID

    var isLocal: Bool { id == Self.localID }
    var timeZone: TimeZone { isLocal ? .autoupdatingCurrent : TimeZone(identifier: id) ?? .autoupdatingCurrent }

    /// "Times you type use …", without a final period.
    var inputHint: String {
        if isLocal { return "Times you type use your local time (\(Self.city(of: TimeZone.current.identifier)))" }
        if id == "UTC" { return "Times you type use UTC" }
        return "Times you type use \(label) time"
    }

    static var local: ZoneOption { .init(id: localID, label: "Local (\(city(of: TimeZone.current.identifier)))") }

    struct Group: Identifiable {
        let id: String
        let options: [ZoneOption]
    }

    /// The menu, by region. U.S. zones keep their familiar names; elsewhere a city names the zone.
    static var groups: [Group] {
        [
            Group(id: "", options: [local]),
            Group(id: "Americas", options: [
                .init(id: "America/New_York", label: "Eastern"),
                .init(id: "America/Chicago", label: "Central"),
                .init(id: "America/Denver", label: "Mountain"),
                .init(id: "America/Los_Angeles", label: "Pacific"),
                .init(id: "America/Anchorage", label: "Alaska"),
                .init(id: "Pacific/Honolulu", label: "Hawaii"),
                .init(id: "America/Mexico_City", label: "Mexico City"),
                .init(id: "America/Sao_Paulo", label: "São Paulo"),
            ]),
            Group(id: "Europe and Africa", options: [
                .init(id: "Europe/London", label: "London"),
                .init(id: "Europe/Paris", label: "Paris"),
                .init(id: "Europe/Berlin", label: "Berlin"),
                .init(id: "Europe/Istanbul", label: "Istanbul"),
                .init(id: "Africa/Lagos", label: "Lagos"),
                .init(id: "Africa/Johannesburg", label: "Johannesburg"),
            ]),
            Group(id: "Asia and Pacific", options: [
                .init(id: "Asia/Dubai", label: "Dubai"),
                .init(id: "Asia/Kolkata", label: "India"),
                .init(id: "Asia/Singapore", label: "Singapore"),
                .init(id: "Asia/Shanghai", label: "China"),
                .init(id: "Asia/Tokyo", label: "Tokyo"),
                .init(id: "Asia/Seoul", label: "Seoul"),
                .init(id: "Australia/Sydney", label: "Sydney"),
                .init(id: "Pacific/Auckland", label: "Auckland"),
            ]),
            Group(id: "Universal", options: [.init(id: "UTC", label: "UTC")]),
        ]
    }

    /// The saved choice. A real zone that isn't listed keeps working under its city's name;
    /// anything unrecognizable falls back to the device's own zone.
    static func named(_ id: String) -> ZoneOption {
        if let listed = groups.lazy.flatMap(\.options).first(where: { $0.id == id }) { return listed }
        if id != localID, TimeZone(identifier: id) != nil { return .init(id: id, label: city(of: id)) }
        return local
    }

    /// The menu's groups, plus the saved zone when it isn't one of them.
    static func menu(including id: String) -> [Group] {
        let saved = named(id)
        let all = groups
        return all.contains { $0.options.contains { $0.id == saved.id } } ? all : all + [Group(id: "Other", options: [saved])]
    }

    static func choices(including id: String) -> [ZoneOption] { menu(including: id).flatMap(\.options) }

    /// A zone typed by name, as in `magic-time --zone tokyo`.
    static func matching(_ name: String) -> ZoneOption? {
        let wanted = name.lowercased()
        if wanted == localID { return local }
        return groups.lazy.flatMap(\.options).first { $0.label.lowercased() == wanted && !$0.isLocal }
    }

    private static func city(of identifier: String) -> String {
        identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? identifier
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
