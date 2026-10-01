# Backlog

Known gaps and planned work, roughly in priority order.

## Before or soon after the App Store launch

- **Unknown event names are skipped instead of refused.** “super bowl sunday 6pm” reads as the next
  Sunday, because unknown words are skipped. That breaks the never-guess rule: when skipped words
  look like an event or holiday name, show a note instead of a time. Add checks for it.
- **Mac App Store build.** Sandbox the Mac app, add it to the `project.yml` targets, and upload it
  so the listing is a Universal Purchase.
- **Screenshots** for iPhone (6.5-inch) and iPad, from the simulator with `-MTPrefill`.
- **China mainland availability** needs an ICP filing number, or China removed from availability.

## Later

- Localize the app and listing beyond U.S. English.

## Done, waiting for the next App Store update

- The time zone picker starts on the device’s own zone (“Local”) and lists cities worldwide;
  Siri, Shortcuts, and `magic-time --zone` take the same choices. Ship it as 1.0.1 with a new
  build number, and retake the store screenshots (their footer still says Eastern time).
