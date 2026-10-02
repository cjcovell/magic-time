---
name: store-screenshots
description: Retake Magic Time's App Store screenshots on every device size (iPhone 6.9", 6.5", 6.3"; iPad 13", 11"; Mac 2880×1800) with one script, so no size is forgotten. Use whenever the app's look, copy, default settings, or example phrases change, before any App Store submission or build upload, or when asked to "take the screenshots", "retake screenshots", "update the store screenshots", or "screenshots for App Store Connect".
---

# Store screenshots

Every App Store screenshot comes from one script, so each release shows the same six phrases on
every device. Never take them by hand.

## Take them

```sh
scripts/screenshots.sh            # writes ../magic-time-store-assets/screenshots
scripts/screenshots.sh /some/dir  # or a folder you name
```

It takes about five minutes. It builds Debug copies of both apps (the `-MTPrefill` launch argument
only exists in Debug), boots each simulator, sets the 9:41 status bar, launches the app once per
phrase, and saves a PNG. The Mac panel opens on screen for a few seconds per phrase; tell the user
not to type while it runs, because the panel takes keystrokes. If Magic Time was running, the script
reopens the installed copy afterward.

Output folders, each with the same six files:

| Folder | Size | App Store Connect slot |
|---|---|---|
| `iPhone 6.9in` | 1320 × 2868 | iPhone 6.9" Display |
| `iPhone 6.5in` | 1284 × 2778 | iPhone 6.5" Display (scaled from 6.9") |
| `iPhone 6.3in` | 1206 × 2622 | iPhone 6.3" Display (optional, in Media Manager) |
| `iPad 13in` | 2064 × 2752 | iPad 13" Display |
| `iPad 11in` | 1668 × 2420 | iPad 11" Display (optional, in Media Manager) |
| `Mac 2880x1800` | 2880 × 1800 | Mac |

## Check them before uploading

Open one image from each folder and confirm:

- the phrase is filled in and the keyboard is hidden
- the status bar reads 9:41 with full signal and battery
- the footer under the field says what the current build says (it changed once already, from
  “Eastern time” to “your local time”)
- the Mac panel is centered on the backdrop, with the full-date format highlighted
- `6-suggests-a-phrase` shows “Use “15th 8:30pm”” under the field and “Did you mean “15th 8:30pm”?”
  in the middle of the screen. The suggestion comes
  from Apple’s on-device model, so it needs Apple Intelligence turned on for this Mac, and its
  wording can vary; rerun the script if it’s missing or reads oddly

## Change what they show

Edit `PHRASES` and `NAMES` at the top of `scripts/screenshots.sh`; every device follows. Keep one
“won’t guess” phrase and one holiday in the set. Run each new phrase through `magic-time "<phrase>"`
first, so no screenshot shows “No date or time found” by accident.

## Upload

App Store Connect only accepts new screenshots while the version is editable (not while it is
“Waiting for Review” or “In Review”). When replacing a set, use Delete All on that display size
first; uploading on top of an existing set adds to it and can leave duplicates. Upload the files
one at a time, in the order they should appear: several files chosen at once land in a random
order, and the first three are what people see in search results. The order used for 1.0 is
1, 2, 3, 6 (the Apple Intelligence suggestion), 4, 5. Uploading only iPhone 6.9", iPad 13", and Mac
is enough; the smaller sizes fall back to those. The user uploads
iPhone and iPad screenshots themselves unless they ask otherwise.

## If it fails

- “No simulator named …”: the device list at the top of the script names simulators that ship with
  the current Xcode. After an Xcode update, change the names to the current largest and standard
  iPhone and the 13-inch and 11-inch iPad Pro.
- “The Mac panel didn’t open”: quit any running Magic Time and run it again.
- “Python needs Pillow”: run the command it prints. The script checks this before it starts.
