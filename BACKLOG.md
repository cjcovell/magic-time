# Backlog

Known gaps and planned work, roughly in priority order.

## Before or soon after the App Store launch

- **Time zone picker is U.S.-only.** The picker offers Eastern, Central, Mountain, Pacific, and UTC
  (`ZoneOption.all` in `Sources/TimeParser.swift`) and starts on Eastern for everyone. Someone in
  London or Tokyo has to type their zone into every phrase. Start on the device’s own time zone,
  label it plainly (for example, “Local (London)”), and let people pick any zone.
- **Unknown event names are skipped instead of refused.** “super bowl sunday 6pm” reads as the next
  Sunday, because unknown words are skipped. That breaks the never-guess rule: when skipped words
  look like an event or holiday name, show a note instead of a time. Add checks for it.
- **Mac App Store build.** Sandbox the Mac app, add it to the `project.yml` targets, and upload it
  so the listing is a Universal Purchase.
- **Screenshots** for iPhone (6.5-inch) and iPad, from the simulator with `-MTPrefill`.
- **China mainland availability** needs an ICP filing number, or China removed from availability.

## Later

- Show the store listing’s familiar U.S. holidays (Christmas, Thanksgiving, the Fourth of July,
  Valentine’s Day) alongside the cross-calendar ones in examples, so every audience sees itself.
- Localize the app and listing beyond U.S. English.
