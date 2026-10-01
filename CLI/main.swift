import Foundation

// magic-time: the Magic Time parser on the command line.
//
//   magic-time "3rd friday in may at 6pm"
//   magic-time "lunar new year 7pm" --zone pacific
//   magic-time "fri 8pm PT" --format t
//   magic-time "diwali" --json
//
// Exit status: 0 = a moment was found, 2 = a known date Magic Time won't guess (a note is
// printed), 1 = no date or time found, 64 = usage error.

let usage = """
    usage: magic-time <text> [--zone local|eastern|pacific|london|tokyo|…|utc|<IANA id>] [--format F|f|s|t|R|D|d|T|S] [--json]

      Turns plain English ("tomorrow 9:30am", "3rd friday in may 6pm", "lunar new year 7pm PT")
      into Discord timestamp codes. Times are read in --zone unless the text names its own zone;
      the default is the zone chosen in the Magic Time app (this Mac’s own zone if none).
    """

var words: [String] = []
var zoneArgument: String?
var formatArgument: String?
var json = false

var arguments = CommandLine.arguments.dropFirst().makeIterator()
while let argument = arguments.next() {
    switch argument {
    case "--zone", "-z": zoneArgument = arguments.next()
    case "--format", "-f": formatArgument = arguments.next()
    case "--json": json = true
    case "--help", "-h": print(usage); exit(0)
    default: words.append(argument)
    }
}

let text = words.joined(separator: " ")
guard !text.trimmingCharacters(in: .whitespaces).isEmpty else {
    FileHandle.standardError.write(Data((usage + "\n").utf8))
    exit(64)
}

func resolveZone(_ argument: String?) -> TimeZone? {
    let saved = UserDefaults(suiteName: "cc.covell.magictime")?.string(forKey: "zone")
    guard let argument else { return ZoneOption.named(saved ?? ZoneOption.defaultID).timeZone }
    if let option = ZoneOption.matching(argument) { return option.timeZone }
    return TimeZone(identifier: argument) ?? TimeZone(abbreviation: argument.uppercased())
}

guard let zone = resolveZone(zoneArgument) else {
    FileHandle.standardError.write(Data("magic-time: unknown time zone “\(zoneArgument ?? "")”\n".utf8))
    exit(64)
}

var styles = DiscordStyle.allCases
if let formatArgument {
    guard let style = DiscordStyle(rawValue: formatArgument) else {
        FileHandle.standardError.write(Data("magic-time: unknown format “\(formatArgument)” (use F f s t R D d T S)\n".utf8))
        exit(64)
    }
    styles = [style]
}

func emit(_ object: [String: Any]) {
    let data = try! JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    print(String(decoding: data, as: UTF8.self))
}

switch TimeParser.interpret(text, in: zone) {
case .moment(let date):
    let unix = Int(date.timeIntervalSince1970)
    let reading = date.formatted(.dateTime.weekday(.wide).month(.wide).day().year().hour().minute().timeZone()
        .locale(Locale(identifier: "en_US")))
    if json {
        emit([
            "status": "moment",
            "input": text,
            "unix": unix,
            "readAs": reading,
            "zone": zone.identifier,
            "codes": styles.map { ["format": $0.rawValue, "name": $0.name, "code": $0.code(for: date), "preview": $0.preview(for: date)] },
        ])
    } else {
        print("Read as \(reading) (\(zone.identifier) unless the text named a zone)")
        print("Unix \(unix)")
        for style in styles {
            print("\(style.code(for: date))  \(style.preview(for: date))  [\(style.name)]")
        }
    }
    exit(0)
case .note(let note):
    if json { emit(["status": "note", "input": text, "note": note]) } else { print("Won’t guess: \(note)") }
    exit(2)
case .nothing:
    if json { emit(["status": "nothing", "input": text]) } else { print("No date or time found in “\(text)”.") }
    exit(1)
}
