import AppIntents
import UIKit

/// "Make a Discord Timestamp" for Spotlight, Siri, Shortcuts, and the Action button:
/// the iPhone counterpart of the Mac's ⌃⌥⌘T. It copies the code and says what it shows as.
struct MakeTimestampIntent: AppIntent {
    static let title: LocalizedStringResource = "Make a Discord Timestamp"
    static let description = IntentDescription(
        "Turns a time like “fri 8pm PT” or “3rd friday in may at 6pm” into a Discord timestamp code and copies it.")

    @Parameter(title: "Time", requestValueDialog: IntentDialog("What time? For example, “fri 8pm PT”."))
    var phrase: String

    @Parameter(title: "Format", default: .fullDateShortTime)
    var format: TimestampFormat

    @Parameter(title: "Time Zone", description: "Used unless the time names its own zone.")
    var zone: TimeZoneChoice?

    static var parameterSummary: some ParameterSummary {
        Summary("Make a \(\.$format) timestamp for \(\.$phrase)") {
            \.$zone
        }
    }

    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let zoneID = zone?.rawValue ?? UserDefaults.standard.string(forKey: "zone") ?? ZoneOption.all[0].id
        let style = format.style
        switch TimeParser.interpret(phrase, in: ZoneOption.named(zoneID).timeZone) {
        case .moment(let date):
            let code = style.code(for: date)
            await MainActor.run { UIPasteboard.general.string = code }
            return .result(value: code, dialog: IntentDialog("Copied \(code). It shows as \(style.preview(for: date))."))
        case .note(let why):
            throw TimestampIntentError.wontGuess(why)
        case .nothing:
            throw TimestampIntentError.noTime(phrase)
        }
    }
}

enum TimestampIntentError: Error, CustomLocalizedStringResourceConvertible {
    case wontGuess(String)
    case noTime(String)

    var localizedStringResource: LocalizedStringResource {
        switch self {
        case .wontGuess(let why): "\(why)"
        case .noTime(let phrase): "No date or time found in “\(phrase)”. Try “tomorrow 9:30am” or “fri 8pm PT”."
        }
    }
}

enum TimestampFormat: String, AppEnum {
    case fullDateShortTime = "F", longDateShortTime = "f", shortDateShortTime = "s", shortTime = "t"
    case relative = "R", longDate = "D", shortDate = "d", mediumTime = "T", shortDateMediumTime = "S"

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Format"
    static let caseDisplayRepresentations: [TimestampFormat: DisplayRepresentation] = [
        .fullDateShortTime: "Full date and time",
        .longDateShortTime: "Date and time",
        .shortDateShortTime: "Short date and time",
        .shortTime: "Time",
        .relative: "Countdown",
        .longDate: "Date",
        .shortDate: "Short date",
        .mediumTime: "Time with seconds",
        .shortDateMediumTime: "Short date, time with seconds",
    ]

    var style: DiscordStyle { DiscordStyle(rawValue: rawValue)! }
}

enum TimeZoneChoice: String, AppEnum {
    case eastern = "America/New_York", central = "America/Chicago", mountain = "America/Denver"
    case pacific = "America/Los_Angeles", utc = "UTC"

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Time Zone"
    static let caseDisplayRepresentations: [TimeZoneChoice: DisplayRepresentation] = [
        .eastern: "Eastern", .central: "Central", .mountain: "Mountain", .pacific: "Pacific", .utc: "UTC",
    ]
}

struct MagicTimeShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: MakeTimestampIntent(),
            phrases: [
                "Make a Discord timestamp with \(.applicationName)",
                "Get a timestamp from \(.applicationName)",
                "\(.applicationName) for Discord",
            ],
            shortTitle: "Discord Timestamp",
            systemImageName: "clock"
        )
    }
}
