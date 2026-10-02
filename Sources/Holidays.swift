import Foundation

/// A calendar day with no time or zone attached.
struct CivilDay: Hashable, Comparable {
    let year: Int, month: Int, day: Int

    static func < (a: CivilDay, b: CivilDay) -> Bool {
        (a.year, a.month, a.day) < (b.year, b.month, b.day)
    }

    func adding(days: Int) -> CivilDay {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let date = cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        return CivilDay(cal.date(byAdding: .day, value: days, to: date)!, in: cal.timeZone)
    }

    init(year: Int, month: Int, day: Int) {
        self.year = year; self.month = month; self.day = day
    }

    /// The Gregorian day `date` falls on in `zone`.
    init(_ date: Date, in zone: TimeZone) {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        let p = cal.dateComponents([.year, .month, .day], from: date)
        self.init(year: p.year!, month: p.month!, day: p.day!)
    }
}

/// One year's observance: a single day, or two days when traditions disagree.
struct Observance {
    let day: CivilDay
    let alternative: CivilDay?
}

/// What a holiday name means: a rule that yields its days, or a reason we won't pick one.
enum HolidayEntry {
    /// Occurrences around `now`, ascending.
    case days((Date) -> [CivilDay])
    /// Occurrences that may be contested between almanacs; `name` is used in the explanation.
    case observances(name: String, (Date) -> [Observance])
    /// Known, but its date can't be placed honestly (varies by country, or which one is ambiguous).
    case note(String)
}

enum HolidayCatalog {
    /// `phrase` is lowercased, apostrophes removed, hyphens as spaces, single-spaced.
    static func lookup(_ phrase: String) -> HolidayEntry? { table[phrase] }

    /// Every word that appears in a holiday's name, for checking that a rewrite kept them.
    static let nameWords: Set<String> = Set(table.keys.flatMap { $0.split(separator: " ").map(String.init) })

    /// Every holiday that resolves to dates, for the long-range stability check.
    static var datedRules: [(name: String, rule: (Date) -> [CivilDay])] {
        table.compactMap { name, entry in
            switch entry {
            case .days(let rule): return (name, rule)
            case .observances(_, let rule): return (name, { rule($0).map(\.day) })
            case .note: return nil
            }
        }.sorted { $0.name < $1.name }
    }

    static let longestName = table.keys.map { $0.split(separator: " ").count }.max() ?? 1

    static func normalize(_ text: String) -> String {
        text.lowercased()
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US"))
            .replacingOccurrences(of: "'", with: "")
            .replacingOccurrences(of: "-", with: " ")
            .split(separator: " ").joined(separator: " ")
    }

    // MARK: Rules

    private static let utc = TimeZone(identifier: "UTC")!

    private static func gregorianYears(_ now: Date) -> ClosedRange<Int> {
        let y = CivilDay(now, in: utc).year
        return (y - 1)...(y + 2)
    }

    private static func fixed(_ month: Int, _ day: Int) -> HolidayEntry {
        .days { now in gregorianYears(now).map { CivilDay(year: $0, month: month, day: day) } }
    }

    /// nth weekday of a Gregorian month (1 = Sunday; ordinal -1 = last).
    private static func nth(_ ordinal: Int, _ weekday: Int, _ month: Int, plus: Int = 0) -> HolidayEntry {
        .days { now in
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = utc
            return gregorianYears(now).compactMap { y in
                cal.date(from: DateComponents(year: y, month: month, hour: 12, weekday: weekday, weekdayOrdinal: ordinal))
                    .map { CivilDay($0, in: utc).adding(days: plus) }
            }
        }
    }

    /// Western (Gregorian) Easter, anonymous Gregorian algorithm.
    private static func westernEaster(_ year: Int) -> CivilDay {
        let a = year % 19, b = year / 100, c = year % 100, d = b / 4, e = b % 4
        let f = (b + 8) / 25, g = (b - f + 1) / 3, h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        return CivilDay(year: year, month: (h + l - 7 * m + 114) / 31, day: (h + l - 7 * m + 114) % 31 + 1)
    }

    /// Orthodox Easter: Julian computus, then shifted by the Julian–Gregorian gap for that
    /// century (13 days now, 14 from 2100), so it never needs a manual update.
    private static func orthodoxEaster(_ year: Int) -> CivilDay {
        let a = year % 4, b = year % 7, c = year % 19
        let d = (19 * c + 15) % 30, e = (2 * a + 4 * b - d + 34) % 7
        let month = (d + e + 114) / 31, day = (d + e + 114) % 31 + 1
        let gap = year / 100 - year / 400 - 2
        return CivilDay(year: year, month: month, day: day).adding(days: gap)
    }

    private static func easter(plus offset: Int, orthodox: Bool = false) -> HolidayEntry {
        .days { now in gregorianYears(now).map { (orthodox ? orthodoxEaster($0) : westernEaster($0)).adding(days: offset) } }
    }

    /// First Sunday of Advent: the fourth Sunday before Christmas.
    private static let advent = HolidayEntry.days { now in
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        return gregorianYears(now).map { y in
            let eve = cal.date(from: DateComponents(year: y, month: 12, day: 24, hour: 12))!
            let back = cal.component(.weekday, from: eve) - 1          // days back to the Sunday on/before Dec 24
            return CivilDay(eve, in: utc).adding(days: -back - 21)
        }
    }

    /// A day in another calendar system (Chinese, Hebrew, Islamic…), read in that calendar's home zone.
    private static func lunar(_ id: Calendar.Identifier, _ zone: String, month: Int, day: Int, plus: Int = 0,
                              hasLeapMonths: Bool = false) -> HolidayEntry {
        .days { now in
            var cal = Calendar(identifier: id)
            cal.timeZone = TimeZone(identifier: zone)!
            var result: [CivilDay] = []
            for offset in -1...2 {
                guard let anchor = cal.date(byAdding: .year, value: offset, to: now) else { continue }
                var parts = cal.dateComponents([.era, .year], from: anchor)
                parts.month = month
                parts.day = day
                parts.hour = 12
                if hasLeapMonths { parts.isLeapMonth = false }
                guard let date = cal.date(from: parts),
                      cal.component(.month, from: date) == month, cal.component(.day, from: date) == day else { continue }
                result.append(CivilDay(date, in: cal.timeZone).adding(days: plus))
            }
            return Array(Set(result)).sorted()
        }
    }

    private static func chinese(_ month: Int, _ day: Int, plus: Int = 0) -> HolidayEntry {
        lunar(.chinese, "Asia/Shanghai", month: month, day: day, plus: plus, hasLeapMonths: true)
    }

    private static func korean(_ month: Int, _ day: Int, plus: Int = 0) -> HolidayEntry {
        if #available(macOS 26, iOS 26, *) { return lunar(.dangi, "Asia/Seoul", month: month, day: day, plus: plus, hasLeapMonths: true) }
        return lunar(.chinese, "Asia/Seoul", month: month, day: day, plus: plus, hasLeapMonths: true)
    }

    private static func vietnamese(_ month: Int, _ day: Int, plus: Int = 0) -> HolidayEntry {
        if #available(macOS 26, iOS 26, *) { return lunar(.vietnamese, "Asia/Ho_Chi_Minh", month: month, day: day, plus: plus, hasLeapMonths: true) }
        return lunar(.chinese, "Asia/Ho_Chi_Minh", month: month, day: day, plus: plus, hasLeapMonths: true)
    }

    /// Hebrew months as Foundation numbers them: 1 Tishrei … 6 Adar I (leap years only),
    /// 7 Adar / Adar II, 8 Nisan, 9 Iyar, 10 Sivan, 11 Tammuz, 12 Av, 13 Elul.
    private static func hebrew(_ month: Int, _ day: Int, plus: Int = 0) -> HolidayEntry {
        lunar(.hebrew, "Asia/Jerusalem", month: month, day: day, plus: plus)
    }

    /// Tisha B'Av moves to Sunday when 9 Av falls on Shabbat.
    private static let tishaBav = HolidayEntry.days { now in
        guard case let .days(rule) = hebrew(12, 9) else { return [] }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = utc
        return rule(now).map { d in
            let date = cal.date(from: DateComponents(year: d.year, month: d.month, day: d.day, hour: 12))!
            return cal.component(.weekday, from: date) == 7 ? d.adding(days: 1) : d
        }
    }

    /// Islamic (Umm al-Qura) months: 1 Muharram … 9 Ramadan, 10 Shawwal, 12 Dhu al-Hijjah.
    private static func islamic(_ month: Int, _ day: Int) -> HolidayEntry {
        lunar(.islamicUmmAlQura, "Asia/Riyadh", month: month, day: day)
    }

    /// The day the sun reaches `longitude` (degrees) as seen in `zone`, near `approxMonth/approxDay`.
    private static func solarTerm(_ longitude: Double, _ zone: String, near approxMonth: Int, _ approxDay: Int, plus: Int = 0) -> HolidayEntry {
        .days { now in
            gregorianYears(now).compactMap { y in
                Solar.moment(longitude: longitude, nearYear: y, month: approxMonth, day: approxDay)
                    .map { CivilDay($0, in: TimeZone(identifier: zone)!).adding(days: plus) }
            }
        }
    }

    private static let persianNewYear = lunar(.persian, "Asia/Tehran", month: 1, day: 1)

    private static func unknown(_ name: String, _ why: String) -> HolidayEntry {
        .note("\(name) \(why) Type the date instead, for example, “nov 8 7pm”.")
    }

    // MARK: Table

    private static let table: [String: HolidayEntry] = {
        var t: [String: HolidayEntry] = [:]
        func add(_ names: [String], _ entry: HolidayEntry) {
            for n in names { t[normalize(n)] = entry }
        }

        // Civic (US)
        add(["new year's day", "new years", "new year", "new year's"], fixed(1, 1))
        add(["new year's eve", "nye"], fixed(12, 31))
        add(["valentine's day", "valentines", "valentine's"], fixed(2, 14))
        add(["st patrick's day", "st patricks", "saint patrick's day", "st paddy's day", "paddy's day"], fixed(3, 17))
        add(["mother's day", "mothers day"], nth(2, 1, 5))
        add(["mothering sunday", "uk mother's day"], easter(plus: -21))
        add(["memorial day"], nth(-1, 2, 5))
        add(["father's day", "fathers day"], nth(3, 1, 6))
        add(["juneteenth"], fixed(6, 19))
        add(["fourth of july", "july fourth", "4th of july", "us independence day", "american independence day"], fixed(7, 4))
        add(["independence day"], .note("Independence Day depends on the country. Try “fourth of july” for the US, or type the date."))
        add(["labor day", "labour day"], nth(1, 2, 9))
        add(["halloween"], fixed(10, 31))
        add(["veterans day"], fixed(11, 11))
        add(["thanksgiving", "thanksgiving day", "us thanksgiving", "american thanksgiving"], nth(4, 5, 11))
        add(["canadian thanksgiving", "thanksgiving canada"], nth(2, 2, 10))
        add(["black friday"], nth(4, 5, 11, plus: 1))

        // Christian (Western)
        add(["christmas", "christmas day", "xmas"], fixed(12, 25))
        add(["christmas eve", "xmas eve"], fixed(12, 24))
        add(["boxing day", "st stephen's day"], fixed(12, 26))
        add(["epiphany", "three kings day", "twelfth night"], fixed(1, 6))
        add(["candlemas", "presentation of the lord"], fixed(2, 2))
        add(["annunciation", "feast of the annunciation"], fixed(3, 25))
        add(["assumption of mary", "feast of the assumption", "assumption day"], fixed(8, 15))
        add(["all saints day", "all saints", "all hallows"], fixed(11, 1))
        add(["all souls day", "all souls"], fixed(11, 2))
        add(["immaculate conception", "feast of the immaculate conception"], fixed(12, 8))
        add(["first sunday of advent", "advent sunday", "start of advent"], advent)
        add(["mardi gras", "fat tuesday", "shrove tuesday", "pancake day", "pancake tuesday"], easter(plus: -47))
        add(["ash wednesday", "start of lent", "beginning of lent", "first day of lent"], easter(plus: -46))
        add(["palm sunday"], easter(plus: -7))
        add(["maundy thursday", "holy thursday"], easter(plus: -3))
        add(["good friday"], easter(plus: -2))
        add(["holy saturday", "easter saturday", "easter vigil"], easter(plus: -1))
        add(["easter", "easter sunday", "resurrection sunday"], easter(plus: 0))
        add(["easter monday"], easter(plus: 1))
        add(["ascension day", "ascension thursday", "feast of the ascension"], easter(plus: 39))
        add(["pentecost", "whitsun", "whit sunday", "whitsunday"], easter(plus: 49))
        add(["whit monday", "pentecost monday"], easter(plus: 50))
        add(["trinity sunday"], easter(plus: 56))
        add(["corpus christi"], easter(plus: 60))

        // Christian (Orthodox)
        add(["orthodox easter", "pascha", "orthodox pascha", "greek easter", "russian easter"], easter(plus: 0, orthodox: true))
        add(["orthodox good friday", "great and holy friday"], easter(plus: -2, orthodox: true))
        add(["orthodox palm sunday"], easter(plus: -7, orthodox: true))
        add(["orthodox pentecost"], easter(plus: 49, orthodox: true))
        add(["clean monday", "orthodox lent"], easter(plus: -48, orthodox: true))
        add(["orthodox christmas", "coptic christmas", "russian christmas", "ethiopian christmas", "genna"], fixed(1, 7))
        add(["theophany", "orthodox epiphany"], fixed(1, 19))

        // Jewish (first full day; "erev …" gives the evening before)
        add(["rosh hashanah", "rosh hashana", "rosh hashonah", "jewish new year"], hebrew(1, 1))
        add(["yom kippur", "day of atonement"], hebrew(1, 10))
        add(["sukkot", "succot", "sukkos", "feast of tabernacles"], hebrew(1, 15))
        add(["shemini atzeret"], hebrew(1, 22))
        add(["simchat torah", "simchas torah"], hebrew(1, 23))
        add(["hanukkah", "chanukah", "hanukah", "chanukkah", "channukah"], hebrew(3, 25))
        add(["festival of lights"], .note("Hanukkah and Diwali are both called the Festival of Lights. Type “hanukkah” or “diwali” instead."))
        add(["tu bishvat", "tu b'shvat", "tu bshvat"], hebrew(5, 15))
        add(["purim"], hebrew(7, 14))
        add(["passover", "pesach", "pesah"], hebrew(8, 15))
        add(["seder", "first seder", "passover seder"], hebrew(8, 14))
        add(["second seder"], hebrew(8, 15))
        add(["lag baomer", "lag b'omer", "lag bomer"], hebrew(9, 18))
        add(["shavuot", "shavuos", "feast of weeks"], hebrew(10, 6))
        add(["tisha bav", "tisha b'av", "tisha beav", "ninth of av"], tishaBav)

        // Islamic (Umm al-Qura; local moon sighting can differ by a day)
        add(["islamic new year", "hijri new year", "muharram", "arabic new year", "ras as sana"], islamic(1, 1))
        add(["ashura", "day of ashura"], islamic(1, 10))
        add(["mawlid", "mawlid an nabi", "mawlid al nabi", "milad un nabi", "prophet's birthday", "prophets birthday"], islamic(3, 12))
        add(["isra and miraj", "isra miraj", "laylat al miraj", "shab e miraj"], islamic(7, 27))
        add(["shab e barat", "laylat al baraat", "mid shaban", "nisf shaban"], islamic(8, 15))
        add(["ramadan", "start of ramadan", "first day of ramadan", "ramzan"], islamic(9, 1))
        add(["laylat al qadr", "night of power", "lailat ul qadr", "shab e qadr"], islamic(9, 27))
        add(["eid al fitr", "eid ul fitr", "eid al-fitr", "eid ul-fitr", "eid fitr", "hari raya", "hari raya aidilfitri", "lebaran", "ramazan bayram"], islamic(10, 1))
        add(["day of arafah", "arafah", "arafat day"], islamic(12, 9))
        add(["eid al adha", "eid ul adha", "eid al-adha", "eid ul-adha", "eid adha", "bakrid", "bakri eid", "kurban bayram", "hari raya haji"], islamic(12, 10))
        add(["eid", "eid mubarak"], .note("Which Eid? Try “Eid al-Fitr” or “Eid al-Adha”."))

        // Chinese
        add(["lunar new year", "chinese new year", "cny", "spring festival", "chunjie", "chun jie",
             "lunar new years day", "chinese new years day"], chinese(1, 1))
        add(["lunar new year's eve", "chinese new year's eve", "chuxi", "new year's eve lunar", "reunion dinner"], chinese(1, 1, plus: -1))
        add(["lantern festival", "yuanxiao", "yuan xiao", "shangyuan", "chap goh mei"], chinese(1, 15))
        add(["qingming", "qing ming", "ching ming", "tomb sweeping day", "tomb sweeping festival", "qingming festival"], solarTerm(15, "Asia/Shanghai", near: 4, 5))
        add(["dragon boat festival", "dragon boat", "duanwu", "duan wu", "tuen ng", "double fifth"], chinese(5, 5))
        add(["qixi", "qi xi", "double seventh", "chinese valentine's day", "magpie festival"], chinese(7, 7))
        add(["ghost festival", "hungry ghost festival", "zhongyuan", "zhong yuan", "ullambana", "yu lan"], chinese(7, 15))
        add(["mid autumn festival", "mid-autumn festival", "mooncake festival", "moon festival", "zhongqiu", "zhong qiu", "mid autumn"], chinese(8, 15))
        add(["double ninth", "double ninth festival", "chongyang", "chung yeung", "chung yeung festival"], chinese(9, 9))
        add(["dongzhi", "dong zhi", "winter solstice festival", "tang chak"], solarTerm(270, "Asia/Shanghai", near: 12, 21))
        add(["laba", "laba festival"], chinese(12, 8))
        add(["kitchen god day", "little new year", "xiaonian"], chinese(12, 23))
        add(["jade emperor's birthday", "jade emperor birthday"], chinese(1, 9))
        add(["mazu's birthday", "mazu birthday"], chinese(3, 23))
        add(["guanyin's birthday", "guan yin birthday"], chinese(2, 19))

        // Korean
        add(["seollal", "korean new year", "solnal"], korean(1, 1))
        add(["chuseok", "hangawi", "korean thanksgiving"], korean(8, 15))
        add(["daeboreum", "jeongwol daeboreum"], korean(1, 15))
        add(["korean dano", "dano festival"], korean(5, 5))
        add(["buddha's birthday", "buddhas birthday", "seokga tansinil", "bucheonnim osin nal", "phat dan"], korean(4, 8))

        // Vietnamese
        add(["tet", "tet nguyen dan", "vietnamese new year", "tet holiday"], vietnamese(1, 1))
        add(["tet trung thu", "trung thu", "vietnamese mid autumn"], vietnamese(8, 15))
        add(["vu lan", "le vu lan"], vietnamese(7, 15))
        add(["hung kings", "hung kings festival", "gio to hung vuong"], vietnamese(3, 10))

        // Japanese
        add(["shogatsu", "oshogatsu", "japanese new year"], fixed(1, 1))
        add(["setsubun"], solarTerm(315, "Asia/Tokyo", near: 2, 4, plus: -1))
        add(["hanamatsuri", "kanbutsue"], fixed(4, 8))
        add(["shunbun no hi", "vernal equinox day", "spring equinox", "vernal equinox", "spring higan"], solarTerm(0, "Asia/Tokyo", near: 3, 20))
        add(["shubun no hi", "autumnal equinox day", "autumn equinox", "autumnal equinox", "fall equinox", "autumn higan"], solarTerm(180, "Asia/Tokyo", near: 9, 22))
        add(["tanabata"], fixed(7, 7))
        add(["shichi go san", "shichigosan"], fixed(11, 15))
        add(["bodhi day", "rohatsu"], fixed(12, 8))
        add(["obon", "bon festival"], .note("Obon is in mid-August in most of Japan, but in July in Tokyo and some other regions. Type the date instead, for example, “aug 13 6pm”."))

        // Persian / Central Asian
        add(["nowruz", "norouz", "nauryz", "persian new year", "iranian new year"], persianNewYear)

        // Buddhist (Theravada / Tibetan) — date depends on country or a calendar we can't compute
        add(["vesak", "wesak", "visakha bucha", "vesak day", "buddha purnima", "buddha day", "saga dawa"],
            .note("Vesak falls on different days in different countries. Type the date instead, for example, “may 31 7pm”."))
        add(["losar", "tibetan new year"], unknown("Losar", "follows the Tibetan calendar, which Magic Time can’t compute yet."))
        add(["magha puja", "makha bucha", "asalha puja", "asanha bucha", "kathina", "uposatha"],
            .note("Theravada full-moon holidays vary by country. Type the date instead."))

        // South Asian — regional calendars we don't compute; say so rather than guess
        if #available(macOS 26, iOS 26, *) {
            func hindu(_ festival: HinduFestivals.Festival, _ name: String) -> HolidayEntry {
                .observances(name: name) { now in
                    let year = CivilDay(now, in: HinduFestivals.ist).year
                    return ((year - 1)...(year + 2)).compactMap { HinduFestivals.observance(festival, gregorianYear: $0) }
                }
            }
            add(["diwali", "deepavali", "divali", "deepawali", "lakshmi puja", "laxmi puja"], hindu(.diwali, "Diwali"))
            add(["holi", "rangwali holi", "dhulandi", "dhuleti", "phagwah", "festival of colors", "festival of colours"], hindu(.holi, "Holi"))
            add(["holika dahan", "chhoti holi", "choti holi", "holika"], hindu(.holikaDahan, "Holika Dahan"))
        } else {
            add(["diwali", "deepavali", "divali", "deepawali", "lakshmi puja", "laxmi puja"],
                .note("Calculating Diwali requires macOS 26 or later. Type the date instead, for example, “nov 8 7pm”."))
            add(["holi", "rangwali holi", "dhulandi", "dhuleti", "phagwah", "festival of colors", "festival of colours",
                 "holika dahan", "chhoti holi", "choti holi", "holika"],
                .note("Calculating Holi requires macOS 26 or later. Type the date instead, for example, “mar 4 2pm”."))
        }
        for (names, label) in [(["navratri", "navaratri"], "Navratri"), (["dussehra", "dasara", "vijayadashami"], "Dussehra"),
                               (["raksha bandhan", "rakhi"], "Raksha Bandhan"), (["janmashtami"], "Janmashtami"),
                               (["ganesh chaturthi"], "Ganesh Chaturthi"), (["karva chauth"], "Karva Chauth"),
                               (["pongal", "makar sankranti"], "Makar Sankranti"), (["vaisakhi", "baisakhi"], "Vaisakhi")] {
            add(names, unknown(label, "follows regional Hindu or Sikh calendars that differ by community."))
        }
        add(["songkran", "thai new year"], fixed(4, 13))

        return t
    }()
}

/// Low-precision solar position (Meeus, Astronomical Algorithms ch. 25) — good to about a minute
/// of time around equinoxes, solstices, and the Chinese/Japanese solar terms.
enum Solar {
    static func moment(longitude target: Double, nearYear year: Int, month: Int, day: Int) -> Date? {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        guard let start = cal.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) else { return nil }
        var jd = start.timeIntervalSince1970 / 86_400 + 2_440_587.5
        for _ in 0..<8 {
            var diff = target - apparentLongitude(jd)
            diff = (diff + 540).truncatingRemainder(dividingBy: 360) - 180
            jd += diff * 365.2422 / 360
            if abs(diff) < 1e-6 { break }
        }
        return Date(timeIntervalSince1970: (jd - 2_440_587.5) * 86_400)
    }

    static func apparentLongitude(_ jd: Double) -> Double {
        let t = (jd - 2_451_545.0) / 36_525
        let l0 = 280.46646 + 36_000.76983 * t + 0.0003032 * t * t
        let m = (357.52911 + 35_999.05029 * t - 0.0001537 * t * t) * .pi / 180
        let c = (1.914602 - 0.004817 * t - 0.000014 * t * t) * sin(m)
            + (0.019993 - 0.000101 * t) * sin(2 * m) + 0.000289 * sin(3 * m)
        let omega = (125.04 - 1934.136 * t) * .pi / 180
        let lambda = l0 + c - 0.00569 - 0.00478 * sin(omega)
        return (lambda.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }
}
