# Magic Time: Chat Timestamps

Type **“Friday 2pm.”** Everyone in the channel sees it in their own time — 2 PM in New York,
11 AM in LA, 7 PM in London. No time-zone math, ever.

Magic Time is a tiny macOS app that turns plain English into Discord timestamp codes like
`<t:1790964000:F>`. Press **⌃⌥⌘T** anywhere, type a time, press **↩**, and paste.

## How the magic works

Behind every code is a single number: the seconds since midnight UTC on January 1, 1970 —
[Unix time](https://en.wikipedia.org/wiki/Unix_time), the clock computers have been counting
since the Nixon administration. That number names the same instant everywhere on Earth, so the
message only has to carry the number; each reader’s Discord app turns it into their local time,
date format, and 12/24-hour preference. Magic Time turns your words into that number.

## Features

- **Reads the way you talk**: `tomorrow 9:30am`, `tmrw 8p`, `fri 6-8pm`,
  `3rd friday in may at 6pm`, `last friday of the month`, `friday after next`, `friday the 13th`,
  `in 2 hours`, `the 15th of next month`, `5/15 6:30`, `half past 6`, `noon`, `tonight`
- **Time zones in the text** override the menu: `6pm PT`, `8pm eastern`, `7pm london`, `9am UTC`
- **Holidays across calendars**, computed from Apple’s own calendar systems — nothing to keep updated:
  Christian (Western and Orthodox: Easter, Ash Wednesday, Advent, Pentecost…), Jewish (Rosh Hashanah,
  Yom Kippur, Hanukkah, Passover, “erev …”, “seder”), Islamic (Ramadan, Eid al-Fitr, Eid al-Adha,
  Ashura, Mawlid — Umm al-Qura), Chinese, Korean, and Vietnamese lunar holidays (Lunar New Year, Tết,
  Seollal, Mid-Autumn, Chuseok, Dragon Boat, Qingming…), Japanese (Setsubun, equinox days),
  Nowruz, and US civic holidays
- **Never guesses**: anything it can’t fully account for shows an empty state, and holidays without
  one agreed date (Vesak, Obon, a bare “Eid”) explain why instead of picking one
- Previews all nine Discord styles the way Discord draws them, with **⌘1–⌘9** to copy one directly
- Decodes Unix timestamps and existing `<t:…>` codes
- Spotlight-style floating panel; lives in the menu bar as `<t:>`, with an optional Open at Login
- Native SwiftUI, Apple frameworks only, fully offline, no data collected, no Accessibility permission

## The nine styles

| Style | Discord shows | Description |
|---|---|---|
| `F` | Friday, October 2, 2026 at 2:00 PM | Full date, short time |
| `f` | October 2, 2026 at 2:00 PM | Long date, short time (Discord’s default) |
| `s` | 10/2/2026, 2:00 PM | Short date, short time |
| `t` | 2:00 PM | Short time |
| `R` | in 2 days | Relative time — a live countdown |
| `D` | October 2, 2026 | Long date |
| `d` | 10/2/2026 | Short date |
| `T` | 2:00:00 PM | Medium time |
| `S` | 10/2/2026, 2:00:00 PM | Short date, medium time |

Examples are for a US-English reader; every viewer sees their own locale’s format.

## Build

Requires macOS 14+ and Xcode (for `actool`, which compiles the Icon Composer icon).

```sh
./build.sh               # runs the parser checks, builds, installs to /Applications
./build.sh --no-install  # build only, into ./build
```

Then open **Magic Time** from Spotlight once; after that ⌃⌥⌘T summons it.

## Keys

| Key | Action |
|---|---|
| ⌃⌥⌘T | Open or hide from any app |
| ↩ | Copy the highlighted style and close |
| ⌘1–⌘9 | Copy that style and close |
| ↑ ↓ | Change the highlighted style |
| esc / ⌘W | Close |

## Layout

- `Sources/TimeParser.swift` — entry point and the timestamp styles
- `Sources/NaturalTime.swift` — the natural-language date reader
- `Sources/Holidays.swift` — holiday rules on Apple’s calendar systems, plus solar terms
- `Sources/ContentView.swift` — the panel UI
- `Sources/Launcher.swift` — the floating panel and the global hotkey
- `Sources/App.swift` — menu bar app and login item
- `Icon/AppIcon.icon` — the app icon; open it in Icon Composer to edit the layers
- `Tests/main.swift` — 400+ parser checks run by `build.sh`, pinned to a fixed date, including
  every dated holiday resolved for every year through 2100

## License

MIT — see [LICENSE](LICENSE). Not affiliated with or endorsed by Discord Inc.
