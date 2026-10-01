import Foundation

/// Diwali and Holi, computed the way Hindu almanacs (panchangs) do it rather than from a table.
///
/// - Apple's amanta lunisolar calendar (Marathi, Śaka era) names the lunar month, including
///   leap (adhika) months, so we pick the right new or full moon.
/// - The festival day is then set by the lunar day (tithi) in force at **sunset in New Delhi**:
///   Diwali (Lakshmi Puja) is the evening the new-moon tithi (Amavasya) prevails; Holika Dahan is
///   the evening the full-moon tithi (Purnima) prevails, and Holi's colors are the next day.
/// - When the tithi covers sunset on two evenings, almanacs and governments split (Diwali 2024:
///   Oct 31 or Nov 1). We report both instead of choosing.
@available(macOS 26, iOS 26, *)
enum HinduFestivals {
    enum Festival { case diwali, holikaDahan, holi }

    static let delhi = (latitude: 28.6139, longitude: 77.2090)
    static let ist = TimeZone(identifier: "Asia/Kolkata")!

    static func observance(_ festival: Festival, gregorianYear year: Int) -> Observance? {
        switch festival {
        case .diwali:
            // Amavasya ending nija (non-leap) Ashvin = around Kartika 1.
            guard let anchor = lunarDay(month: 8, day: 1, inGregorianYear: year, months: 9...12) else { return nil }
            return diwali(near: anchor)
        case .holikaDahan:
            guard let anchor = lunarDay(month: 12, day: 15, inGregorianYear: year, months: 2...4) else { return nil }
            return holikaDahan(near: anchor)
        case .holi:
            guard let dahan = observance(.holikaDahan, gregorianYear: year) else { return nil }
            return Observance(day: dahan.day.adding(days: 1), alternative: dahan.alternative?.adding(days: 1))
        }
    }

    /// One ghati (24 minutes), the unit the almanac rules are written in.
    private static let ghati: TimeInterval = 24 * 60
    /// Pradosh Kaal: about 2 h 24 m after sunset.
    private static let pradosh: TimeInterval = 6 * ghati

    /// Lakshmi Puja: the evening Amavasya (elongation 348°–360°) prevails at Pradosh.
    /// If it covers sunset on two evenings, the second wins only when Amavasya lasts at least a
    /// ghati past that sunset (Drik Panchang / Dharma Sindhu). If it lasts a ghati but not the whole
    /// Pradosh, India genuinely splits (2024: Oct 31 or Nov 1), so both are reported.
    private static func diwali(near anchor: CivilDay) -> Observance? {
        let amavasya: (Double) -> Bool = { $0 >= 348 && $0 < 360 }
        let evenings = (-3...1).map { anchor.adding(days: $0) }.filter { day in
            sunset(day).map { amavasya(Astronomy.elongation(at: $0)) } ?? false
        }
        switch evenings.count {
        case 1:
            return Observance(day: evenings[0], alternative: nil)
        case 2:
            guard let second = sunset(evenings[1]) else { return nil }
            let throughGhati = amavasya(Astronomy.elongation(at: second.addingTimeInterval(ghati)))
            let throughPradosh = amavasya(Astronomy.elongation(at: second.addingTimeInterval(pradosh)))
            if !throughGhati { return Observance(day: evenings[0], alternative: nil) }
            if throughPradosh { return Observance(day: evenings[1], alternative: nil) }
            return Observance(day: evenings[0], alternative: evenings[1])
        case 0:
            return shortTithiEvening(near: anchor, tithiStart: 348).map { Observance(day: $0, alternative: nil) }
        default:
            return nil
        }
    }

    /// Holika Dahan: the evening Purnima (168°–180°) prevails at Pradosh, avoiding Bhadra (its first
    /// half, 168°–174°). If Bhadra on that evening runs past midnight and Purnima still holds for
    /// 3½ prahars of the next day, the bonfire moves to the next evening (Drik Panchang: 2016,
    /// 2023, 2026); otherwise it stays, in Bhadra Punchha (2022).
    private static func holikaDahan(near anchor: CivilDay) -> Observance? {
        let purnima: (Double) -> Bool = { $0 >= 168 && $0 < 180 }
        let bhadra: (Double) -> Bool = { $0 >= 168 && $0 < 174 }
        guard let first = (-2...2).map({ anchor.adding(days: $0) }).first(where: { day in
            sunset(day).map { purnima(Astronomy.elongation(at: $0)) } ?? false
        }) ?? shortTithiEvening(near: anchor, tithiStart: 168) else { return nil }

        let next = first.adding(days: 1)
        guard let dusk = sunset(first), let dawn = sunrise(next), let nextDusk = sunset(next) else { return nil }
        let midnight = dusk.addingTimeInterval(dawn.timeIntervalSince(dusk) / 2)
        let bhadraPastMidnight = bhadra(Astronomy.elongation(at: midnight))
        guard bhadraPastMidnight else { return Observance(day: first, alternative: nil) }
        // Move to the next evening if Purnima holds for 3½ of the next day's four prahars (Drik
        // Panchang). Holding 3 but not 3½ is where almanacs and the Government of India split
        // (2027: Drik Mar 21, DoPT Mar 22), so both are reported.
        let daylight = nextDusk.timeIntervalSince(dawn)
        let threeAndAHalf = purnima(Astronomy.elongation(at: dawn.addingTimeInterval(daylight * 0.875)))
        let three = purnima(Astronomy.elongation(at: dawn.addingTimeInterval(daylight * 0.75)))
        if threeAndAHalf { return Observance(day: next, alternative: nil) }
        if three { return Observance(day: first, alternative: next) }
        return Observance(day: first, alternative: nil)
    }

    /// When a tithi starts after one sunset and ends before the next, it never "prevails at sunset".
    /// Drik Panchang then takes the evening it starts on if it begins within that evening's Pradosh,
    /// otherwise the next day (checked for Diwali 2036–2099 and Holika Dahan 2046, 2065).
    private static func shortTithiEvening(near anchor: CivilDay, tithiStart: Double) -> CivilDay? {
        for offset in -3...2 {
            let day = anchor.adding(days: offset)
            guard let dusk = sunset(day), let nextDusk = sunset(day.adding(days: 1)) else { continue }
            let before = (tithiStart - Astronomy.elongation(at: dusk) + 360).truncatingRemainder(dividingBy: 360)
            let after = (Astronomy.elongation(at: nextDusk) - tithiStart + 360).truncatingRemainder(dividingBy: 360)
            guard before > 0, before < 12, after >= 12, after < 24 else { continue }
            let inPradosh = (Astronomy.elongation(at: dusk.addingTimeInterval(pradosh)) - tithiStart + 360)
                .truncatingRemainder(dividingBy: 360) < 12
            return inPradosh ? day : day.adding(days: 1)
        }
        return nil
    }

    private static func sunset(_ day: CivilDay) -> Date? {
        Astronomy.sunEvent(on: day, rising: false, latitude: delhi.latitude, longitude: delhi.longitude)
    }

    private static func sunrise(_ day: CivilDay) -> Date? {
        Astronomy.sunEvent(on: day, rising: true, latitude: delhi.latitude, longitude: delhi.longitude)
    }

    /// The Gregorian day (in India) that Apple's amanta calendar labels `month/day` (non-leap),
    /// searching the given Gregorian months; skipped lunar days fall back to the nearest label.
    private static func lunarDay(month: Int, day: Int, inGregorianYear year: Int, months: ClosedRange<Int>) -> CivilDay? {
        var amanta = Calendar(identifier: .marathi)
        amanta.timeZone = ist
        var gregorian = Calendar(identifier: .gregorian)
        gregorian.timeZone = ist
        guard let start = gregorian.date(from: DateComponents(year: year, month: months.lowerBound, day: 1, hour: 12)),
              let end = gregorian.date(from: DateComponents(year: year, month: months.upperBound + 1, day: 1, hour: 12))
        else { return nil }

        var best: (distance: Int, day: CivilDay)?
        var date = start
        while date < end {
            let p = amanta.dateComponents([.month, .day], from: date)
            if p.month == month, p.isLeapMonth != true, let d = p.day {
                let distance = abs(d - day)
                if best == nil || distance < best!.distance { best = (distance, CivilDay(date, in: ist)) }
            }
            date = gregorian.date(byAdding: .day, value: 1, to: date)!
        }
        return best.flatMap { $0.distance <= 2 ? $0.day : nil }
    }
}

/// Sun and Moon positions (Meeus, *Astronomical Algorithms*, ch. 15, 25, 47) — accurate to well
/// under a minute of tithi timing, which is what festival dates turn on.
enum Astronomy {
    /// Moon minus Sun apparent longitude, 0…360°. Tithis are 12° steps of this angle.
    static func elongation(at date: Date) -> Double {
        let jd = julianDayTT(date)
        let diff = moonLongitude(jd) - Solar.apparentLongitude(jd)
        return (diff.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Julian Day in Terrestrial Time (ΔT ≈ 69 s for the 2020s–2030s).
    static func julianDayTT(_ date: Date) -> Double {
        date.timeIntervalSince1970 / 86_400 + 2_440_587.5 + 69.0 / 86_400
    }

    /// Apparent geocentric longitude of the Moon, degrees.
    static func moonLongitude(_ jd: Double) -> Double {
        let t = (jd - 2_451_545.0) / 36_525
        let lp = 218.3164477 + 481_267.88123421 * t - 0.0015786 * t * t + t * t * t / 538_841 - t * t * t * t / 65_194_000
        let d = 297.8501921 + 445_267.1114034 * t - 0.0018819 * t * t + t * t * t / 545_868 - t * t * t * t / 113_065_000
        let m = 357.5291092 + 35_999.0502909 * t - 0.0001536 * t * t + t * t * t / 24_490_000
        let mp = 134.9633964 + 477_198.8675055 * t + 0.0087414 * t * t + t * t * t / 69_699 - t * t * t * t / 14_712_000
        let f = 93.2720950 + 483_202.0175233 * t - 0.0036539 * t * t - t * t * t / 3_526_000 + t * t * t * t / 863_310_000
        let e = 1 - 0.002516 * t - 0.0000074 * t * t
        let rad = Double.pi / 180

        var sum = 0.0
        for term in moonTerms {
            var coefficient = Double(term.l)
            if abs(term.m) == 1 { coefficient *= e } else if abs(term.m) == 2 { coefficient *= e * e }
            sum += coefficient * sin((Double(term.d) * d + Double(term.m) * m + Double(term.mp) * mp + Double(term.f) * f) * rad)
        }
        let a1 = 119.75 + 131.849 * t, a2 = 53.09 + 479_264.290 * t
        sum += 3958 * sin(a1 * rad) + 1962 * sin((lp - f) * rad) + 318 * sin(a2 * rad)

        let omega = 125.04452 - 1934.136261 * t
        let nutation = -0.00478 * sin(omega * rad)
        return lp + sum / 1_000_000 + nutation
    }

    /// Meeus Table 47.A: multiples of D, M, M′, F and the longitude coefficient (10⁻⁶ degrees).
    private static let moonTerms: [(d: Int, m: Int, mp: Int, f: Int, l: Int)] = [
        (0, 0, 1, 0, 6_288_774), (2, 0, -1, 0, 1_274_027), (2, 0, 0, 0, 658_314), (0, 0, 2, 0, 213_618),
        (0, 1, 0, 0, -185_116), (0, 0, 0, 2, -114_332), (2, 0, -2, 0, 58_793), (2, -1, -1, 0, 57_066),
        (2, 0, 1, 0, 53_322), (2, -1, 0, 0, 45_758), (0, 1, -1, 0, -40_923), (1, 0, 0, 0, -34_720),
        (0, 1, 1, 0, -30_383), (2, 0, 0, -2, 15_327), (0, 0, 1, 2, -12_528), (0, 0, 1, -2, 10_980),
        (4, 0, -1, 0, 10_675), (0, 0, 3, 0, 10_034), (4, 0, -2, 0, 8_548), (2, 1, -1, 0, -7_888),
        (2, 1, 0, 0, -6_766), (1, 0, -1, 0, -5_163), (1, 1, 0, 0, 4_987), (2, -1, 1, 0, 4_036),
        (2, 0, 2, 0, 3_994), (4, 0, 0, 0, 3_861), (2, 0, -3, 0, 3_665), (0, 1, -2, 0, -2_689),
        (2, 0, -1, 2, -2_602), (2, -1, -2, 0, 2_390), (1, 0, 1, 0, -2_348), (2, -2, 0, 0, 2_236),
        (0, 1, 2, 0, -2_120), (0, 2, 0, 0, -2_069), (2, -2, -1, 0, 2_048), (2, 0, 1, -2, -1_773),
        (2, 0, 0, 2, -1_595), (4, -1, -1, 0, 1_215), (0, 0, 2, 2, -1_110), (3, 0, -1, 0, -892),
        (2, 1, 1, 0, -810), (4, -1, -2, 0, 759), (0, 2, -1, 0, -713), (2, 2, -1, 0, -700),
        (2, 1, -2, 0, 691), (2, -1, 0, -2, 596), (4, 0, 1, 0, 549), (0, 0, 4, 0, 537),
        (4, -1, 0, 0, 520), (1, 0, -2, 0, -487), (2, 1, 0, -2, -399), (0, 0, 2, -2, -381),
        (1, 1, 1, 0, 351), (3, 0, -2, 0, -340), (4, 0, -3, 0, 330), (2, -1, 2, 0, 327),
        (0, 2, 1, 0, -323), (1, 1, -1, 0, 299), (2, 0, 3, 0, 294),
    ]

    /// Sunrise or sunset (upper limb, standard refraction) on a civil day at a place east of
    /// Greenwich, NOAA solar equations, iterated on the event time itself.
    static func sunEvent(on day: CivilDay, rising: Bool, latitude: Double, longitude: Double) -> Date? {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        guard let noonUTC = utc.date(from: DateComponents(year: day.year, month: day.month, day: day.day, hour: 12)) else {
            return nil
        }
        var estimate = noonUTC.addingTimeInterval(-longitude / 15 * 3600 + (rising ? -6 : 6) * 3600)
        for _ in 0..<3 {
            let jd = estimate.timeIntervalSince1970 / 86_400 + 2_440_587.5
            let (declination, equationOfTime) = solarDeclinationAndEoT(jd)
            let rad = Double.pi / 180
            let cosH = (cos(90.833 * rad) - sin(latitude * rad) * sin(declination * rad))
                / (cos(latitude * rad) * cos(declination * rad))
            guard abs(cosH) <= 1 else { return nil }
            let hourAngle = (rising ? -1 : 1) * acos(cosH) / rad
            let minutesUTC = 720 - 4 * (longitude - hourAngle) - equationOfTime
            estimate = noonUTC.addingTimeInterval((minutesUTC - 720) * 60)
        }
        return estimate
    }

    private static func solarDeclinationAndEoT(_ jd: Double) -> (Double, Double) {
        let t = (jd - 2_451_545.0) / 36_525
        let rad = Double.pi / 180
        let l0 = (280.46646 + t * (36_000.76983 + 0.0003032 * t)).truncatingRemainder(dividingBy: 360)
        let m = 357.52911 + t * (35_999.05029 - 0.0001537 * t)
        let e = 0.016708634 - t * (0.000042037 + 0.0000001267 * t)
        let c = sin(m * rad) * (1.914602 - t * (0.004817 + 0.000014 * t))
            + sin(2 * m * rad) * (0.019993 - 0.000101 * t) + sin(3 * m * rad) * 0.000289
        let omega = 125.04 - 1934.136 * t
        let lambda = l0 + c - 0.00569 - 0.00478 * sin(omega * rad)
        let epsilon0 = 23 + (26 + (21.448 - t * (46.815 + t * (0.00059 - t * 0.001813))) / 60) / 60
        let epsilon = epsilon0 + 0.00256 * cos(omega * rad)
        let declination = asin(sin(epsilon * rad) * sin(lambda * rad)) / rad
        let y = pow(tan(epsilon * rad / 2), 2)
        let eot = 4 / rad * (y * sin(2 * l0 * rad) - 2 * e * sin(m * rad) + 4 * e * y * sin(m * rad) * cos(2 * l0 * rad)
            - 0.5 * y * y * sin(4 * l0 * rad) - 1.25 * e * e * sin(2 * m * rad))
        return (declination, eot)
    }
}
