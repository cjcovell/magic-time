import Foundation

// Compiled with the parser sources by build.sh; exits non-zero on any failure.
// Everything is pinned to Thursday, October 1, 2026, 12:00 PM Eastern.

var failures = 0
var passes = 0

let eastern = TimeZone(identifier: "America/New_York")!
let pacific = TimeZone(identifier: "America/Los_Angeles")!
var cal = Calendar(identifier: .gregorian)
cal.timeZone = eastern
let now = cal.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12))!

func at(_ y: Int, _ mo: Int, _ d: Int, _ h: Int = 12, _ mi: Int = 0, _ zone: TimeZone = eastern) -> Date {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = zone
    return c.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
}

func check(_ text: String, _ expected: Date?, zone: TimeZone = eastern) {
    let got = TimeParser.parse(text, in: zone, now: now)
    if got == expected {
        passes += 1
    } else {
        failures += 1
        print("FAIL  “\(text)”: got \(got.map { "\($0)" } ?? "nothing"), want \(expected.map { "\($0)" } ?? "nothing")")
    }
}

func checkNote(_ text: String) {
    if case .note = TimeParser.interpret(text, in: eastern, now: now) { passes += 1 }
    else { failures += 1; print("FAIL  “\(text)”: expected an explanatory note") }
}

// MARK: Times and simple days
check("tomorrow 9:30am", at(2026, 10, 2, 9, 30))
check("tomorrow 9:30 pm", at(2026, 10, 2, 21, 30))
check("tomorrow 9:30am", at(2026, 10, 2, 9, 30, pacific), zone: pacific)
check("tmrw 8p", at(2026, 10, 2, 20))
check("fri 2pm", at(2026, 10, 2, 14))
check("6pm", at(2026, 10, 1, 18))
check("8am", at(2026, 10, 2, 8))                       // already past today → tomorrow
check("tonight", at(2026, 10, 1, 20))
check("tonight at 8", at(2026, 10, 1, 20))
check("noon friday", at(2026, 10, 2, 12))
check("midnight friday", at(2026, 10, 3, 0))
check("dinner saturday", at(2026, 10, 3, 19))
check("at 1800 friday", at(2026, 10, 2, 18))
check("half past 6 tomorrow", at(2026, 10, 2, 18, 30))
check("quarter to 7 friday pm", at(2026, 10, 2, 18, 45))
check("friday 6-8pm", at(2026, 10, 2, 18))
check("11-1pm sat", at(2026, 10, 3, 11))
check("raid night fri 8pm", at(2026, 10, 2, 20))
check("we may play fri 8pm", at(2026, 10, 2, 20))
check("Friday, October 2, 2026 at 2:00 PM", at(2026, 10, 2, 14))
check("oct 2nd 2pm", at(2026, 10, 2, 14))

// MARK: Relative
check("in 3 hours", at(2026, 10, 1, 15))
check("in half an hour", at(2026, 10, 1, 12, 30))
check("in 2 weeks at noon", at(2026, 10, 15, 12))
check("3 days from now 5pm", at(2026, 10, 4, 17))
check("this friday", at(2026, 10, 2))
check("next friday 6pm", at(2026, 10, 9, 18))
check("friday after next 6pm", at(2026, 10, 16, 18))
check("the day after tomorrow 10am", at(2026, 10, 3, 10))

// MARK: Calendar dates
check("may 15 6pm", at(2027, 5, 15, 18))
check("15th of may 6pm", at(2027, 5, 15, 18))
check("the 15th 7pm", at(2026, 10, 15, 19))
check("the 15th of next month", at(2026, 11, 15))
check("the 3rd 7pm", at(2026, 10, 3, 19))
check("5/15 6:30", at(2027, 5, 15, 18, 30))
check("5/15/27 6:30pm", at(2027, 5, 15, 18, 30))
check("2027-05-15 18:00", at(2027, 5, 15, 18))
check("friday the 13th 8pm", at(2026, 11, 13, 20))

// MARK: Ordinal weekdays
check("3rd friday in may at 6pm", at(2027, 5, 21, 18))
check("third friday of may 6pm", at(2027, 5, 21, 18))
check("the 3rd friday in may at 6pm", at(2027, 5, 21, 18))
check("last friday in may 6pm", at(2027, 5, 28, 18))
check("first monday of next month 9am", at(2026, 11, 2, 9))
check("2nd tuesday 7pm", at(2026, 10, 13, 19))
check("last friday of the month 8pm", at(2026, 10, 30, 20))
check("3rd friday in may 2028 6pm", at(2028, 5, 19, 18))

// MARK: Time zones in the text
check("6pm pt", at(2026, 10, 1, 18, 0, pacific))
check("fri 8pm eastern time", at(2026, 10, 2, 20))
check("7pm london tomorrow", at(2026, 10, 2, 19, 0, TimeZone(identifier: "Europe/London")!))
check("9am utc", at(2026, 10, 2, 9, 0, TimeZone(identifier: "UTC")!))

// MARK: Holidays — civic and Christian
check("christmas 9am", at(2026, 12, 25, 9))
check("christmas eve 7pm", at(2026, 12, 24, 19))
check("christmas 2030", at(2030, 12, 25))
check("thanksgiving 4pm", at(2026, 11, 26, 16))
check("mother's day 10am", at(2027, 5, 9, 10))
check("easter", at(2027, 3, 28))
check("good friday", at(2027, 3, 26))
check("ash wednesday", at(2027, 2, 10))
check("orthodox easter", at(2027, 5, 2))
check("first sunday of advent", at(2026, 11, 29))

// MARK: Holidays — Chinese, Korean, Vietnamese, Japanese
check("lunar new year 7pm", at(2027, 2, 6, 19))
check("chinese new year", at(2027, 2, 6))
check("spring festival", at(2027, 2, 6))
check("cny eve", at(2027, 2, 5))
check("mid-autumn festival", at(2027, 9, 15))
check("dragon boat festival", at(2027, 6, 9))
check("lantern festival", at(2027, 2, 20))
check("qingming", at(2027, 4, 5))
check("dongzhi", at(2026, 12, 22))
check("setsubun", at(2027, 2, 3))

if #available(macOS 26, *) {                           // Korean and Vietnamese calendars arrived in macOS 26
    check("tết", at(2027, 2, 6))
    check("seollal", at(2027, 2, 7))                  // Seoul's new moon falls a day later in 2027
    check("chuseok", at(2027, 9, 15))
}

// MARK: Holidays — Jewish (first full day; erev = evening before)
check("rosh hashanah", at(2027, 10, 2))
check("yom kippur", at(2027, 10, 11))
check("erev yom kippur 6pm", at(2027, 10, 10, 18))
check("hanukkah", at(2026, 12, 5))
check("erev hanukkah 6pm", at(2026, 12, 4, 18))
check("passover", at(2027, 4, 22))
check("seder 7pm", at(2027, 4, 21, 19))
check("purim", at(2027, 3, 23))
check("shavuot", at(2027, 6, 11))

// MARK: Holidays — Islamic (Umm al-Qura), Persian
check("ramadan", at(2027, 2, 8))
check("eid al-fitr", at(2027, 3, 9))
check("eid ul adha", at(2027, 5, 16))
check("nowruz", at(2027, 3, 21))

// MARK: Known but not datable → an explanation, never a guess
checkNote("eid")
checkNote("vesak")
checkNote("obon")
checkNote("navratri")
checkNote("losar")

// MARK: Diwali and Holi (macOS 26 Indian calendars + Sun/Moon astronomy at New Delhi)
// Reference: Drik Panchang (New Delhi) and Government of India DoPT holiday lists, 2015–2035.
// "a|b" = sources disagree that year, so Magic Time reports both instead of choosing.
if #available(macOS 26, *) {
    check("diwali 7pm", at(2026, 11, 8, 19))
    check("lakshmi puja", at(2026, 11, 8))
    checkNote("holi")                                  // next Holi is 2027: Mar 22 (Drik) or Mar 23 (DoPT)
    checkNote("diwali 2024")                           // Oct 31 (DoPT) or Nov 1 (Drik)
    check("holi 2023", at(2023, 3, 8))
    check("holika dahan 2026", at(2026, 3, 3))

    let reference: [(Int, String, String, String)] = [   // year, Diwali, Holika Dahan, Holi
        (2015, "11-11", "03-05", "03-06"), (2016, "10-30", "03-23", "03-24"), (2017, "10-19", "03-12", "03-13"),
        (2018, "11-07", "03-01", "03-02"), (2019, "10-27", "03-20", "03-21"), (2020, "11-14", "03-09", "03-10"),
        (2021, "11-04", "03-28", "03-29"), (2022, "10-24", "03-17", "03-18"), (2023, "11-12", "03-07", "03-08"),
        (2024, "10-31|11-01", "03-24", "03-25"), (2025, "10-20", "03-13", "03-14"), (2026, "11-08", "03-03", "03-04"),
        (2027, "10-29", "03-21|03-22", "03-22|03-23"), (2028, "10-17", "03-10", "03-11"), (2029, "11-05", "02-28", "03-01"),
        (2030, "10-26", "03-19", "03-20"), (2031, "11-14", "03-08", "03-09"), (2032, "11-02", "03-26", "03-27"),
        (2033, "10-22", "03-15", "03-16"), (2034, "11-10", "03-04", "03-05"), (2035, "10-30", "03-23", "03-24"),
    ]
    // Years where the tithi misses every sunset (Drik Panchang, New Delhi).
    let shortTithi: [(Int, HinduFestivals.Festival, String)] = [
        (2036, .diwali, "10-18"), (2046, .diwali, "10-29"), (2055, .diwali, "10-20"), (2065, .diwali, "10-29"),
        (2074, .diwali, "10-19"), (2075, .diwali, "11-07"), (2098, .diwali, "10-23"), (2099, .diwali, "11-12"),
        (2046, .holikaDahan, "03-21"), (2046, .holi, "03-22"), (2065, .holikaDahan, "03-21"), (2065, .holi, "03-22"),
    ]
    func text(_ o: Observance?) -> String {
        guard let o else { return "none" }
        let one = { (d: CivilDay) in String(format: "%02d-%02d", d.month, d.day) }
        return o.alternative.map { one(o.day) + "|" + one($0) } ?? one(o.day)
    }
    for (year, diwali, dahan, holi) in reference {
        for (festival, want) in [(HinduFestivals.Festival.diwali, diwali), (.holikaDahan, dahan), (.holi, holi)] {
            let got = text(HinduFestivals.observance(festival, gregorianYear: year))
            if got == want { passes += 1 } else { failures += 1; print("FAIL  \(festival) \(year): got \(got), want \(want)") }
        }
    }
    for (year, festival, want) in shortTithi {
        let got = text(HinduFestivals.observance(festival, gregorianYear: year))
        if got == want { passes += 1 } else { failures += 1; print("FAIL  \(festival) \(year): got \(got), want \(want)") }
    }
}

// MARK: Fresh-eyes regressions: never a silent guess
check("raid 15", nil)                                  // a bare number is not 3 PM
check("friday 18", at(2026, 10, 2, 18))                // …but next to a day it's a 24-hour time
check("bring 2 friends", nil)                          // a leading or middle number is not a time either
check("15 raid", nil)
check("top 10 list", nil)
check("need 3 players fri", nil)
check("6 tmrw", at(2026, 10, 2, 18))
check("6 to 8pm fri", at(2026, 10, 2, 18))
check("friday 12", at(2026, 10, 2, 12))                // noon, not the midnight that starts Friday
check("friday at 12", at(2026, 10, 2, 12))
check("dragon boat", at(2027, 6, 9))
check("6 tonight", at(2026, 10, 1, 18))                // a bare hour attached to a day word still works
check("8 morning", at(2026, 10, 2, 8))
check("7 this friday", at(2026, 10, 2, 7))
check("6 on friday", at(2026, 10, 2, 18))
check("fri need 3 players", nil)                       // …but not a number that merely shares the text
check("pt session fri 9am", nil)                       // zone words only count next to a time
check("la fitness fri 8pm", nil)
check("mt hood hike sat 9am", nil)
check("fri 8 pm eastern time", at(2026, 10, 2, 20))
check("PT 8pm fri", at(2026, 10, 2, 20, 0, pacific))
check("new year's eve 2027", at(2027, 12, 31))         // the eve of 2027's holiday is Dec 31, 2027
check("erev rosh hashanah 2027", at(2027, 10, 1))
check("this thursday 8am", nil)                        // already past today; next week isn't "this"
check("this thursday 6pm", at(2026, 10, 1, 18))
check("last friday", nil)                              // previous Friday or last of the month?
check("last friday of the month 8pm", at(2026, 10, 30, 20))
check("advent of code sat 8pm", at(2026, 10, 3, 20))   // not the Advent holiday
check("I lent it fri 8pm", at(2026, 10, 2, 20))
check("india vs pakistan sat 9am", at(2026, 10, 3, 9)) // “india” isn’t a time zone
check("9am mumbai", at(2026, 10, 2, 9, 0, TimeZone(identifier: "Asia/Kolkata")!))
checkNote("festival of lights")
checkNote("independence day")
check("fourth of july 9pm", at(2027, 7, 4, 21))
check("canadian thanksgiving", at(2026, 10, 12))
check("mothering sunday", at(2027, 3, 7))

// MARK: Unknown → nothing
check("banana", nil)
check("blursday", nil)
check("3rd blursday in may", nil)
check("5th friday in november", nil)
check("next", nil)
check("in may", nil)
check("8", nil)
check("   ", nil)

// MARK: Codes and timestamps
check("1790947800", Date(timeIntervalSince1970: 1790947800))
check("<t:1790947800:R>", Date(timeIntervalSince1970: 1790947800))
check("<t:1790947800:S>", Date(timeIntervalSince1970: 1790947800))

// MARK: Long-range stability — every dated holiday, every year through 2100
// Each one must keep resolving, recurring roughly yearly (Islamic ≈ 354 days, lunisolar 354–385).
for (name, rule) in HolidayCatalog.datedRules {
    var previous: CivilDay?
    var gapsOK = true
    for year in 2026...2100 {
        let anchor = at(year, 6, 1)
        let days = rule(anchor)
        guard !days.isEmpty else { gapsOK = false; break }
        for day in days where day.year == year || (previous == nil && day.year == year - 1) {
            if let previous, day > previous {
                let gap = Calendar(identifier: .gregorian).dateComponents([.day],
                    from: at(previous.year, previous.month, previous.day), to: at(day.year, day.month, day.day)).day!
                if !(320...400).contains(gap) { gapsOK = false; print("FAIL  \(name): \(gap)-day gap before \(day)") }
            }
            if previous == nil || day > previous! { previous = day }
        }
    }
    if gapsOK { passes += 1 } else { failures += 1; print("FAIL  \(name) stops resolving or drifts before 2100") }
}
check("orthodox easter 2100", at(2100, 5, 2))         // Julian–Gregorian gap grows to 14 days in 2100

// MARK: Time zone choices

func expect(_ ok: Bool, _ what: String) {
    if ok { passes += 1 } else { failures += 1; print("FAIL  zones: \(what)") }
}
let localCity = TimeZone.current.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? ""
expect(ZoneOption.defaultID == ZoneOption.localID, "the default is the device’s own zone")
expect(ZoneOption.named(ZoneOption.localID).timeZone.identifier == TimeZone.current.identifier, "Local follows the device")
expect(ZoneOption.named(ZoneOption.localID).label == "Local (\(localCity))", "Local names its city")
expect(ZoneOption.named("America/New_York").label == "Eastern", "a saved Eastern choice keeps its name")
expect(ZoneOption.named("Europe/London").label == "London", "London is offered")
expect(ZoneOption.named("Asia/Tokyo").label == "Tokyo", "Tokyo is offered")
expect(ZoneOption.named("Asia/Kolkata").label == "India", "India is offered")
expect(ZoneOption.named("Asia/Kathmandu").label == "Kathmandu", "an unlisted real zone keeps working")
expect(ZoneOption.named("Asia/Kathmandu").timeZone.identifier == "Asia/Kathmandu", "an unlisted zone reads in that zone")
expect(ZoneOption.named("Not/AZone").id == ZoneOption.localID, "an unknown saved value falls back to Local")
expect(ZoneOption.named("UTC").inputHint == "Times you type use UTC", "UTC hint")
expect(ZoneOption.named("Europe/London").inputHint == "Times you type use London time", "city hint")
expect(ZoneOption.named("America/Chicago").inputHint == "Times you type use Central time", "U.S. hint")
expect(ZoneOption.named(ZoneOption.localID).inputHint == "Times you type use your local time (\(localCity))", "Local hint")
expect(ZoneOption.matching("tokyo")?.id == "Asia/Tokyo", "match a city by name")
expect(ZoneOption.matching("Pacific")?.id == "America/Los_Angeles", "match a U.S. zone by name")
expect(ZoneOption.matching("local")?.id == ZoneOption.localID, "match Local by name")
expect(ZoneOption.matching("narnia") == nil, "no match for an unknown name")
expect(ZoneOption.choices(including: "Asia/Kathmandu").contains { $0.id == "Asia/Kathmandu" }, "a saved unlisted zone appears in the menu")
expect(ZoneOption.choices(including: "Europe/London").filter { $0.id == "Europe/London" }.count == 1, "a listed zone isn’t added twice")
let listed = ZoneOption.groups.flatMap(\.options)
expect(Set(listed.map(\.id)).count == listed.count, "no zone is listed twice")
expect(listed.allSatisfy { $0.id == ZoneOption.localID || TimeZone(identifier: $0.id) != nil }, "every listed zone exists")
expect(listed.first?.id == ZoneOption.localID, "Local comes first")

let sample = Date(timeIntervalSince1970: 1790947800)
let letters = DiscordStyle.allCases.map(\.rawValue).sorted().joined()
if letters == "DFRSTdfst" { passes += 1 } else { failures += 1; print("FAIL  styles: \(letters)") }
if DiscordStyle.shortDateShortTime.code(for: sample) == "<t:1790947800:s>" { passes += 1 } else { failures += 1; print("FAIL  s code") }

print(failures == 0 ? "ok    \(passes) parser checks" : "\(failures) of \(passes + failures) parser checks FAILED")
exit(failures == 0 ? 0 : 1)
