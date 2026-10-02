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

- Read spelled-out times (“eight thirty”, “quarter past seven”) in the reader itself.
- Siri and Shortcuts answer in the zone the phrase named, as the apps now do.

- Localize the app and listing beyond U.S. English.

## Done, waiting for the next App Store update

Version 1.0.1 (build 2), ready to archive once 1.0 clears review:

- The time zone picker starts on the device’s own zone (“Local”) and lists cities worldwide;
  Siri, Shortcuts, and `magic-time --zone` take the same choices.
- A zone named in the text shows the result in that zone, with the chosen zone’s time beside it.
- “now”, “london now”, “now in tokyo”, and “3pm london in tokyo”.
- Times without a colon: “830am”, “1130pm”, “8 30 am”, “fri at 930”; a bare “fri 930” asks.
- Unread spelled-out numbers (“eight thirty”) refuse instead of falling back to “night”.
- Apple Intelligence suggestions for long sentences, accepted by tapping.
- Retake the store screenshots (their footer still says Eastern time), and add the new phrases
  (“tomorrow london noon”, “london now”, “830am”) to the website’s examples when it ships.
