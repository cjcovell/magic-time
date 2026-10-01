# Documentation Audit Report
Generated: 2026-10-01 | Commit: c980140 + uncommitted working tree (README, Sources, Tests, build.sh modified; `Sources/HinduFestivals.swift`, `CLI/`, `skill/` untracked)
Audited on macOS 27.0.1, Xcode 27.0. Parser checks: **528 pass** at audit start; **538 pass** after the concurrent session's fixes.

> **Status at close (15:30).** A concurrent session was editing the code and README while this audit ran. It picked up this report's findings and has already **fixed B1 and B2** (with tests), the stale `⌘1–⌘7` comment, the `dragon boat` alias, and **7 of the 8 README findings**. The README tables below describe the README *as first audited* (15:03). See "Re-audit of revised README" for the current state. HOW-IT-WORKS.md has been updated to match the fixed code.

Scope: `README.md` and `docs/HOW-IT-WORKS.md` (new). Behavior claims were checked by running the real parser
(the four parser sources compiled with a probe, with `now` pinned to Thu 2026-10-01 12:00 ET like the tests), not by reading alone.

## Executive Summary

| Metric | README.md | HOW-IT-WORKS.md |
|---|---|---|
| Claims verified | ~70 | ~235 (incl. ~200 probe phrases) |
| Verified TRUE | ~62 | ~222 |
| **False or imprecise** | **8** | **13 (all corrected in place)** |
| Human review (Tier 3) | 6 | see below |

Plus **7 code issues** surfaced while verifying behavior claims (B1–B7). B1 directly breaks the README's "never guesses" promise, and so do B5 and B6 to a lesser degree.

## Code bugs found during verification

These are not documentation errors. The docs describe the intended behavior and the code doesn't deliver it.

Status: **B1 FIXED**, **B2 FIXED** (both with new tests, `Tests/main.swift:193-199`). B3–B7 are **open**.

| # | Where | Behavior | Evidence | Suggested fix |
|---|---|---|---|---|
| B1 | `Sources/NaturalTime.swift:574` (`matchTime`) | **A bare number followed by any word becomes a time.** `token(k + 1).map(Meridiem.init) == nil` maps a failable init, giving `Meridiem??`. When a next token exists that's `.some(nil)`, which is never `== nil`, so the "bare number needs a day word" guard is skipped. | `bring 2 friends` → today 2:00 PM · `15 raid` → today 3:00 PM · `top 10 list` → today 10:00 PM · `need 3 players fri` → Fri 3:00 PM. Only the trailing case is refused (`raid 15` → nothing), and that's the only case the tests cover (`Tests/main.swift:191`). | **Not a one-liner.** Switching to `flatMap` alone was tried on a scratch copy. It also refuses `6-8pm`, `6 to 8pm`, `11-1pm sat` (existing test, `Tests/main.swift:53`), `6 tonight`, `8 morning`, `7 this friday`, `6 on friday`, which work today only *because of* the bug. Use `flatMap` plus explicit acceptance when the next token is a range separator followed by a time, a tomorrow spelling, `tonight`, a part-of-day word, or `this`/`next`/`on` + weekday. Add tests for both sides. |
| B2 | `Sources/NaturalTime.swift:636-639` (`resolve`) | **`12` on a named day is midnight at the start of that day.** The rule "1–6 → PM, else AM" sends 12 to AM, i.e. 00:00. | `friday 12`, `friday at 12`, `12 friday` → Fri 00:00. On the same weekday it then rolls a week: `thursday 12` typed Thursday → **next** Thursday 00:00. (`at 12` with no day → today 12:00 PM, which is correct.) | Treat 12 as PM (noon) on a named day, or refuse it. Add a test. |
| B3 | `NaturalTime.swift:121-131` (`markTimeZones`) | **Zone words match anywhere**, including inside event titles. | `pt session fri 9am` → 9 AM Pacific · `la fitness fri 8pm` → 8 PM Pacific · `mt hood hike sat 9am` → Mountain. | Policy call: require zone words to sit next to a time, or drop the riskiest short keys (`la`, `mt`, `pt`, `et`, `ct`) from the anywhere-match. |
| B4 | `NaturalTime.swift:218-224` (`pick`) | With `eve`/`erev`, the typed year is compared with the **shifted** date. | `new year eve 2027` and `erev new year 2027` → Dec 31 **2027**. | Match the year before shifting. |
| B5 | `NaturalTime.swift:370-371` | `this WEEKDAY` never rolls forward, so a passed time on today's weekday is returned in the past. | `this thursday 8am` typed Thursday at noon → today 08:00 (4 hours ago). | Roll a week, or refuse. |
| B6 | `Holidays.swift:360-363` | Before macOS 26, only the main Diwali/Holi names get the "requires macOS 26" note. Other aliases aren't meaningful words, so they're skipped. | `lakshmi puja 7pm` → 7 PM today on macOS 14–25 (by reading the code; it can't be run on this macOS 27 host). | Add every alias to the pre-26 note lists. |
| B7 | `Tests/main.swift:114` | The `seollal` → Feb 7 2027 check isn't wrapped in `#available(macOS 26, *)`. The pre-26 fallback gives Feb 6, so `build.sh` fails on a macOS 14–25 build host. | Fallback computed directly: Feb 6. | Guard the Korean and Vietnamese checks. |

Minor: in `matchRelativeOffset`, `in a couple of hours` isn't understood (`couple` only works in `in couple hours`). A part-of-day word next to `in N hours` is silently dropped. `@` is a tokenizer separator, so the `@` filler and `token() == "@"` checks are dead code.

Related stale code comment: `Sources/Launcher.swift:72` said "⌘1–⌘7". The concurrent session fixed it to "⌘1–⌘9" during the audit.

## False Claims Requiring Fixes

### README.md

| Line | Claim | Reality | Fix |
|---|---|---|---|
| 23 | Holidays "computed from Apple's own calendar systems" | Only the Hebrew, Islamic (Umm al-Qura), Chinese, Dangi, Vietnamese, Persian, and Marathi calendars are Apple's. Western and Orthodox Easter (and everything offset from them) use the project's own computus (`Holidays.swift:98-114`). Qingming, Dongzhi, Setsubun, and the equinox days use the project's own Meeus solar math (`Holidays.swift:376-403`). Diwali and Holi are set by the project's own Sun/Moon astronomy (`HinduFestivals.swift:144-242`); Apple's calendar only locates the month. | "computed on your Mac from Apple's calendar systems and standard astronomical algorithms, so there's nothing to keep updated" |
| 24 | "Advent" listed as a holiday | Typing `advent` returns nothing. It's deliberately not a name, so `advent of code` isn't read as a holiday (`Tests/main.swift:195`). Only `first sunday of advent`, `advent sunday`, and `start of advent` work. | "…Ash Wednesday, the first Sunday of Advent, Pentecost…" |
| 27 | "Dragon Boat" listed | `dragon boat` returns nothing. The table has `dragon boat festival`, `duanwu`, `tuen ng`, `double fifth`, but not `dragon boat` (`Holidays.swift:303`). | Add `"dragon boat"` as an alias (preferred), or write "Dragon Boat Festival" |
| 23-28 | Holiday list (gap) | Diwali, Holi, and Holika Dahan, the most complex holidays in the app, aren't listed in Features. They only appear in Layout and Tests. Also unlisted: Orthodox Christmas, Canadian Thanksgiving, UK Mothering Sunday, Songkran, Tisha B'Av, Japanese fixed festivals. | Add "Hindu (Diwali, Holi, and Holika Dahan, worked out the way almanacs do; macOS 26 or later)" |
| 29-30 | "Never guesses: anything it can't fully account for shows an empty state" | False for leading or mid-text numbers. See **B1**: `bring 2 friends` → 2 PM today. | Fix B1. The claim is true once it's fixed. |
| 56 | "Requires macOS 14+ and Xcode" (build side also hit by B7: the parser checks fail on a macOS 14–25 build host) | Two requirements are mixed up. **Running** the app needs macOS 14 or later on **Apple silicon**: build.sh compiles `-target arm64-apple-macos14.0`, and the binary is arm64 only (verified with `lipo`). **Building** needs **Xcode 26 or later**: the sources use `Calendar.Identifier.marathi/.dangi/.vietnamese`, which are `@available(macOS 26)` in the SDK, and `actool` must compile an Icon Composer `.icon`. On macOS 14–25, Diwali and Holi are notes, and Korean and Vietnamese holidays fall back to the Chinese calendar (Seollal 2027: Feb 6 instead of Feb 7). | "Runs on macOS 14 or later (Apple silicon). Building needs Xcode 26 or later. Diwali and Holi, and exact Korean and Vietnamese lunar dates, need macOS 26." |
| 60 | `--no-install` = "build only, into ./build" | It still runs the parser checks first and stops if they fail (`build.sh:16-19`). Since today's working tree it also builds the `magic-time` command. | "test and build into ./build, without installing" |
| 85-86 | Tests "include every dated holiday for every year through 2100" | The long-range test (`Tests/main.swift:220-239`) checks 2026–2100, and only that each rule keeps producing a date at a 320–400-day spacing. It doesn't check those dates against any source. Also, "more than 500" holds only when the test runner runs on macOS 26 or later. Below that, the 81 Hindu checks and 17 Hindu dated rules drop out (~430 checks). | "…a check that every dated holiday keeps resolving, year by year, through 2100…" |

### HOW-IT-WORKS.md

This doc was written in this session, so an independent agent that hadn't written it did the audit. It found 13
false or imprecise claims, all corrected in place, and I re-verified the key ones with the probe:

| Doc § | Was | Corrected to |
|---|---|---|
| 6.4 | B1 fix = `flatMap` + `isTomorrow` | That fix breaks ranges (scratch-copy test). Full acceptance list given |
| 6.4 | `friday 12` → Friday 00:00 | Also rolls a week on the same weekday (`thursday 12`) |
| 4.3 | Bhadra Punchha "(2022, 2027 Drik)" | Only 2022 takes the stay branch. 2027 is the split branch (same comment slip at `HinduFestivals.swift:68`) |
| 3.2 | Tokyo is a day later "when the equinox falls after 15:00 UTC" | Also when it falls early in the UTC day (Sept 2027: Sept 22 LA, Sept 23 Tokyo) |
| 2.5 | Part-of-day words set AM/PM for a bare hour | Only when the bare hour is otherwise accepted. `morning 8` is refused |
| 2.3 | `couple` is a number word | Works only in `in couple hours` |
| 2.3 | Ordinal weekday `… [YEAR]` | A year attaches only after an in/of clause |
| 2.4 | Relative instant can't combine with day or time | Only minute/hour offsets are instants. Part-of-day is silently dropped. Day+ offsets take a time |
| 3.1 | Year picks that year's occurrence | With `eve`/`erev`, the year matches the shifted date (B4) |
| 4.1 | "nutation in longitude" | Only the main −0.00478° sin Ω term |
| 4.4 | Reference checks run only on macOS 26+ | True for the Hindu checks. The Seollal check is unguarded (B7) |
| 3.2 | Pre-26 Hindu aliases "aren't recognized" | They're silently skipped, and `lakshmi puja 7pm` → 7 PM today (B6) |
| 2.5 | Rolling forward | `this WEEKDAY` never rolls (B5) |

Gaps the agent found, now documented: zone words match anywhere (§2.2, B3), the CLI's `--zone`
handling and exit codes (§1), multiple part-of-day words, and solar terms evaluated in UT.

## Re-audit of revised README (modified 15:25)

Fixed from the first pass: L23 "Apple's own calendar systems" (now "Apple's calendar systems and standard astronomical algorithms"), "Advent" (now "the first Sunday of Advent"), "Dragon Boat" (alias added, and "Dragon Boat Festival" in the text), Hindu festivals added to Features, build requirements split into run (macOS 14+ Apple silicon) and build (Xcode 26+), `--no-install` described correctly, and the test description ("keeps resolving year by year through 2100"). The never-guess claim now holds for B1.

New and remaining findings:

| Line | Claim | Reality | Fix |
|---|---|---|---|
| 34 | "US and Canadian civic holidays" | The only Canadian holiday is Canadian Thanksgiving (`Holidays.swift:229`). There's no Canada Day, Victoria Day, or Civic Holiday. | "US civic holidays and Canadian Thanksgiving", or add the Canadian civic days |
| 35-37 | "Never guesses: anything it can't fully account for shows an empty state" | Still false in some cases: B3 (`la fitness fri 8pm` → Pacific time), B5 (`this thursday 8am` → a past moment), B6 (pre-26 `lakshmi puja 7pm` → 7 PM today). | Fix B3, B5, B6 |
| 96-98 | Building needs Xcode 26 (implies any host that runs it) | Xcode 26 runs on macOS 15.6+, but on a macOS 15 host the unguarded Seollal test (B7) fails, so `build.sh` stops. | Fix B7, or say "build on macOS 26 or later" |
| 82, 101 | `build.sh` installs `magic-time` to `~/.local/bin` | ✓ `build.sh:70-72` | none |
| 85 | CLI prints "every format, plus how it was read" | ✓ "Read as …" line (`CLI/main.swift:86`) | none |
| 90 | Exit codes 0 / 2 / 1 | ✓ (plus 64 for usage errors, `CLI/main.swift:40-61`, not mentioned) | Optional: mention 64 |
| 75-76 | "Make a Discord Timestamp" in Spotlight, Siri, Shortcuts, Action button; iPad ⌘1–⌘9 | ✓ intent title (`iOS/TimestampIntents.swift:7`), `AppShortcut` (`:86`), keyboard shortcuts (`iOS/MagicTimeApp.swift:16`) | none |
| 77, 108 | iPhone Duo layout; "Supporting iPhone Duo fully needs Xcode 27.1" | `iOS/RootView.swift:94` mentions Duo. The Xcode 27.1 requirement appears nowhere in `project.yml` or `docs/APP-STORE-PLAN.md`. | Tier 3: confirm against Apple's docs |
| 107 | iOS builds from `project.yml` with XcodeGen | ✓ `project.yml` (iOS deployment target 17.0, not stated in README) | Optional: state iOS 17+ |
| 122 | "more than 500 parser checks" | ✓ 538 on macOS 26+ (about 440 below that) | none |
| 118-125 | Layout entries for `iOS/`, `CLI/`, `skill/`, `docs/` | ✓ all exist | none |

## Pattern Summary (Pass 2A expansion)

| Pattern | Count | Root cause |
|---|---|---|
| Holiday category names that aren't typeable names (`Advent`, `Dragon Boat`) | 2 of 34 names checked | The README's holiday list uses display names, not table keys. All 34 listed names were run through the parser; the other 32 resolve or explain. |
| Stale "how many formats" counts (`⌘1–⌘7`) | 1 (code comment, since fixed) | Seven formats became nine (commit 583e16f). `Launcher.swift:72` lagged, then was fixed concurrently. |
| "Apple calendar" credited for self-computed dates | 2 (README L23, L79 partly) | L79 says "plus solar terms" but leaves out the Easter computus. Minor. |
| Platform requirements stated for one OS only | 3 (README L56; macOS 26 gates for Hindu, Korean, Vietnamese not mentioned) | The macOS 26 calendar features arrived after the README's build section was written. |
| Test-guard blind spot (number position) | 1 (B1) | The "bare number" regression test only covers a trailing number. |

## Gap Detection (Pass 2B: in code, not in README)

- **Manual adjustment**: the status row's `DatePicker` lets you fix the parsed date and time by hand (`ContentView.swift:135-143`). Not documented.
- **Remembered settings**: the zone and the selected format persist (`UserDefaults` keys `zone`, `style`).
- **Panel zone menu choices**: Eastern, Central, Mountain, Pacific, UTC (`TimeParser.swift:10-16`). README says only "the menu".
- **Zone words match anywhere in the text** (B3): `la fitness fri 8pm` is read as Pacific time. Not in README; now in HOW-IT-WORKS §2.2.
- **Typed zone vocabulary**: about 70 words; abbreviations mean regions (`GMT` = London, so `9am gmt` in July is BST; `IST` = India). Now covered in HOW-IT-WORKS §2.2.
- **Panel hides when it loses focus** (`Launcher.swift:38-46`).
- **`magic-time` command and `skill/`**: added by a concurrent session (untracked, built by build.sh). Not in README Layout yet. Left alone during this audit because it's in flight.

## Human Review Queue (Tier 3)

- [ ] README L31 "the way Discord draws them": previews use this Mac's zone and locale through Foundation formatters (`TimeParser.swift:96-120`, commented "Roughly what Discord renders"). Consider "close to how Discord draws them".
- [ ] README L44/L50: confirm Discord currently supports the `s` and `S` styles and renders them as shown. Can't be verified offline.
- [ ] README L46: the `R` example "in 2 days" depends on when you read it. Fine as an illustration.
- [ ] README L23 "nothing to keep updated": broadly true (all rules, no date tables), but see HOW-IT-WORKS §6.2: the fixed ΔT of 69 s, Orthodox Christmas/Theophany as fixed Jan 7/19 (off by a day from Christmas 2100), and governments changing holidays.
- [ ] Never-guess policy edges, which are conventions rather than bugs but worth a deliberate decision: `labour day` (British/Commonwealth spelling) gives the **US** September date; `buddha's birthday` gives the Korean lunar date while `vesak` refuses; the equinox names give **Japan's** holiday date (`spring equinox 2027` → Mar 21, though the equinox is Mar 20 in the Americas); macOS 14–25 Korean and Vietnamese fallback can be a day off.
- [ ] Diwali/Holi reference values (2015–2035 and the short-tithi years 2036–2099) are attributed to Drik Panchang and DoPT. Spot-checked from memory against well-known years (Diwali 2023 Nov 12, 2024 Oct 31/Nov 1, 2025 Oct 20, 2026 Nov 8; Holi 2024 Mar 25, 2025 Mar 14, 2026 Mar 4). These agree, but the far-future short-tithi rows weren't checked against the source.

## Method notes

- Pass 1: README claims were checked by hand, plus a 34-name holiday sweep and about 120 probe phrases. HOW-IT-WORKS was checked by an independent agent that hadn't written it (~235 claims, ~200 probe phrases, branch instrumentation of the Holika Dahan rule, and a scratch-copy trial of the proposed B1 fix).
- Pass 2A: false claims were expanded into grep sweeps (format counts, macOS/Xcode versions, year ranges, Drik/DoPT attributions) and into phrase-family probes: number position, hour 12, zone abbreviations in summer.
- Nothing in `Sources/`, `Tests/`, `build.sh`, or `README.md` was edited. Another session was changing them during the audit.
