# Discord Time

A tiny macOS app that turns plain English like **“tomorrow 9:30am”** into Discord’s
`<t:1790947800:F>` timestamp codes, which every viewer sees in their own time zone.

Press **⌃⌥⌘T** anywhere, type a time, press **↩**, and paste into Discord.

- Understands natural phrases (`fri 2pm`, `10/14 7pm`, `tomorrow 9:30am`), Unix timestamps,
  and existing `<t:…>` codes (paste one in to decode it)
- Previews every Discord format the way Discord draws it, with **⌘1–⌘7** to copy one directly
- Reads times in Eastern, Central, Mountain, Pacific, or UTC
- Spotlight-style floating panel; lives in the menu bar with an optional Open at Login
- Native SwiftUI, Apple frameworks only, fully offline, no Accessibility permission needed

## Build

Requires macOS 14+ and the Xcode Command Line Tools (full Xcode not needed).

```sh
./build.sh               # runs the parser checks, builds, installs to ~/Applications
./build.sh --no-install  # build only, into ./build
```

Then open **Discord Time** from Spotlight once; after that ⌃⌥⌘T summons it.

## Keys

| Key | Action |
|---|---|
| ⌃⌥⌘T | Open or hide from any app |
| ↩ | Copy the highlighted format and close |
| ⌘1–⌘7 | Copy that format and close |
| ↑ ↓ | Change the highlighted format |
| esc / ⌘W | Close |

## Layout

- `Sources/TimeParser.swift` — text → date (via `NSDataDetector`) and Discord format codes
- `Sources/ContentView.swift` — the panel UI
- `Sources/Launcher.swift` — the floating panel and the global hotkey
- `Sources/App.swift` — menu bar app and login item
- `Tools/make_icon.swift` — draws the app icon
- `Tests/main.swift` — parser checks run by `build.sh`
