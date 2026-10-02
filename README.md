# Magic Time: Chat Timestamps

Type **“Friday 2pm.”** Everyone in the channel sees it in their own time: 2 PM in New York,
11 AM in LA, 7 PM in London. No time-zone math, ever.

Magic Time turns plain English into Discord timestamp codes like `<t:1790964000:F>`. It comes as a
Mac menu bar app (press **⌃⌥⌘T** anywhere, type a time, press **↩**, and paste), an iPhone and iPad
app (in progress for the App Store), a `magic-time` command, and a Claude skill. All of them share
one parser, so they always agree.

## How the magic works

Behind every code is a single number: the seconds since midnight UTC on January 1, 1970.
It’s called [Unix time](https://en.wikipedia.org/wiki/Unix_time), and computers have been counting it
since the Nixon administration. That number names the same instant everywhere on Earth, so the
message only has to carry the number; each reader’s Discord app turns it into their local time,
date format, and 12/24-hour preference. Magic Time turns your words into that number.

## Features

- **Reads the way you talk**: `tomorrow 9:30am`, `tmrw 8p`, `fri 6-8pm`,
  `3rd friday in may at 6pm`, `last friday of the month`, `friday after next`, `friday the 13th`,
  `in 2 hours`, `the 15th of next month`, `5/15 6:30`, `half past 6`, `noon`, `tonight`, `830am`,
  `fri at 930`
- **Time zones in the text** override the menu, and the result is shown in that zone with your
  own time beside it: `6pm PT`, `8pm eastern`, `tomorrow london noon`, `9am UTC`
- **Quick conversions**: `london now`, `now in tokyo`, `3pm london in tokyo`
- **Holidays across calendars**, computed on your device from Apple’s calendar systems and standard
  astronomical algorithms, so there’s nothing to keep updated:
  - Christian, Western and Orthodox: Easter, Ash Wednesday, the first Sunday of Advent, Pentecost,
    and more
  - Jewish: Rosh Hashanah, Yom Kippur, Hanukkah, Passover, Purim, plus “erev …” and “seder”
  - Islamic, using the Umm al-Qura calendar: Ramadan, Eid al-Fitr, Eid al-Adha, Ashura, Mawlid
  - Hindu: Diwali, Holi, and Holika Dahan, worked out the way almanacs do (macOS 26 or iOS 26 or later)
  - Chinese, Korean, and Vietnamese lunar holidays: Lunar New Year, Tết, Seollal, Mid-Autumn,
    Chuseok, Dragon Boat Festival, Qingming
  - Japanese (Setsubun, the equinox days), Nowruz, US civic holidays, and Canadian Thanksgiving
- **Never guesses**: anything it can’t fully account for shows an empty state, and holidays without
  one agreed date (Vesak, Obon, a bare “Eid”, or a year when almanacs disagree, like Diwali 2024)
  explain why instead of picking one
- Previews all nine Discord timestamp formats the way Discord draws them, with **⌘1–⌘9** to copy one
- Decodes Unix timestamps and existing `<t:…>` codes
- **A second opinion for long sentences**: on devices with Apple Intelligence, Apple’s on-device
  model can suggest a shorter phrase (“Did you mean ‘15th 8:30pm pt’?”). The reader must understand
  the suggestion on its own, and nothing changes unless you accept it
- Native SwiftUI, Apple frameworks only, fully offline, no data collected

## The nine formats

Discord calls these timestamp styles. The letter goes at the end of the code, as in `<t:1790964000:F>`.

| Letter | Discord shows | Description |
|---|---|---|
| `F` | Friday, October 2, 2026 at 2:00 PM | Full date, short time |
| `f` | October 2, 2026 at 2:00 PM | Long date, short time (Discord’s default) |
| `s` | 10/2/2026, 2:00 PM | Short date, short time |
| `t` | 2:00 PM | Short time |
| `R` | in 2 days | Relative time (a live countdown) |
| `D` | October 2, 2026 | Long date |
| `d` | 10/2/2026 | Short date |
| `T` | 2:00:00 PM | Medium time |
| `S` | 10/2/2026, 2:00:00 PM | Short date, medium time |

Examples are for a US-English reader; every viewer sees their own locale’s format.

## Mac app

A Spotlight-style floating panel that lives in the menu bar as `<t:>`, with an optional Open at
Login. It needs no Accessibility permission.

| Key | Action |
|---|---|
| ⌃⌥⌘T | Open or hide from any app |
| ↩ | Copy the highlighted format and close |
| ⌘1–⌘9 | Copy that format and close |
| ↑ ↓ | Select a different format |
| esc or ⌘W | Close |

## iPhone and iPad app

Type a time, then tap a format to copy it. **Make a Discord Timestamp** is also available in
Spotlight, Siri, Shortcuts, and the Action button. On iPad with a keyboard, ⌘1–⌘9 copy a format.
The layout adapts to iPhone Duo’s inner and outer displays. App Store plans are in
[docs/APP-STORE-PLAN.md](docs/APP-STORE-PLAN.md).

## Command line and Claude skill

`build.sh` also installs a `magic-time` command to `~/.local/bin`:

```sh
magic-time "3rd friday in may at 6pm"           # every format, plus how it was read
magic-time "fri 8pm PT" --format t              # one format
magic-time "lunar new year 7pm" --zone pacific --json
```

It exits with 0 when it finds a time, 2 when it won’t guess (and prints why), and 1 when it finds
nothing. The Claude skill in [`skill/magic-time`](skill/magic-time/SKILL.md) uses it, so Claude never
works out Unix times by hand. Link it into `~/.claude/skills` to use it.

## Build

The Mac app runs on macOS 14 or later on Apple silicon. Building needs Xcode 26 or later (the
sources use Apple’s macOS 26 calendars, and `actool` compiles the Icon Composer icon). On macOS 14
through 25, Diwali and Holi show a note, and Korean and Vietnamese holidays use the Chinese calendar.

```sh
./build.sh               # runs the parser checks, then builds and installs the app and the command
./build.sh --no-install  # runs the parser checks and builds into ./build, without installing
```

Then open **Magic Time** from Spotlight once; after that ⌃⌥⌘T summons it.

The iPhone and iPad app builds from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen):
run `xcodegen generate`, then open `MagicTime.xcodeproj`. Supporting iPhone Duo fully needs Xcode 27.1.

## Layout

- `Sources/TimeParser.swift`: the entry point and the timestamp formats
- `Sources/NaturalTime.swift`: the natural-language date reader
- `Sources/Holidays.swift`: holiday rules, using Apple’s calendar systems, the Easter computus, and
  solar terms
- `Sources/HinduFestivals.swift`: Diwali and Holi from the Indian calendars and Sun and Moon positions
- `Sources/ContentView.swift`, `Sources/Launcher.swift`, `Sources/App.swift`: the Mac app
- `iOS/`: the iPhone and iPad app and its App Intents
- `CLI/main.swift`: the `magic-time` command
- `skill/magic-time/`: the Claude skill
- `Icon/AppIcon.icon`: the app icon (open it in Icon Composer to edit the layers)
- `Tests/main.swift`: more than 500 parser checks that `build.sh` runs, pinned to a fixed date. They
  check that every dated holiday keeps resolving year by year through 2100, and they check Diwali
  and Holi against Drik Panchang and Government of India holiday lists
- `docs/`: how it works, the App Store plan, and documentation audits

## License

MIT. See [LICENSE](LICENSE). Magic Time isn’t affiliated with or endorsed by Discord Inc.
