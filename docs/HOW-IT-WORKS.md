# How Magic Time Works

This is the maintainer's guide to the parser: the grammar it accepts, where every holiday date
comes from, how Diwali and Holi are computed and checked, the rules behind "never guesses," and
what (little) needs looking after over time. The README covers using the app; this covers why it
gives the answer it does.

Source of truth is the code. Where this document and the code disagree, the code wins and this
document is wrong; fix it.

## 1. The pipeline

All text goes through one function, `TimeParser.interpret(_:in:now:)` in
`Sources/TimeParser.swift`, which returns a `Reading`:

| Reading | Meaning | What the panel shows |
|---|---|---|
| `.moment(Date)` | One instant | The nine format rows |
| `.note(String)` | A holiday or date it recognizes but won't place | "Magic Time won't guess this one" plus the reason |
| `.nothing` | Nothing it can fully account for | "No date or time found" |

`interpret` tries three readers in order:

1. **An existing Discord code** anywhere in the text: `<t:SECONDS>` or `<t:SECONDS:X>` where `X`
   is one of `t T d D f F s S R`. The seconds may be negative. The code doesn't have to be the
   whole text: `see you <t:1790964000:R> ok` decodes.
2. **A bare Unix timestamp**: the whole trimmed text is an integer at least 9 characters long
   (a leading `-` counts). So `100000000` (1973) decodes; `12345678` does not.
3. **Natural language**, via `NaturalTime(zone:now:).parse`. A moment from here is floored to the
   whole minute. Decoded codes and timestamps keep their seconds.

The zone passed in is the one chosen in the menu: Local (the device's own zone, the default), a U.S.
zone, a city elsewhere, or UTC (`ZoneOption.groups`; remembered in `UserDefaults` under `zone` as an
IANA identifier or `local`). A zone named in the text overrides it.

The same four parser files (`TimeParser`, `NaturalTime`, `Holidays`, `HinduFestivals`) are compiled
into the test runner (`Tests/main.swift`), and into the `magic-time` command (`CLI/main.swift`),
so all three always agree. The command takes `--zone` as a menu label, an IANA ID, or an abbreviation.
Without it, it uses the zone saved by the app. Exit codes: 0 = moment, 2 = note, 1 = nothing,
64 = usage error.

## 2. Natural-language grammar

`Sources/NaturalTime.swift`. The reader is a hand-written, token-by-token matcher, not a regex
over the whole string.

### 2.1 Tokenizing

1. Lowercase, then fold diacritics (`Tết` → `tet`).
2. Normalize `a.m.`/`p.m.` → `am`/`pm`, curly apostrophe → `'`, en and em dashes → `-`.
3. Split time ranges glued with a hyphen when the end carries am/pm: `6-8pm` → `6 - 8pm`.
   ISO dates (`2027-05-15`) and `5-15` are left alone.
4. Split on spaces, commas, semicolons, `@`, parentheses, tabs, and newlines.
5. Trim `.`, `!`, and `?` from the ends of each token (so `Friday 2pm.` works).

### 2.2 Time zones first

Before anything else, every token is checked against the zone vocabulary, so that "today" and
"friday" are computed in the zone the text names. A zone word followed by `time`
(`eastern time`) consumes both tokens. Two different zones in one text (`8pm pt et`) fail.

**A zone word counts only next to a time**: directly before or after a time, `am`/`pm`, `noon`,
`midnight`, `o'clock`, or `time` (`8pm PT`, `PT 8pm`, `8 pm eastern time`). A zone word anywhere else
is ambiguous (`pt session`, `la fitness`, `mt hood`, `rome cafe`), so the whole parse is refused
rather than silently changing the zone.

| Typed | Zone |
|---|---|
| `et est edt eastern nyc` | America/New_York |
| `ct cst cdt central chicago` | America/Chicago |
| `mt mst mdt mountain denver` | America/Denver |
| `pt pst pdt pacific la seattle` | America/Los_Angeles |
| `akst akdt alaska` · `hst hawaii` · `arizona phoenix` | Anchorage · Honolulu · Phoenix |
| `toronto` · `vancouver` | America/Toronto · America/Vancouver |
| `utc` | UTC |
| `gmt bst london` | Europe/London |
| `cet cest paris` · `berlin amsterdam madrid rome stockholm` | Their European zones |
| `ist delhi mumbai` | Asia/Kolkata |
| `jst tokyo` · `kst seoul` · `sgt singapore` · `hkt` | Tokyo · Seoul · Singapore · Hong Kong |
| `aest aedt sydney` · `melbourne` | Australia/Sydney · Australia/Melbourne |
| `nzst nzdt auckland` | Pacific/Auckland |

Abbreviations name a **region**, not a fixed offset: `EST` in July means New York's daylight time,
and `GMT` means London, so `9am gmt` in July is 9 AM British Summer Time. Type `utc` for a fixed
offset. `IST` is India.

### 2.3 Matchers

Unconsumed tokens are offered to these matchers in this order; the first that claims a token wins.

| # | Matcher | Accepts |
|---|---|---|
| 1 | Relative offset | `in N unit`, `N unit from now`, `N unit later`, `in half an hour`. N is 0–9999 or `a an one`…`twelve`. (`couple` works only in `in couple hours`. `in a couple of hours` isn't understood.) Units: minute(s)/min(s), hour(s)/hr(s), day(s), week(s)/wk(s), month(s), year(s). |
| 2 | Holiday | Any catalog name (section 3), optionally prefixed `erev` or followed by `eve`, then optionally a year. |
| 3 | Ordinal weekday | `[the] 1st…5th / first…fifth / last / final WEEKDAY [in/of (MONTH \| the month \| this month \| next month) [YEAR]]`. A year attaches only after an `in`/`of` clause (`2nd tuesday 2027` is refused). With no month, it is this month's, or next month's if that has passed or doesn't exist. |
| 4 | Named day | `today`, `tonight`/`tonite`, `tomorrow` (and `tmrw tmr tmw tomorow tommorow tommorrow`), `yesterday`, `day after tomorrow`, `weekend`, `end of [the/this] month` |
| 5 | This / next | `this WEEKDAY`, `next WEEKDAY [week]`, `WEEKDAY after next`, `this/next weekend`, `next week/month/year`, bare `WEEKDAY` |
| 6 | Month and day | `may 15 [YEAR]`, `15 may`, `15th of may [YEAR]`, `the 15th`, `the 15th of next month`, `[WEEKDAY] the 13th` |
| 7 | Numeric date | `5/15`, `5/15/27`, `5/15/2027`, `5-15`, `2027-05-15`. Slash and hyphen forms are **month first** (US order). |
| 8 | Part of day | `noon`/`midday`, `midnight`, `morning`, `breakfast`, `brunch`, `lunch`, `afternoon`, `evening`, `dinner`, `night` |
| 9 | Time | `6pm`, `6 pm`, `6p`, `6:30`, `6:30pm`, `18:00`, `06:30`, `6 o'clock`, `at 6`, `at 1800`, `half past 6`, `quarter past/after 6`, `quarter to 7`, and ranges `6-8pm`, `6 to 8pm`, `6 until/till/til 8pm` |
| 10 | Filler | `at on the of in by from around about approx approximately starting starts start begins beginning - o'clock oclock time this and for` |

Vocabulary:

- **Weekdays**: `sun sunday suns`, `mon monday mondays`, `tue tues tuesday`, `wed weds wednesday`,
  `thu thur thurs thursday`, `fri friday`, `sat saturday`.
- **Months**: full names and three-letter forms, plus `sept`.
- **Years**: 1900–2199, or `'27` for 2027. A year only attaches to a date or holiday just before it.

### 2.4 How tokens combine

- **One of each.** A day can be set once (a second, different day fails: `friday saturday`).
  A clock time can be set once (`6pm 7pm` and `noon 3pm` fail). A minute or hour offset (`in 3 hours`) is
  an instant and can't be combined with a day or clock time. A part-of-day word next to it is silently
  ignored (`in 3 hours evening` = in 3 hours). Day, week, month, and year offsets set a *day* and do take
  a time (`in 2 weeks at noon`).
- **A weekday next to an explicit date only checks it.** In `fri, may 15`, "fri" doesn't set the
  day; if May 15 isn't a Friday, the result is `.nothing`. `friday the 13th` searches up to 28
  months ahead for a 13th that is a Friday.
- **Unknown words are skipped**, so event titles work (`raid night fri 8pm`). But if a skipped
  token is *meaningful* the whole parse is refused. Meaningful means: it contains a digit; is a
  weekday; is a month other than "may"; is an ordinal other than `first`, `second`, `last`; or is one of
  `next after before ago tomorrow today tonight yesterday noon midnight week weekend month year
  hours minutes days weeks months`. "may" counts as a month only after `in` or `of` (`in may`
  is refused), since elsewhere it is usually the verb (`we may play fri 8pm`).
- **Bare numbers.** `6` alone is not a time. It counts as one only with am/pm, a colon,
  `o'clock`, or a leading `at`; when a day is already set before it (`friday 6`); when the next token
  is a day or part-of-day word, optionally after `on`, `this`, or `next` (`6 friday`, `6 tmrw`,
  `6 tonight`, `8 morning`, `7 this friday`, `6 on friday`); or when it starts a range whose end
  carries am/pm (`6-8pm`, `11-1pm`, `6 to 8pm`). "Before it" means the token right before the number:
  `fri need 3 players` is refused. Anything else is refused too: `bring 2 friends`, `15 raid`, and
  `raid 15` are all `.nothing`. A bare `3rd` is the 3rd of the month only when no word follows it
  (other than am/pm or `at`), so `3rd blursday` is refused.
- **`last friday`** without `in`/`of` is refused: it could mean the previous Friday or the last
  Friday of the month. `5th friday in november` is refused when that month has no fifth Friday.
- **Military time** (`1800`) is read only after `at`: `at 1800 friday` works, `friday 1800` does not.
  A number with no am/pm counts as 24-hour time when it is 0, 13 or more, or written with a leading zero
  (`06:30`).
- **Ranges keep the start.** The start borrows the end's am/pm, except that `11-1pm` starts in the
  morning (the start hour is larger than the end, the end is PM, and the start isn't 12, so `12-2pm`
  starts at noon).

### 2.5 Resolving to one instant

`resolve()` in `NaturalTime.swift`, in order:

1. A relative instant (`in 3 hours`) is the answer as is.
2. Otherwise there must be a day, a time, or a part-of-day word, or the result is `.nothing`.
3. The day defaults to today in the effective zone; the time defaults to the part-of-day time,
   else **noon**. Part-of-day defaults: breakfast 8 AM, morning 9 AM, brunch 11 AM, lunch
   12 PM, afternoon 3 PM, evening and dinner 7 PM, night and tonight 8 PM. Morning and breakfast
   also make a bare hour AM. Afternoon, evening, dinner, night, and tonight make it PM
   (`tonight at 8` is 8 PM). This applies only when the bare hour is otherwise accepted, after `at`
   or attached to a day or part-of-day word: `friday morning 8` and `8 morning` work. If there are several
   part-of-day words, the first sets the default time and the last sets AM/PM.
4. **AM or PM for a bare hour 1–12**:
   - With no explicit day: the next occurrence. AM if that time is still ahead today, else PM.
   - With an explicit day: 12 and 1–6 mean PM, 7–11 mean AM (`friday 12` is noon, `friday 6` is
     6 PM, `friday 8` is 8 AM).
5. `midnight` is the midnight at the *end* of the day: `midnight friday` is Saturday 00:00.
6. Rolling forward: with no explicit day, a time already past today moves to tomorrow (`8am`
   typed at noon is tomorrow 8 AM). A bare weekday that has already passed today moves a week
   (`friday 8am` on a Friday afternoon is next Friday). `this WEEKDAY` never rolls, because next
   week isn't "this": on that weekday, a time already past is refused (`this thursday 8am` typed
   Thursday at noon is `.nothing`).

Relative-day conventions:

| Phrase | Means |
|---|---|
| `friday`, `this friday` | The next Friday on or after today |
| `next friday` | Friday of next calendar week (weeks start Sunday): on a Thursday, 8 days out |
| `friday after next` | A week after `next friday` |
| `weekend`, `this weekend` | The next Saturday on or after today |
| `next weekend` | Saturday of next calendar week |
| `next week` / `next month` / `next year` | Today plus 7 days / 1 month / 1 year |
| `the 15th` | This month's 15th, or next month's if already past |
| `may 15`, `5/15` (no year) | This year's, or next year's if already past |

## 3. Holidays

`Sources/Holidays.swift`. Every name lives in one table, `HolidayCatalog.table`, mapping a
normalized name to a `HolidayEntry`:

- `.days(rule)`: one date per year.
- `.observances(name:rule)`: one date, or two when authorities disagree (Diwali, Holi, Holika Dahan).
- `.note(message)`: known but deliberately not dated.

### 3.1 Matching

- Names are normalized: lowercase, diacritics folded, apostrophes removed, hyphens become spaces,
  whitespace collapsed. `Eid al-Fitr`, `eid al fitr`, and `EID AL-FITR` are the same key.
- The longest name wins: the matcher tries 5-word phrases down to 1 word
  (`HolidayCatalog.longestName`, computed from the table).
- `erev X` or `X eve` means the day before. `christmas eve` is its own entry, so
  `christmas eve eve` is December 23.
- A following year picks that Gregorian year's occurrence (`eid al-adha 2027`). With `eve` or `erev`,
  the year names the holiday, not its eve: `erev rosh hashanah 2027` is the evening before 2027's Rosh
  Hashanah. (`new year's eve` is its own entry, so `new year's eve 2027` is Dec 31, 2027.) Without one, the
  next occurrence on or after today in the effective zone. For a two-date year, the year still
  counts as upcoming until its second date has passed.
- Each rule produces occurrences for the Gregorian years from one before to two after the anchor
  year. For calendar-system holidays, it's one lunar year before to two after.
- A holiday is a **civil day**, read as that date in the effective zone. `lunar new year 7pm PT`
  is 7 PM Pacific on the date of Lunar New Year in China, not 7 PM in Beijing.
- With no time given, holidays resolve to noon.

### 3.2 Where each calendar's dates come from

| Group | Source | Notes |
|---|---|---|
| US civic | Gregorian rules: fixed dates and nth-weekday rules | New Year's Day/Eve, Valentine's, St Patrick's, Mother's Day (2nd Sun May), Memorial Day (last Mon May), Father's Day, Juneteenth, July 4, Labor Day, Halloween, Veterans Day, Thanksgiving (4th Thu Nov), Black Friday. Also Canadian Thanksgiving (2nd Mon Oct) and UK Mothering Sunday (Easter − 21). |
| Western Christian | **Anonymous Gregorian computus** (Meeus/Jones/Butcher), our own arithmetic | Easter and its offsets: Mardi Gras −47, Ash Wednesday −46, Palm Sunday −7, Maundy Thursday −3, Good Friday −2, Holy Saturday −1, Easter Monday +1, Ascension +39, Pentecost +49, Whit Monday +50, Trinity +56, Corpus Christi +60. Fixed feasts (Christmas, Epiphany, All Saints…) are Gregorian dates. First Sunday of Advent = the 4th Sunday before Christmas. |
| Orthodox Christian | **Julian computus**, shifted by the Julian–Gregorian gap `year/100 − year/400 − 2` (13 days now, 14 from 2100) | Orthodox Easter, Good Friday, Palm Sunday, Pentecost, Clean Monday (−48). Orthodox Christmas (Jan 7) and Theophany (Jan 19) are **fixed Gregorian dates**. |
| Jewish | Apple `Calendar(.hebrew)`, evaluated in Asia/Jerusalem | Gives the first full day; `erev` gives the evening before. Months as Foundation numbers them: 1 Tishrei … 6 Adar I (leap years), 7 Adar/Adar II, 8 Nisan … 13 Elul. `seder` is 14 Nisan (the evening of the first seder). Tisha B'Av moves to Sunday when 9 Av is Shabbat. |
| Islamic | Apple `Calendar(.islamicUmmAlQura)`, evaluated in Asia/Riyadh | Saudi Umm al-Qura dates. Communities that follow local moon sighting can differ by a day. Islamic New Year, Ashura, Mawlid, Isra and Mi'raj, Shab-e-Barat, Ramadan (1 Ramadan), Laylat al-Qadr (27 Ramadan), Eid al-Fitr, Day of Arafah, Eid al-Adha. |
| Chinese | Apple `Calendar(.chinese)`, Asia/Shanghai, never the leap month | Lunar New Year (and its eve = day before), Lantern, Dragon Boat, Qixi, Ghost Festival, Mid-Autumn, Double Ninth, Laba, Kitchen God, Jade Emperor, Mazu, Guanyin. |
| Chinese solar terms | Sun's apparent longitude (Meeus ch. 25), date taken in Asia/Shanghai | Qingming = 15°, Dongzhi = 270°. |
| Korean | Apple `Calendar(.dangi)`, Asia/Seoul, **macOS 26+** | Seollal, Daeboreum, Dano, Chuseok, Buddha's Birthday (8th day of the 4th lunar month). On macOS 14–25 these fall back to the Chinese calendar evaluated in Seoul, which can be a day off (Seollal 2027: fallback Feb 6, Dangi Feb 7). |
| Vietnamese | Apple `Calendar(.vietnamese)`, Asia/Ho_Chi_Minh, **macOS 26+** | Tết, Trung Thu, Vu Lan, Hung Kings. Same Chinese-calendar fallback before macOS 26. |
| Japanese | Solar longitude, date taken in Asia/Tokyo; fixed Gregorian dates otherwise | Vernal (0°) and autumnal (180°) equinox days; Setsubun = the day before Risshun (315°). Fixed: Shōgatsu Jan 1, Hanamatsuri Apr 8, Tanabata Jul 7, Shichi-Go-San Nov 15, Bodhi Day Dec 8. |
| Persian | Apple `Calendar(.persian)`, Asia/Tehran | Nowruz = 1 Farvardin. |
| Thai | Fixed Gregorian date | Songkran Apr 13. |
| Hindu | Apple `Calendar(.marathi)` to find the lunar month, then Sun and Moon positions at New Delhi. **macOS 26+** | Diwali (Lakshmi Puja), Holika Dahan, Holi. Section 4. Before macOS 26, `diwali`/`deepavali`/`divali`/`deepawali`, `holi`, and `holika dahan` return a note saying macOS 26 is required. The other aliases (`lakshmi puja`, `rangwali holi`, `chhoti holi`…) aren't recognized. |

Two consequences worth knowing:

- **The equinox names give Japan's holiday date.** `spring equinox`, `vernal equinox`,
  `autumn equinox`, and `fall equinox` are aliases for Shunbun no Hi and Shūbun no Hi, dated in Tokyo.
  Tokyo's date is a day later than the Americas' whenever the equinox falls between 15:00 UTC and
  local midnight in the Americas. In 2027 the March equinox (20:24 UTC) is March 20 in New York, but
  `spring equinox 2027` gives March 21. The September equinox (05:56 UTC) is Sept 22 in Los Angeles,
  but `fall equinox 2027` gives Sept 23.
- **Some generic names resolve to one country's date.** `thanksgiving`, `mother's day`, and
  `labor day`/`labour day` are the US dates. `buddha's birthday` is the East Asian lunar date,
  while `vesak` is a note.

### 3.3 Names that return a note instead of a date

| Name(s) | Why |
|---|---|
| `eid`, `eid mubarak` | Which Eid? |
| `independence day` | Depends on the country (suggests `fourth of july`) |
| `festival of lights` | Hanukkah or Diwali |
| `obon`, `bon festival` | Mid-August in most of Japan, July in Tokyo and some other regions |
| `vesak`, `wesak`, `visakha bucha`, `buddha purnima`, `saga dawa`… | Different days in different countries |
| `magha puja`, `asalha puja`, `kathina`, `uposatha`… | Theravada full-moon days vary by country |
| `losar`, `tibetan new year` | Tibetan calendar not computed |
| `navratri`, `dussehra`, `raksha bandhan`, `janmashtami`, `ganesh chaturthi`, `karva chauth`, `pongal`/`makar sankranti`, `vaisakhi` | Regional Hindu or Sikh calendars that differ by community |
| Any Diwali/Holi/Holika Dahan year where authorities split | "falls on X or Y, depending on the almanac you follow" |

Not every bare word is a holiday. `advent` alone is deliberately not in the table, so
`advent of code sat 8pm` stays a Saturday. Use `advent sunday` or `first sunday of advent`.

## 4. Diwali and Holi: the almanac method

`Sources/HinduFestivals.swift`, available on macOS 26 and later. Hindu festivals are set by the
*tithi* (lunar day) in force at a particular time of day, and almanacs (panchangs) don't always agree.
Magic Time computes them the way an almanac does, for **New Delhi**
(28.6139° N, 77.2090° E, IST), instead of shipping a table.

### 4.1 Building blocks

- **Tithi.** The Moon's longitude minus the Sun's (the elongation), 0–360°, in 12° steps.
  Amavasya (new-moon tithi) is 348°–360°. Purnima (full-moon tithi) is 168°–180°. Bhadra (the
  inauspicious Vishti karana) during Purnima is its first half, 168°–174°.
- **Moon longitude**: Meeus, *Astronomical Algorithms*, ch. 47, Table 47.A longitude terms plus
  the A1/A2 additive terms and the main nutation term (−0.00478° sin Ω). **Sun longitude**: Meeus ch. 25 low-precision
  apparent longitude. Both are evaluated in Terrestrial Time with a fixed ΔT of 69 s. The solar
  terms in section 3.2 use the same Sun formula in UT, without ΔT, which is harmless at day resolution.
- **Sunrise and sunset**: NOAA solar equations, upper limb with standard refraction (zenith
  90.833°), iterated three times on the event time.
- **Units**: a *ghati* is 24 minutes. *Pradosh Kaal* is taken as 6 ghatis (2 h 24 m) after sunset. A
  *prahar* is a quarter of the daylight span.
- **Finding the right month.** Apple's amanta lunisolar calendar (`Calendar(.marathi)`, Śaka
  era) names lunar months, including leap (adhika) months. Diwali is anchored on the day labeled
  1 Kartika (month 8), searched September–December. Holika Dahan is anchored on 15 Phalguna
  (month 12), searched February–April. Leap months are skipped. If the exact label is skipped
  (a dropped tithi), the nearest label within 2 days is used.

### 4.2 Diwali (Lakshmi Puja)

The evening on which Amavasya prevails at sunset, looking at the five evenings from 3 days before
to 1 day after the anchor:

| Evenings with Amavasya at sunset | Result |
|---|---|
| One | That evening |
| Two | If Amavasya ends less than 1 ghati after the second sunset → the **first**. If it lasts through the whole Pradosh of the second evening → the **second**. (2025: Amavasya covered sunset on Oct 20 and 21 but ended within a ghati of the second, so Oct 20.) In between → **both**, reported as a note (2024: Oct 31 per DoPT, Nov 1 per Drik Panchang). |
| None (a short tithi that starts after one sunset and ends before the next) | The evening it starts on if it begins within that evening's Pradosh, otherwise the next day. This search covers 3 days before to 2 after the anchor. |
| More than two | No result |

### 4.3 Holika Dahan and Holi

1. Take the first evening (anchor ± 2 days) on which Purnima prevails at sunset, or the
   short-tithi rule above.
2. Find "midnight" as the midpoint between that sunset and the next sunrise. If Bhadra is not in
   force at midnight, that evening is Holika Dahan.
3. If Bhadra runs past midnight, look at the next day: if Purnima still holds after 3½ of its four
   prahars (7/8 of daylight), the bonfire moves to the **next** evening (Drik Panchang: 2016,
   2023, 2026). If it holds for 3 prahars but not 3½, almanacs and the Government of India split.
   Both are reported (2027: Drik Mar 21, DoPT Mar 22). Otherwise it stays on the first evening, in
   Bhadra Punchha (2022). In the 2027 split, Drik's Mar 21 is that same first evening.
4. **Holi** (Rangwali Holi, the colors) is the day after Holika Dahan. When Holika Dahan is split,
   Holi is split the same way.

### 4.4 Reference validation

`Tests/main.swift` checks the computed observances against published dates. The Hindu checks run only
when the test runner itself runs on macOS 26 or later. The Korean check (`seollal` → 2027-02-07,
`Tests/main.swift:114`) is *not* guarded, and the pre-26 fallback gives Feb 6. So `build.sh` currently
needs a macOS 26+ host to pass (see 6.4):

- **2015–2035**: Diwali, Holika Dahan, and Holi for every year, against Drik Panchang (New Delhi)
  and Government of India (DoPT) holiday lists. Two split years are encoded as `a|b` and must come out
  as two dates: Diwali 2024 (`10-31|11-01`) and Holika Dahan/Holi 2027 (`03-21|03-22`,
  `03-22|03-23`).
- **Short-tithi years** where the tithi misses every sunset, against Drik Panchang: Diwali 2036, 2046,
  2055, 2065, 2074, 2075, 2098, 2099. Holika Dahan and Holi 2046 and 2065.
- **End-to-end parses** pinned to Thursday, October 1, 2026, 12:00 PM Eastern: `diwali 7pm` and `lakshmi puja` →
  Nov 8 2026, `holi 2023` → Mar 8, `holika dahan 2026` → Mar 3, and `holi` and `diwali 2024` return
  notes.
- **Long-range stability** (all dated holidays, not just Hindu): for each year 2026–2100, every
  dated rule must still produce an occurrence, and consecutive occurrences must be 320–400 days
  apart. This catches a rule that stops resolving or drifts. It does not check correctness against
  any outside source.

Scope limits: dates are India's (New Delhi sunset). Panchangs computed for other cities,
including North American temple calendars, can land a day apart. The method covers these three
festivals only. Others in section 3.3 are notes.

## 5. The never-guess policy

The parser's contract is: **a wrong date is worse than no date.** If the parser can't account
for every meaningful part of the text, the answer is `.nothing`. If it recognizes a date it can't
place honestly, the answer is a `.note` that explains why and suggests typing the date.

The parser refuses (`.nothing`):

- A leftover meaningful token (section 2.4), such as a number or a weekday it couldn't use.
- Two different days, two clock times, two zones, or a relative instant with a day or time.
- A date that doesn't exist (`feb 30`, `2027-02-30`, `13/5`, `5th friday in november`).
- A weekday that contradicts its date (`thu oct 2` when Oct 2 is a Friday).
- An ambiguous phrase: `last friday`, a bare number (`8`), `in may`.
- A year outside 1900–2199.

It explains instead of answering (`.note`) when:

- A holiday has no single date (`eid`, `vesak`, `obon`, `independence day`…; section 3.3).
- Authorities disagree that year (Diwali 2024, Holi 2027).
- The OS can't compute it (Diwali/Holi before macOS 26).

It doesn't count these documented conventions as guesses. If you change one, update this list
and the tests:

- Default time noon. Part-of-day defaults. Bare-hour AM/PM rules (section 2.5).
- Past times roll forward. `next friday` means next calendar week.
- Numeric dates are month-first.
- Islamic dates follow Umm al-Qura. Hindu dates follow New Delhi. Lunar holidays follow the home
  country's calendar and zone.
- `thanksgiving`, `mother's day`, and `labor day` are US dates. The equinox names are Japan's
  holidays.
- A two-day almanac split is never resolved by picking one.

## 6. Maintenance expectations

### 6.1 What should never need updating

- Every holiday is a **rule**, not a table of dates. Easter (both computuses), the Apple calendar
  systems, the solar terms, and the Diwali/Holi method all extend indefinitely. The stability test
  runs every dated rule through 2100 on every build.
- The Julian–Gregorian gap formula already handles 2100 (`orthodox easter 2100` is tested).

### 6.2 What will need attention eventually

| Item | Where | When / why |
|---|---|---|
| ΔT constant (69 s) | `Astronomy.julianDayTT` | Correct for the 2020s–2030s. Real ΔT drifts. Each minute of error moves tithi boundaries by roughly a minute, which only matters when a tithi ends within minutes of sunset or a ghati threshold. Revisit when extending the reference table past ~2040, or replace with a ΔT polynomial. |
| Orthodox Christmas / Theophany | `Holidays.swift` (`fixed(1, 7)`, `fixed(1, 19)`) | Correct while the Julian–Gregorian gap is 13 days. It grows to 14 in March 2100, when the Julian calendar adds a 29 February that the Gregorian calendar skips. From Christmas 2100 (Gregorian Jan 8, 2101) these need the same gap formula as Orthodox Easter. That is past the test horizon, so no test will catch it. |
| Year range | `Vocabulary.year` | Typed years are 1900–2199. |
| macOS 26 gates | `Holidays.swift`, `HinduFestivals.swift` | Korean/Vietnamese calendars and Diwali/Holi need macOS 26. If the deployment target (now macOS 14) is ever raised to 26, delete the fallbacks and the "requires macOS 26" notes. |
| Diwali/Holi reference table | `Tests/main.swift` | When DoPT publishes each year's holiday list, check that year's row. If a new kind of almanac split appears, add the year as `a|b` and adjust the rule. Don't special-case the year. |
| Apple calendar behavior | All `Calendar(identifier:)` rules | A macOS update could change an Apple calendar (Umm al-Qura tables, Chinese leap-month edge cases). The pinned tests and the stability check run on every build and will flag this. |
| Policy-made holidays | Civic table | Governments change holidays (new US federal days, Japanese equinox days are announced each year but computed here). Edit the table when this happens. |

### 6.3 Adding or changing a holiday

1. Add the names with `add([...], rule)` in the right section of `HolidayCatalog.table`. Include
   common spellings. Normalization handles case, accents, apostrophes, and hyphens.
2. Use an existing rule builder: `fixed`, `nth`, `easter(plus:orthodox:)`, `hebrew`, `islamic`,
   `chinese`, `korean`, `vietnamese`, `solarTerm`, or the generic `lunar`.
3. If the date depends on the country or community, use `.note` (or `unknown(_:_:)`) instead of
   choosing a date.
4. Check that no new name swallows a common word. A one-word name (`holika`, `laba`, `tet`) matches
   anywhere in the text. This is why bare `advent` is deliberately not a name. The same applies to zone
   words (section 2.2).
5. Add a `check` or `checkNote` to `Tests/main.swift`. The long-range stability check picks up
   every new dated rule automatically.
6. Run `./build.sh --no-install`. It stops if any parser check fails.

### 6.4 Known issues (as of 2026-10-01)

All seven issues the documentation audit found on 2026-10-01 are fixed, each with tests:

- Bare numbers followed by a word were read as times (`bring 2 friends` → 2 PM).
- `12` on a named day was midnight.
- Zone words matched anywhere (`la fitness fri 8pm` → Pacific time).
- `eve`/`erev` with a year matched the year against the shifted date.
- `this WEEKDAY` could return a moment already past.
- Before macOS 26, Hindu aliases other than the main names leaked through (`lakshmi puja 7pm`).
- The Korean and Vietnamese checks weren't limited to macOS 26, so `build.sh` failed on older hosts.

The dead `@` handling (the tokenizer already splits on `@`) was removed.
