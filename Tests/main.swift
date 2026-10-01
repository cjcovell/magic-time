import Foundation

// Compiled together with Sources/TimeParser.swift by build.sh; exits non-zero on failure.

var failures = 0
func expect(_ label: String, _ actual: Date?, _ expected: Date?) {
    if actual == expected {
        print("ok    \(label)")
    } else {
        failures += 1
        print("FAIL  \(label): got \(String(describing: actual)), want \(String(describing: expected))")
    }
}

let eastern = TimeZone(identifier: "America/New_York")!
let pacific = TimeZone(identifier: "America/Los_Angeles")!

func wallClock(_ zone: TimeZone, dayOffset: Int, hour: Int, minute: Int) -> Date {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = zone
    let today = cal.startOfDay(for: .now)
    let day = cal.date(byAdding: .day, value: dayOffset, to: today)!
    return cal.date(bySettingHour: hour, minute: minute, second: 0, of: day)!
}

expect("tomorrow 9:30am (Eastern)", TimeParser.parse("tomorrow 9:30am", in: eastern), wallClock(eastern, dayOffset: 1, hour: 9, minute: 30))
expect("tomorrow 9:30 pm (Eastern)", TimeParser.parse("tomorrow 9:30 pm", in: eastern), wallClock(eastern, dayOffset: 1, hour: 21, minute: 30))
expect("tomorrow 9:30am (Pacific)", TimeParser.parse("tomorrow 9:30am", in: pacific), wallClock(pacific, dayOffset: 1, hour: 9, minute: 30))
expect("unix timestamp", TimeParser.parse("1790947800", in: eastern), Date(timeIntervalSince1970: 1790947800))
expect("existing tag", TimeParser.parse("<t:1790947800:R>", in: eastern), Date(timeIntervalSince1970: 1790947800))
expect("gibberish", TimeParser.parse("banana", in: eastern), nil)
expect("empty", TimeParser.parse("   ", in: eastern), nil)

let sample = Date(timeIntervalSince1970: 1790947800)
print("      F → \(DiscordStyle.longDateTime.code(for: sample))  \(DiscordStyle.longDateTime.preview(for: sample))")
print("      R → \(DiscordStyle.relative.code(for: sample))  \(DiscordStyle.relative.preview(for: sample))")

exit(failures == 0 ? 0 : 1)
