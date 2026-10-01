# Contributing

Thanks for helping make Magic Time read times better.

## Reporting a time it reads wrong

[Open an issue](https://github.com/cjcovell/magic-time/issues/new) with:

- exactly what you typed
- the time zone picked in the app
- what you expected, and what Magic Time showed (or the note it gave instead)
- the platform: Mac, iPhone, iPad, or the `magic-time` command

For a holiday, link a source for the date you expect. Magic Time won’t guess: if a holiday has no
single agreed date in a given year, it shows a note instead of a time, and that’s on purpose.

## Building and testing

You need a Mac with Xcode 26 or later.

```sh
./build.sh --no-install   # runs the parser checks, then builds the Mac app and the magic-time command into ./build
./build.sh                # the same, then installs both
```

The parser checks in `Tests/main.swift` (more than 500) run first and stop the build if any fail.
They’re pinned to a fixed date, so results don’t change from day to day.

The iPhone and iPad app builds from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen):
run `xcodegen generate`, then open `MagicTime.xcodeproj`.

## Changing the parser

- Add a check to `Tests/main.swift` for every phrase you fix or add, including phrases that should
  produce a note rather than a time.
- Never make the parser guess. When the input can mean more than one moment, return a note that
  explains why.
- Keep to Apple’s frameworks: no third-party packages, and nothing that needs a network connection.
- Holiday rules are computed, not looked up, so they keep working without yearly updates. Check new
  rules against published dates across many years.

## Pull requests

Keep each pull request to one change, describe what it fixes, and make sure `./build.sh --no-install`
passes. By contributing, you agree your work is released under the [MIT License](LICENSE).
