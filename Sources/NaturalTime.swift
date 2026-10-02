import Foundation

/// A natural-language reader for a single moment: "3rd friday in may at 6pm",
/// "tmrw 8p PT", "thanksgiving 4pm", "in 2 hours", "friday after next", "5/15 6:30".
///
/// It reads the text token by token. Words it doesn't know are skipped (so event titles like
/// "raid night fri 8pm" work), but a leftover number, ordinal, month, or weekday makes the whole
/// parse fail — a wrong date is worse than no date.
struct NaturalTime {
    let zone: TimeZone
    let now: Date

    init(zone: TimeZone, now: Date = .now) {
        self.zone = zone
        self.now = now
    }

    func parse(_ text: String) -> Reading { read(text).reading }

    /// The reading, plus the zone the text asked to see it in: the one it named ("london noon"),
    /// or the one it converted to ("3pm london in tokyo"). `nil` when the text named no zone.
    func read(_ text: String) -> (reading: Reading, shownIn: TimeZone?) {
        var reader = Reader(tokens: Self.tokenize(text), zone: zone, now: now)
        let reading = reader.read()
        return (reading, reading.date == nil ? nil : reader.shownZone)
    }

    /// The zones a text names, as identifiers, so "pacific" and "pt" count as the same one.
    static func zones(in text: String) -> Set<String> {
        Set(tokenize(text).compactMap { Vocabulary.timeZones[$0] })
    }

    /// The words that fix a text's date, in one spelling each ("sat" and "saturday" are the same
    /// weekday; "3rd" and "third" the same ordinal). Two texts that mean the same day have the
    /// same set; a rewrite that drops "next", "third", "may", or "christmas" does not.
    static func dateWords(in text: String) -> Set<String> {
        let shifts: Set<String> = [
            "today", "tonight", "yesterday", "next", "after", "before", "last", "following", "from", "other",
            "every", "ago", "week", "weeks", "weekend", "month", "months", "year", "years", "day", "days", "now",
        ]
        let genericHolidayWords: Set<String> = ["day", "night", "new", "the", "of", "al", "el", "st", "first", "last"]
        var found = Set<String>()
        for raw in tokenize(text) {
            let token = raw == "tonite" ? "tonight" : HolidayCatalog.normalize(raw)
            if let weekday = Vocabulary.weekdays[token] ?? Vocabulary.weekdays[String(token.dropLast())].flatMap({ token.hasSuffix("s") ? $0 : nil }) {
                found.insert("weekday \(weekday)")
            } else if let month = Vocabulary.months[token] {
                found.insert("month \(month)")
            } else if let nth = Vocabulary.weekdayOrdinal(token), nth > 0 {
                found.insert("nth \(nth)")
            } else if let m = token.firstMatch(of: #/^(\d{1,2})(st|nd|rd|th)$/#) {
                found.insert("nth \(Int(m.1)!)")
            } else if Vocabulary.isTomorrow(token) {
                found.insert("tomorrow")
            } else if shifts.contains(token) {
                found.insert(token)
            } else if Vocabulary.timeZones[token] == nil, HolidayCatalog.nameWords.contains(token), !genericHolidayWords.contains(token),
                      !Vocabulary.fillers.contains(token) {
                found.insert("holiday \(token)")
            }
        }
        return found
    }

    /// Whether a word in a rewrite is one the reader knows on its own: a time, a zone, a date word.
    static func isKnownWord(_ token: String) -> Bool {
        Vocabulary.isClockWord(token) || Clock.parse(token, allowMilitary: false) != nil || Vocabulary.timeZones[token] != nil
            || Vocabulary.fillers.contains(token) || !dateWords(in: token).isEmpty
    }

    static func tokenize(_ text: String) -> [String] {
        var s = text.lowercased().folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US"))
        for (from, to) in [("a.m.", "am"), ("p.m.", "pm"), ("’", "'"), ("–", "-"), ("—", "-")] {
            s = s.replacingOccurrences(of: from, with: to)
        }
        // Split ranges like "6-8pm" into "6 - 8pm"; leave ISO dates (2027-05-15) and m-d alone.
        s = s.replacing(#/(\d(?::\d\d)?\s*(?:am|pm|a|p)?)-(\d{1,2}(?::\d\d)?\s*(?:am|pm|a|p))\b/#) { m in
            "\(m.1) - \(m.2)"
        }
        let separators = CharacterSet(charactersIn: " ,;@()\t\n")
        return s.components(separatedBy: separators)
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ".!?")) }
            .filter { !$0.isEmpty }
    }
}

// MARK: - Reader

private struct Reader {
    let tokens: [String]
    let zone: TimeZone
    let now: Date

    private var i = 0
    private var failed = false
    private var note: String?                          // a holiday we know but won't date

    // What the text said.
    private var zoneOverride: TimeZone?
    private var displayZone: TimeZone?                 // "3pm london in tokyo": show it in Tokyo
    private var instant: Date?                         // "in 3 hours"
    private var day: DayComponents?                    // a calendar day, possibly needing a year
    private var dayIsBareWeekday = false               // "friday": roll a week if already past
    private var weekdayCheck: Int?                     // "fri, may 15": must agree with the date
    private var clock: Clock?                          // an explicit time of day
    private var defaultClock: Clock?                   // from "morning", "dinner", "tonight"
    private var meridiemHint: Meridiem?
    private var addDayForMidnight = false
    private var dayIsThisWeekday = false               // "this thursday": never roll to next week
    private var looseZoneWord = false                  // a zone word away from any time: ambiguous

    init(tokens: [String], zone: TimeZone, now: Date) {
        self.tokens = tokens
        self.zone = zone
        self.now = now
    }

    var shownZone: TimeZone? { displayZone ?? zoneOverride }

    private var calendar: Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zoneOverride ?? zone
        return cal
    }

    mutating func read() -> Reading {
        // Time zones first, so relative days ("today", "friday") are computed in the right zone.
        markTimeZones()
        if looseZoneWord { return .nothing }
        while i < tokens.count, !failed {
            if consumed.contains(i) { i += 1; continue }
            if !matchAnything() {
                let previous = i > 0 ? tokens[i - 1] : ""
                if tokens[i].count >= 3, Clock.compact(tokens[i], meridiem: nil) != nil, Vocabulary.year(tokens[i]) == nil {
                    // "fri 930": a time, a room number? Ask rather than guess.
                    return .note("Is “\(tokens[i])” a time? Add am or pm, like “\(tokens[i])am”, or write “at \(tokens[i])”.")
                }
                if Vocabulary.isMeaningful(tokens[i]) || (tokens[i] == "may" && ["in", "of"].contains(previous)) {
                    return .nothing
                }
                i += 1
            }
        }
        if let note { return .note(note) }
        if failed { return .nothing }
        return resolve().map(Reading.moment) ?? .nothing
    }

    // MARK: Token helpers

    private var consumed = Set<Int>()

    private func token(_ offset: Int = 0) -> String? {
        let index = i + offset
        return tokens.indices.contains(index) ? tokens[index] : nil
    }

    private mutating func take(_ count: Int) {
        for k in 0..<count { consumed.insert(i + k) }
        i += count
    }

    private mutating func fail() { failed = true }

    private mutating func setDay(_ newDay: DayComponents, bareWeekday: Bool = false) {
        if let day, day != newDay { fail(); return }
        if day != nil { return }
        day = newDay
        dayIsBareWeekday = bareWeekday
    }

    private mutating func setClock(_ newClock: Clock) {
        if clock != nil { fail(); return }
        clock = newClock
    }

    // MARK: Time zones

    private mutating func markTimeZones() {
        var named: [(zone: TimeZone, prepositional: Bool)] = []
        for k in tokens.indices {
            guard let id = Vocabulary.timeZones[tokens[k]], let tz = TimeZone(identifier: id) else { continue }
            let before = k > 0 ? tokens[k - 1] : "", after = k + 1 < tokens.count ? tokens[k + 1] : ""
            // "8pm PT", "PT 8pm", "8 pm eastern time", "london now" — never "la fitness" or "mt hood".
            let nextToTime = Vocabulary.isClockWord(before) || Vocabulary.isClockWord(after)
            // "london tomorrow noon": a spelled-out place next to a day. Short codes need a time.
            let nextToDay = tokens[k].count > 3 && (Vocabulary.isDayWord(before) || Vocabulary.isDayWord(after))
            // "8pm in london", "now in tokyo", "3pm london to tokyo" — never "in mt hood".
            let prepositional = (before == "in" || before == "to")
                && (after.isEmpty || Vocabulary.isClockWord(after) || Vocabulary.isDayWord(after))
            guard nextToTime || nextToDay || prepositional else {
                looseZoneWord = true
                continue
            }
            named.append((tz, prepositional))
            consumed.insert(k)
            if prepositional { consumed.insert(k - 1) }
            if after == "time" { consumed.insert(k + 1) }
        }
        switch named.count {
        case 0: break
        case 1: zoneOverride = named[0].zone
        case 2 where named[0].zone == named[1].zone: zoneOverride = named[0].zone
        case 2 where named[1].prepositional:
            // The first zone is where the time is; the second is where to show it.
            zoneOverride = named[0].zone
            displayZone = named[1].zone
        default: failed = true
        }
    }

    // MARK: Matchers

    private mutating func matchAnything() -> Bool {
        matchRelativeOffset()
            || matchNow()
            || matchHoliday()
            || matchOrdinalWeekday()
            || matchNamedDay()
            || matchThisNextWeekday()
            || matchMonthDay()
            || matchNumericDate()
            || matchPartOfDay()
            || matchTime()
            || matchFiller()
    }

    /// "in 3 hours", "in half an hour", "in two weeks", "3 days from now".
    private mutating func matchRelativeOffset() -> Bool {
        if token() == "in", token(1) == "half", token(2) == "an" || token(2) == "a", token(3) == "hour" {
            take(4)
            return setInstant(now.addingTimeInterval(30 * 60))
        }
        var start = 0
        if token() == "in" { start = 1 }
        guard let amountToken = token(start), let amount = Vocabulary.amount(amountToken),
              let unitToken = token(start + 1), let unit = Vocabulary.units[unitToken] else { return false }
        let fromNow = token(start + 2) == "from" && token(start + 3) == "now"
        let later = token(start + 2) == "later"
        guard start == 1 || fromNow || later else { return false }
        take(start + 2 + (fromNow ? 2 : later ? 1 : 0))

        switch unit {
        case .minute, .hour:
            let seconds = Double(amount) * (unit == .minute ? 60 : 3600)
            return setInstant(now.addingTimeInterval(seconds))
        case .day, .week, .month, .year:
            let component: Calendar.Component = [.day: .day, .week: .weekOfYear, .month: .month, .year: .year][unit]!
            guard let target = calendar.date(byAdding: component, value: amount, to: now) else { fail(); return true }
            setDay(DayComponents(date: target, calendar: calendar))
            return true
        }
    }

    /// "now", "right now": this minute, for "london now" and "now in tokyo".
    private mutating func matchNow() -> Bool {
        if token() == "right", token(1) == "now" { take(2); return setInstant(now) }
        guard token() == "now" else { return false }
        take(1)
        return setInstant(now)
    }

    private mutating func setInstant(_ date: Date) -> Bool {
        if instant != nil { fail() }
        instant = date
        return true
    }

    /// Holidays across calendars: "thanksgiving", "lunar new year", "erev yom kippur",
    /// "easter eve", "eid al-adha 2027". Known-but-undatable names leave a note instead.
    private mutating func matchHoliday() -> Bool {
        var lead = 0
        var shift = 0
        if token() == "erev" { lead = 1; shift = -1 }
        for length in stride(from: HolidayCatalog.longestName, through: 1, by: -1) {
            guard i + lead + length <= tokens.count else { continue }
            let phrase = HolidayCatalog.normalize(tokens[(i + lead)..<(i + lead + length)].joined(separator: " "))
            guard let entry = HolidayCatalog.lookup(phrase) else { continue }
            var used = lead + length
            if shift == 0, token(used) == "eve" { shift = -1; used += 1 }
            var year: Int?
            if let y = token(used).flatMap(Vocabulary.year) { year = y; used += 1 }
            take(used)

            switch entry {
            case .note(let message):
                note = message
                fail()
            case .days(let rule):
                let observances = rule(anchor(for: year)).map { Observance(day: $0, alternative: nil) }
                apply(pick(observances, year: year, shift: shift), name: nil)
            case .observances(let name, let rule):
                apply(pick(rule(anchor(for: year)), year: year, shift: shift), name: name)
            }
            return true
        }
        return false
    }

    private func anchor(for year: Int?) -> Date {
        year.flatMap { calendar.date(from: DateComponents(year: $0, month: 6, day: 1)) } ?? now
    }

    /// The occurrence in `year`, or the next one from today; `shift` moves to the eve.
    private func pick(_ observances: [Observance], year: Int?, shift: Int) -> Observance? {
        let today = CivilDay(now, in: calendar.timeZone)
        let shift = { (o: Observance) in
            Observance(day: o.day.adding(days: shift), alternative: o.alternative?.adding(days: shift))
        }
        // "new year's eve 2027" means the eve of 2027's holiday, so match the year before shifting.
        if let year { return observances.first { $0.day.year == year }.map(shift) }
        return observances.map(shift).first { ($0.alternative ?? $0.day) >= today }
    }

    private mutating func apply(_ observance: Observance?, name: String?) {
        guard let observance else { fail(); return }
        if let other = observance.alternative {
            // Almanacs disagree this year: say so instead of choosing.
            let f = DateFormatter()
            f.locale = Locale(identifier: "en_US")
            f.setLocalizedDateFormatFromTemplate("MMMd")
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: "UTC")!
            f.timeZone = cal.timeZone
            func text(_ d: CivilDay) -> String {
                f.string(from: cal.date(from: DateComponents(year: d.year, month: d.month, day: d.day, hour: 12))!)
            }
            note = "\(name ?? "It") \(observance.day.year) falls on \(text(observance.day)) or \(text(other)), "
                + "depending on the almanac you follow. Type the date instead, for example, “\(text(other).lowercased()) 7pm”."
            fail()
            return
        }
        setDay(DayComponents(observance.day))
    }

    /// "3rd friday in may", "last friday of the month", "first monday of next month", "2nd tuesday".
    private mutating func matchOrdinalWeekday() -> Bool {
        let lead = token() == "the" ? 1 : 0
        guard let ordinalToken = token(lead), let ordinal = Vocabulary.weekdayOrdinal(ordinalToken),
              let weekdayToken = token(lead + 1), let weekday = Vocabulary.weekdays[weekdayToken] else { return false }
        var length = lead + 2
        var month: Int?
        var monthOffset = 0
        var year: Int?

        if ordinal == -1, token(length) != "in", token(length) != "of" {
            // Bare "last friday" could mean the previous Friday or the month's last; don't pick.
            fail()
            return true
        }
        if token(length) == "in" || token(length) == "of" {
            var k = length + 1
            if token(k) == "the" { k += 1 }
            if let name = token(k), let m = Vocabulary.months[name] {
                month = m; length = k + 1
            } else if token(k) == "next", token(k + 1) == "month" {
                monthOffset = 1; length = k + 2
            } else if token(k) == "this" || token(k) == "the", token(k + 1) == "month" {
                length = k + 2
            } else if token(k) == "month" {
                length = k + 1
            } else {
                return false
            }
            if let y = token(length).flatMap(Vocabulary.year) { year = y; length += 1 }
        }
        take(length)

        let cal = calendar
        let today = cal.startOfDay(for: now)
        let thisYear = cal.component(.year, from: now)

        func nth(year: Int, month: Int) -> Date? {
            let parts = DateComponents(year: year, month: month, weekday: weekday, weekdayOrdinal: ordinal)
            guard let date = cal.date(from: parts), cal.component(.month, from: date) == month else { return nil }
            return date
        }

        var candidates: [(Int, Int)] = []
        if let month {
            if let year { candidates = [(year, month)] } else { candidates = [(thisYear, month), (thisYear + 1, month)] }
        } else {
            let base = cal.date(byAdding: .month, value: monthOffset, to: now)!
            let (y, m) = (cal.component(.year, from: base), cal.component(.month, from: base))
            candidates = [(y, m)]
            if monthOffset == 0 {
                let next = cal.date(byAdding: .month, value: 1, to: base)!
                candidates.append((cal.component(.year, from: next), cal.component(.month, from: next)))
            }
        }
        for (y, m) in candidates {
            guard let date = nth(year: y, month: m) else {
                // "5th friday in november" doesn't exist: refuse rather than guess another month.
                if candidates.count == 1 || year != nil || month != nil { fail(); return true }
                continue
            }
            if date >= today || candidates.count == 1 {
                setDay(DayComponents(date: date, calendar: cal))
                return true
            }
        }
        fail()
        return true
    }

    /// "today", "tonight", "tomorrow", "day after tomorrow", "yesterday", "this weekend", "next week".
    private mutating func matchNamedDay() -> Bool {
        let cal = calendar
        func offset(_ days: Int) -> DayComponents {
            DayComponents(date: cal.date(byAdding: .day, value: days, to: now)!, calendar: cal)
        }
        switch token() {
        case "today":
            take(1); setDay(offset(0)); return true
        case "tonight", "tonite":
            take(1); setDay(offset(0)); hintDefault(Clock(hour: 20, minute: 0, isTwentyFourHour: true), meridiem: .pm); return true
        case "tomorrow", "tmrw", "tmr", "tomorow", "tommorow", "tommorrow", "tmw":
            take(1); setDay(offset(1)); return true
        case "yesterday":
            take(1); setDay(offset(-1)); return true
        case "day" where token(1) == "after" && Vocabulary.isTomorrow(token(2)):
            take(3); setDay(offset(2)); return true
        case "weekend":
            take(1); setDay(upcomingWeekday(7, weeksAhead: 0)); return true
        case "end" where token(1) == "of":
            var k = 2
            if token(k) == "the" || token(k) == "this" { k += 1 }
            guard token(k) == "month" else { return false }
            take(k + 1)
            let range = cal.range(of: .day, in: .month, for: now)!
            var parts = cal.dateComponents([.year, .month], from: now)
            parts.day = range.count
            setDay(DayComponents(date: cal.date(from: parts)!, calendar: cal))
            return true
        default:
            return false
        }
    }

    /// "this friday", "next friday", "friday after next", "this weekend", "next weekend",
    /// "next week", "next month", "next year", and a bare "friday".
    private mutating func matchThisNextWeekday() -> Bool {
        let cal = calendar
        switch (token(), token(1)) {
        case ("this", "weekend"):
            take(2); setDay(upcomingWeekday(7, weeksAhead: 0)); return true
        case ("next", "weekend"):
            take(2); setDay(nextWeeksWeekday(7)); return true
        case ("next", "week"):
            take(2); setDay(DayComponents(date: cal.date(byAdding: .day, value: 7, to: now)!, calendar: cal)); return true
        case ("next", "month"):
            take(2); setDay(DayComponents(date: cal.date(byAdding: .month, value: 1, to: now)!, calendar: cal)); return true
        case ("next", "year"):
            take(2); setDay(DayComponents(date: cal.date(byAdding: .year, value: 1, to: now)!, calendar: cal)); return true
        default:
            break
        }
        if token() == "this", let wd = token(1).flatMap({ Vocabulary.weekdays[$0] }) {
            take(2); setDay(upcomingWeekday(wd, weeksAhead: 0)); dayIsThisWeekday = true; return true
        }
        if token() == "next", let wd = token(1).flatMap({ Vocabulary.weekdays[$0] }) {
            take(2)
            if token() == "week" { take(1) }
            setDay(nextWeeksWeekday(wd))
            return true
        }
        if let wd = token().flatMap({ Vocabulary.weekdays[$0] }) {
            if token(1) == "after", token(2) == "next" {
                take(3)
                let next = cal.date(from: nextWeeksWeekday(wd).components)!
                setDay(DayComponents(date: cal.date(byAdding: .day, value: 7, to: next)!, calendar: cal))
                return true
            }
            // "friday" next to an explicit date ("fri, may 15") only double-checks it.
            if day != nil || isFollowedByExplicitDate() {
                take(1); weekdayCheck = wd; return true
            }
            take(1)
            setDay(upcomingWeekday(wd, weeksAhead: 0), bareWeekday: true)
            return true
        }
        return false
    }

    private func isFollowedByExplicitDate() -> Bool {
        guard let next = token(1) else { return false }
        if Vocabulary.months[next] != nil { return true }
        if next.firstMatch(of: #/^\d{1,4}[/-]\d{1,2}([/-]\d{2,4})?$/#) != nil { return true }
        if next == "the" || Vocabulary.dayOfMonth(next) != nil, let after = token(2), after == "of" || Vocabulary.months[after] != nil {
            return true
        }
        if next == "the", let after = token(2), Vocabulary.dayOfMonth(after) != nil { return true }
        return false
    }

    /// The next `weekday` on or after today (1 = Sunday … 7 = Saturday).
    private func upcomingWeekday(_ weekday: Int, weeksAhead: Int) -> DayComponents {
        let cal = calendar
        let today = cal.startOfDay(for: now)
        let current = cal.component(.weekday, from: today)
        let ahead = (weekday - current + 7) % 7 + 7 * weeksAhead
        return DayComponents(date: cal.date(byAdding: .day, value: ahead, to: today)!, calendar: cal)
    }

    /// `weekday` in next calendar week (Sunday-start): on Thursday, "next friday" is 8 days out.
    private func nextWeeksWeekday(_ weekday: Int) -> DayComponents {
        let cal = calendar
        let today = cal.startOfDay(for: now)
        let current = cal.component(.weekday, from: today)
        let startOfNextWeek = cal.date(byAdding: .day, value: 8 - current, to: today)!
        return DayComponents(date: cal.date(byAdding: .day, value: weekday - 1, to: startOfNextWeek)!, calendar: cal)
    }

    /// "may 15", "may 15th 2027", "15 may", "15th of may", "the 15th", "the 15th of next month".
    private mutating func matchMonthDay() -> Bool {
        // month first
        if let m = token().flatMap({ Vocabulary.months[$0] }), let d = token(1).flatMap(Vocabulary.dayOfMonth) {
            var length = 2
            var year: Int?
            if let y = token(2).flatMap(Vocabulary.year) { year = y; length = 3 }
            take(length)
            setCalendarDay(month: m, day: d, year: year)
            return true
        }
        // day first: "15 may", "15th of may", "the 15th", "the 15th of may"
        var k = 0
        if token() == "the" { k = 1 }
        guard let d = token(k).flatMap(Vocabulary.dayOfMonth) else { return false }
        let isOrdinalForm = token(k).map { $0.firstMatch(of: #/^\d{1,2}(st|nd|rd|th)$/#) != nil } ?? false
        var length = k + 1
        if token(length) == "of" { length += 1 }
        if let m = token(length).flatMap({ Vocabulary.months[$0] }) {
            length += 1
            var year: Int?
            if let y = token(length).flatMap(Vocabulary.year) { year = y; length += 1 }
            take(length)
            setCalendarDay(month: m, day: d, year: year)
            return true
        }
        // "the 15th" with no month: this month, or next if it's past ("of next month" forces next).
        guard k == 1 || isOrdinalForm else { return false }
        let cal = calendar
        if token(k + 1) == "of", token(k + 2) == "next", token(k + 3) == "month" {
            take(k + 4)
            let next = cal.date(byAdding: .month, value: 1, to: now)!
            var parts = cal.dateComponents([.year, .month], from: next)
            parts.day = d
            guard let date = cal.date(from: parts), cal.component(.day, from: date) == d else { fail(); return true }
            setDay(DayComponents(date: date, calendar: cal))
            return true
        }
        // A bare "3rd" (no "the") is only a day when nothing word-like follows: "3rd blursday" isn't.
        if k == 0, let next = token(1), next.first?.isLetter == true, Meridiem(next) == nil, next != "at" {
            return false
        }
        take(k + 1)
        if let weekday = weekdayCheck {
            // "friday the 13th": the next month whose 13th is a Friday.
            for ahead in 0..<28 {
                guard let month = cal.date(byAdding: .month, value: ahead, to: cal.startOfDay(for: now)) else { break }
                var parts = cal.dateComponents([.year, .month], from: month)
                parts.day = d
                parts.hour = 12
                guard let date = cal.date(from: parts), cal.component(.day, from: date) == d else { continue }
                if cal.startOfDay(for: date) >= cal.startOfDay(for: now), cal.component(.weekday, from: date) == weekday {
                    setDay(DayComponents(date: date, calendar: cal))
                    return true
                }
            }
            fail()
            return true
        }
        var parts = cal.dateComponents([.year, .month], from: now)
        parts.day = d
        guard let candidate = cal.date(from: parts), cal.component(.day, from: candidate) == d else { fail(); return true }
        if candidate < cal.startOfDay(for: now) {
            let next = cal.date(byAdding: .month, value: 1, to: candidate)!
            setDay(DayComponents(date: next, calendar: cal))
        } else {
            setDay(DayComponents(date: candidate, calendar: cal))
        }
        return true
    }

    private mutating func setCalendarDay(month: Int, day d: Int, year: Int?) {
        let cal = calendar
        let thisYear = cal.component(.year, from: now)
        let today = cal.startOfDay(for: now)
        for y in year.map({ [$0] }) ?? [thisYear, thisYear + 1] {
            let parts = DateComponents(year: y, month: month, day: d)
            guard let date = cal.date(from: parts), cal.component(.day, from: date) == d else { fail(); return }
            if year != nil || date >= today {
                setDay(DayComponents(date: date, calendar: cal))
                return
            }
        }
        fail()
    }

    /// "5/15", "5/15/27", "5/15/2027", "2027-05-15".
    private mutating func matchNumericDate() -> Bool {
        guard let t = token() else { return false }
        if let m = t.firstMatch(of: #/^(\d{4})-(\d{1,2})-(\d{1,2})$/#) {
            take(1)
            setCalendarDay(month: Int(m.2)!, day: Int(m.3)!, year: Int(m.1)!)
            return true
        }
        if let m = t.firstMatch(of: #/^(\d{1,2})[/-](\d{1,2})(?:[/-](\d{2}|\d{4}))?$/#) {
            let month = Int(m.1)!, d = Int(m.2)!
            guard (1...12).contains(month), (1...31).contains(d) else { return false }
            take(1)
            let year = m.3.map { y -> Int in let v = Int(y)!; return v < 100 ? 2000 + v : v }
            setCalendarDay(month: month, day: d, year: year)
            return true
        }
        return false
    }

    /// "morning", "afternoon", "evening", "night", "noon", "midnight", "lunch", "dinner".
    private mutating func matchPartOfDay() -> Bool {
        guard let t = token() else { return false }
        switch t {
        case "noon", "midday":
            take(1); setClock(Clock(hour: 12, minute: 0, meridiem: .pm)); return true
        case "midnight":
            take(1); setClock(Clock(hour: 0, minute: 0, meridiem: .am)); addDayForMidnight = true; return true
        default:
            break
        }
        if let (clock, meridiem) = Vocabulary.partsOfDay[t] {
            take(1)
            hintDefault(clock, meridiem: meridiem)
            return true
        }
        return false
    }

    private mutating func hintDefault(_ clock: Clock, meridiem: Meridiem?) {
        if defaultClock == nil { defaultClock = clock }
        if let meridiem { meridiemHint = meridiem }
    }

    /// "6pm", "6 pm", "6p", "6:30", "18:00", "at 6", "at 1800", "6 o'clock", "half past 6",
    /// "quarter to 7", and ranges ("6-8pm", "6 to 8pm") which keep the start time.
    private mutating func matchTime() -> Bool {
        var k = 0
        let afterAt = token() == "at"
        if afterAt { k = 1 }

        // half past / quarter past / quarter to
        if let lead = token(k), lead == "half" || lead == "quarter", let rel = token(k + 1), rel == "past" || rel == "to" || rel == "after",
           let hourToken = token(k + 2), let hour = Int(hourToken), (1...12).contains(hour) {
            var minute = lead == "half" ? 30 : 15
            var h = hour
            if rel == "to" { minute = 60 - minute; h = hour == 1 ? 12 : hour - 1 }
            take(k + 3)
            setClock(Clock(hour: h, minute: minute, meridiem: takeMeridiem()))
            return true
        }

        guard let t = token(k) else { return false }
        var used = 1
        var parsed = Clock.parse(t, allowMilitary: afterAt)
        if parsed == nil, afterAt { parsed = Clock.compact(t, meridiem: nil) }             // "at 930"
        if parsed == nil, let next = token(k + 1), next == "am" || next == "pm",          // "830 am"
           let clock = Clock.compact(t, meridiem: Meridiem(next)) {
            parsed = clock
            used = 2
        }
        if let hour = Int(t), t.count <= 2, (1...12).contains(hour), let next = token(k + 1) {
            if let m = next.firstMatch(of: #/^([0-5]\d)(am|pm|a|p)$/#) {                    // "8 30am"
                parsed = Clock(hour: hour, minute: Int(m.1)!, meridiem: Meridiem(String(m.2)))
                used = 2
            } else if next.firstMatch(of: #/^[0-5]\d$/#) != nil, let last = token(k + 2), last == "am" || last == "pm" {
                parsed = Clock(hour: hour, minute: Int(next)!, meridiem: Meridiem(last))    // "8 30 am"
                used = 3
            }
        }
        guard var start = parsed else { return false }
        if start.meridiem == nil, !afterAt, token(k + 1).flatMap(Meridiem.init) == nil,
           token(k + 1) != "o'clock", token(k + 1) != "oclock", !t.contains(":") {
            // A bare number like "6" only counts as a time next to a day word ("friday 6").
            // …or when it starts a range that ends in a clear time ("11-1pm", "6 to 8pm").
            let startsRange = token(k + 1).map { ["-", "to", "until", "till", "til"].contains($0) } == true
                && token(k + 2).flatMap { Clock.parse($0, allowMilitary: false) }?.meridiem != nil
            let followsDay = day != nil && i > 0 && consumed.contains(i - 1)
            let link = ["on", "this", "next"].contains(token(k + 1) ?? "") ? 2 : 1
            let precedesDay = token(k + link).map(Vocabulary.isDayWord) ?? false
            guard followsDay || startsRange || precedesDay else { return false }
        }
        take(k + used)
        if start.meridiem == nil { start.meridiem = takeMeridiem() }
        if token() == "o'clock" || token() == "oclock" { take(1) }

        // Range: keep the start, borrowing the end's am/pm ("6-8pm" → 6pm).
        if let sep = token(), ["-", "to", "until", "till", "til"].contains(sep), let endToken = token(1), var end = Clock.parse(endToken, allowMilitary: false) {
            take(2)
            if end.meridiem == nil { end.meridiem = takeMeridiem() }
            if start.meridiem == nil, let em = end.meridiem {
                // "11-1pm" starts in the morning; "6-8pm" in the evening.
                start.meridiem = (em == .pm && start.hour > end.hour && start.hour != 12) ? .am : em
            }
        }
        setClock(start)
        return true
    }

    private mutating func takeMeridiem() -> Meridiem? {
        if let t = token(), let m = Meridiem(t) { take(1); return m }
        return nil
    }

    private mutating func matchFiller() -> Bool {
        guard let t = token(), Vocabulary.fillers.contains(t) else { return false }
        take(1)
        return true
    }

    // MARK: Resolve

    private func resolve() -> Date? {
        if let instant {
            return (day == nil && clock == nil) ? instant : nil
        }
        guard day != nil || clock != nil || defaultClock != nil else { return nil }

        let cal = calendar
        let today = DayComponents(date: now, calendar: cal)
        let target = day ?? today

        if let weekdayCheck, let date = cal.date(from: target.components), cal.component(.weekday, from: date) != weekdayCheck {
            return nil
        }

        let explicitDay = day != nil
        var time = clock ?? defaultClock ?? Clock(hour: 12, minute: 0, meridiem: .pm)
        if time.meridiem == nil { time.meridiem = meridiemHint }

        var result: Date
        if time.meridiem == nil, time.isTwelveHourAmbiguous, !explicitDay {
            // A bare "8" today means the next 8 o'clock: 8 AM if it's still ahead, else 8 PM.
            let am = cal.date(from: target.at(Clock(hour: time.hour, minute: time.minute, meridiem: .am)))!
            let pm = cal.date(from: target.at(Clock(hour: time.hour, minute: time.minute, meridiem: .pm)))!
            result = am > now ? am : pm
        } else {
            if time.meridiem == nil, time.isTwelveHourAmbiguous {
                // On a named day, 12 is noon, 1–6 reads as afternoon/evening, 7–11 as morning.
                time.meridiem = (time.hour == 12 || (1...6).contains(time.hour)) ? .pm : .am
            }
            result = cal.date(from: target.at(time))!
        }

        if addDayForMidnight { result = cal.date(byAdding: .day, value: 1, to: result)! }

        if !explicitDay, result < now {
            // "8pm" after 8pm means tomorrow.
            result = cal.date(byAdding: .day, value: 1, to: result)!
        } else if dayIsThisWeekday, result < now {
            // "this thursday 8am" said Thursday afternoon: today's 8 AM is gone, and next week isn't "this".
            return nil
        } else if dayIsBareWeekday, result < now {
            // "friday 8am" on a Friday afternoon means next Friday.
            result = cal.date(byAdding: .day, value: 7, to: result)!
        }
        return result
    }
}

// MARK: - Values

private struct DayComponents: Equatable {
    var year: Int, month: Int, day: Int

    init(date: Date, calendar: Calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        year = parts.year!; month = parts.month!; day = parts.day!
    }

    init(_ civil: CivilDay) {
        year = civil.year; month = civil.month; day = civil.day
    }

    var components: DateComponents { DateComponents(year: year, month: month, day: day, hour: 12) }

    func at(_ clock: Clock) -> DateComponents {
        DateComponents(year: year, month: month, day: day, hour: clock.hour24, minute: clock.minute)
    }
}

private enum Meridiem: Equatable {
    case am, pm

    init?(_ token: String) {
        switch token {
        case "am", "a": self = .am
        case "pm", "p": self = .pm
        default: return nil
        }
    }
}

private struct Clock: Equatable {
    var hour: Int
    var minute: Int
    var meridiem: Meridiem?
    /// Written in 24-hour form ("18:00", "06:30"), so am/pm guessing doesn't apply.
    var isTwentyFourHour = false

    init(hour: Int, minute: Int, meridiem: Meridiem? = nil, isTwentyFourHour: Bool = false) {
        self.hour = hour
        self.minute = minute
        self.meridiem = meridiem
        self.isTwentyFourHour = isTwentyFourHour
    }

    var isTwelveHourAmbiguous: Bool { !isTwentyFourHour && (1...12).contains(hour) }

    var hour24: Int {
        guard let meridiem, !isTwentyFourHour else { return hour }
        switch meridiem {
        case .am: return hour == 12 ? 0 : hour
        case .pm: return hour == 12 ? 12 : hour + 12
        }
    }

    /// "6", "6pm", "6p", "6:30", "6:30pm", "18:00", "06:30", and "1800" when `allowMilitary`.
    static func parse(_ token: String, allowMilitary: Bool) -> Clock? {
        if let m = token.firstMatch(of: #/^(\d{1,2})(?::(\d{2}))?(am|pm|a|p)?$/#) {
            let hour = Int(m.1)!, minute = m.2.map { Int($0)! } ?? 0
            guard minute < 60 else { return nil }
            let meridiem = m.3.flatMap { Meridiem(String($0)) }
            if meridiem != nil {
                guard (1...12).contains(hour) else { return nil }
                return Clock(hour: hour, minute: minute, meridiem: meridiem)
            }
            guard hour < 24 else { return nil }
            let twentyFour = hour == 0 || hour >= 13 || (m.1.count == 2 && m.1.hasPrefix("0"))
            return Clock(hour: hour, minute: minute, isTwentyFourHour: twentyFour)
        }
        if let m = token.firstMatch(of: #/^(\d{1,2})(\d{2})(am|pm|a|p)$/#) {             // "830am", "1130p"
            return compact(String(m.1) + String(m.2), meridiem: Meridiem(String(m.3)))
        }
        if allowMilitary, let m = token.firstMatch(of: #/^([01]\d|2[0-3])([0-5]\d)$/#) {
            return Clock(hour: Int(m.1)!, minute: Int(m.2)!, isTwentyFourHour: true)
        }
        return nil
    }

    /// "830" or "1130" as a twelve-hour time, with or without its am/pm.
    static func compact(_ token: String, meridiem: Meridiem?) -> Clock? {
        guard let m = token.firstMatch(of: #/^(\d{1,2})(\d{2})$/#), let hour = Int(m.1), let minute = Int(m.2),
              (1...12).contains(hour), minute < 60 else { return nil }
        return Clock(hour: hour, minute: minute, meridiem: meridiem)
    }
}

// MARK: - Vocabulary

private enum Unit: Hashable { case minute, hour, day, week, month, year }

private enum Vocabulary {
    static let weekdays: [String: Int] = [
        "sun": 1, "sunday": 1, "suns": 1,
        "mon": 2, "monday": 2, "mondays": 2,
        "tue": 3, "tues": 3, "tuesday": 3,
        "wed": 4, "weds": 4, "wednesday": 4,
        "thu": 5, "thur": 5, "thurs": 5, "thursday": 5,
        "fri": 6, "friday": 6,
        "sat": 7, "saturday": 7,
    ]

    static let months: [String: Int] = [
        "jan": 1, "january": 1, "feb": 2, "february": 2, "mar": 3, "march": 3,
        "apr": 4, "april": 4, "may": 5, "jun": 6, "june": 6, "jul": 7, "july": 7,
        "aug": 8, "august": 8, "sep": 9, "sept": 9, "september": 9, "oct": 10, "october": 10,
        "nov": 11, "november": 11, "dec": 12, "december": 12,
    ]

    static let units: [String: Unit] = [
        "minute": .minute, "minutes": .minute, "min": .minute, "mins": .minute,
        "hour": .hour, "hours": .hour, "hr": .hour, "hrs": .hour,
        "day": .day, "days": .day,
        "week": .week, "weeks": .week, "wk": .week, "wks": .week,
        "month": .month, "months": .month,
        "year": .year, "years": .year,
    ]

    static let numberWords: [String: Int] = [
        "a": 1, "an": 1, "one": 1, "two": 2, "three": 3, "four": 4, "five": 5, "six": 6,
        "seven": 7, "eight": 8, "nine": 9, "ten": 10, "eleven": 11, "twelve": 12, "couple": 2,
    ]

    static func amount(_ token: String) -> Int? {
        if let n = Int(token), n >= 0, n < 10_000 { return n }
        return numberWords[token]
    }

    static func weekdayOrdinal(_ token: String) -> Int? {
        ["first": 1, "1st": 1, "second": 2, "2nd": 2, "third": 3, "3rd": 3,
         "fourth": 4, "4th": 4, "fifth": 5, "5th": 5, "last": -1, "final": -1][token]
    }

    /// "15", "15th", "1st", "22nd" → 1…31.
    static func dayOfMonth(_ token: String) -> Int? {
        guard let m = token.firstMatch(of: #/^(\d{1,2})(st|nd|rd|th)?$/#), let d = Int(m.1), (1...31).contains(d) else {
            return nil
        }
        return d
    }

    /// "2027", "'27".
    static func year(_ token: String) -> Int? {
        if let m = token.firstMatch(of: #/^(19\d\d|20\d\d|21\d\d)$/#) { return Int(m.1) }
        if let m = token.firstMatch(of: #/^'(\d\d)$/#) { return 2000 + Int(m.1)! }
        return nil
    }

    /// Words a bare hour can attach to: "6 tonight", "8 morning", "7 fri", "6 tmrw".
    static func isDayWord(_ token: String) -> Bool {
        weekdays[token] != nil || isTomorrow(token) || partsOfDay[token] != nil
            || ["today", "tonight", "tonite", "noon", "midnight"].contains(token)
    }

    /// A time or a piece of one, for deciding whether a zone word is attached to a time.
    static func isClockWord(_ token: String) -> Bool {
        if token.firstMatch(of: #/^\d{1,2}(:?\d\d)?(am|pm|a|p)?$/#) != nil { return true }
        return ["am", "pm", "a", "p", "noon", "midnight", "o'clock", "oclock", "time", "now"].contains(token)
    }

    static func isTomorrow(_ token: String?) -> Bool {
        ["tomorrow", "tmrw", "tmr", "tomorow", "tommorow", "tommorrow", "tmw"].contains(token ?? "")
    }

    /// Default times for words that imply one; an explicit time always wins.
    static let partsOfDay: [String: (Clock, Meridiem?)] = [
        "morning": (Clock(hour: 9, minute: 0, meridiem: .am), .am),
        "breakfast": (Clock(hour: 8, minute: 0, meridiem: .am), .am),
        "brunch": (Clock(hour: 11, minute: 0, meridiem: .am), nil),
        "lunch": (Clock(hour: 12, minute: 0, meridiem: .pm), nil),
        "afternoon": (Clock(hour: 15, minute: 0, isTwentyFourHour: true), .pm),
        "evening": (Clock(hour: 19, minute: 0, isTwentyFourHour: true), .pm),
        "dinner": (Clock(hour: 19, minute: 0, isTwentyFourHour: true), .pm),
        "night": (Clock(hour: 20, minute: 0, isTwentyFourHour: true), .pm),
    ]

    /// Typed time zones. US abbreviations map to the region, so "EST" in summer still means New York.
    static let timeZones: [String: String] = [
        "et": "America/New_York", "est": "America/New_York", "edt": "America/New_York", "eastern": "America/New_York",
        "ct": "America/Chicago", "cst": "America/Chicago", "cdt": "America/Chicago", "central": "America/Chicago",
        "mt": "America/Denver", "mst": "America/Denver", "mdt": "America/Denver", "mountain": "America/Denver",
        "pt": "America/Los_Angeles", "pst": "America/Los_Angeles", "pdt": "America/Los_Angeles", "pacific": "America/Los_Angeles",
        "akst": "America/Anchorage", "akdt": "America/Anchorage", "alaska": "America/Anchorage",
        "hst": "Pacific/Honolulu", "hawaii": "Pacific/Honolulu",
        "arizona": "America/Phoenix", "phoenix": "America/Phoenix",
        "utc": "UTC", "gmt": "Europe/London", "bst": "Europe/London", "london": "Europe/London",
        "cet": "Europe/Paris", "cest": "Europe/Paris", "paris": "Europe/Paris", "berlin": "Europe/Berlin",
        "amsterdam": "Europe/Amsterdam", "madrid": "Europe/Madrid", "rome": "Europe/Rome", "stockholm": "Europe/Stockholm",
        "ist": "Asia/Kolkata", "delhi": "Asia/Kolkata", "mumbai": "Asia/Kolkata",
        "jst": "Asia/Tokyo", "tokyo": "Asia/Tokyo", "kst": "Asia/Seoul", "seoul": "Asia/Seoul",
        "sgt": "Asia/Singapore", "singapore": "Asia/Singapore", "hkt": "Asia/Hong_Kong",
        "aest": "Australia/Sydney", "aedt": "Australia/Sydney", "sydney": "Australia/Sydney", "melbourne": "Australia/Melbourne",
        "nzst": "Pacific/Auckland", "nzdt": "Pacific/Auckland", "auckland": "Pacific/Auckland",
        "nyc": "America/New_York", "toronto": "America/Toronto", "chicago": "America/Chicago",
        "denver": "America/Denver", "la": "America/Los_Angeles", "seattle": "America/Los_Angeles", "vancouver": "America/Vancouver",
    ]

    static let fillers: Set<String> = [
        "at", "on", "the", "of", "in", "by", "from", "around", "about", "approx", "approximately",
        "starting", "starts", "start", "begins", "beginning", "-", "o'clock", "oclock", "time", "this", "and", "for",
    ]

    static let spelledNumbers: Set<String> = [
        "two", "three", "four", "five", "six", "seven", "eight", "nine", "ten", "eleven", "twelve",
        "fifteen", "twenty", "thirty", "forty", "forty-five", "fifty",
    ]

    /// Words that carry date meaning; if one is left unread, the parse is refused.
    static func isMeaningful(_ token: String) -> Bool {
        if token.contains(where: \.isNumber) { return true }
        if weekdays[token] != nil { return true }
        if let m = months[token], m != 5 { return true }   // "may" is usually the verb
        if weekdayOrdinal(token) != nil, token != "last" && token != "first" && token != "second" { return true }
        // "eight thirty at night": a spelled-out number is probably part of the time. Skipping it
        // would turn this into a plain "night" (8 PM), so refuse instead.
        if spelledNumbers.contains(token) { return true }
        return ["next", "after", "before", "ago", "tomorrow", "today", "tonight", "yesterday", "noon", "midnight",
                "week", "weekend", "month", "year", "hours", "minutes", "days", "weeks", "months"].contains(token)
    }
}
