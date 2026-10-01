# Magic Time

Turns plain English (“fri 2pm eastern”) into Discord timestamp codes (`<t:UNIX:STYLE>`). One shared
parser powers four front ends: the Mac menu bar app, the iPhone and iPad app, the `magic-time`
command, and the Claude skill in `skill/magic-time`.

## Commands

- `./build.sh --no-install`: runs the parser checks (`Tests/main.swift`), then builds the Mac app
  and the `magic-time` command into `build/`. `./build.sh` also installs them.
- `xcodegen generate`: regenerates `MagicTime.xcodeproj` from `project.yml` (the iOS target and the
  sandboxed Mac App Store target, `MagicTime-macOS`). Edit `project.yml`, never the generated project.
- `build.sh` deletes `build/` first, so keep archives and store screenshots somewhere else.
- Screenshots: `-MTPrefill "phrase"` works in Debug builds of both apps (add `-style F` on Mac).
- App Store export or upload: `xcodebuild -exportArchive` fails with a “Copy failed” packaging
  error when Homebrew’s rsync comes first in `PATH`. Prefix the command with
  `PATH="/usr/bin:/bin:/usr/sbin:/sbin:$PATH"`.
- Each App Store upload needs a higher `CURRENT_PROJECT_VERSION` in `project.yml`.

## Rules

- The parser never guesses. Ambiguous input returns a note explaining why; add a check for it.
- Every parser change gets a check in `Tests/main.swift`. Checks are pinned to 2026-10-01.
- Apple frameworks only, fully offline. No packages, no network, no analytics.
- Discord has nine timestamp styles (t T d D f F s S R); the apps list them F f s t R D d T S.
- Describe the parser on its own terms; don’t compare it to other apps by name.
- Say “not affiliated with Discord Inc.” wherever Discord is named in marketing copy.
- The website lives in `site/` and deploys to GitHub Pages on push. Its privacy policy must stay
  true to the code: update `site/privacy.html` if the app starts storing or sending anything new.

## Layout

`Sources/` holds the shared parser (`TimeParser`, `NaturalTime`, `Holidays`, `HinduFestivals`) and the
Mac app; `iOS/` is the iPhone and iPad app with its App Intents; `CLI/` is the command; `docs/`
holds how it works, the App Store plan, and audits.
