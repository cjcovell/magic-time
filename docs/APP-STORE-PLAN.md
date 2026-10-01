# App Store plan: iPhone, iPad, and Mac

Decisions (October 1, 2026): ship under CJ’s personal Apple Developer account, free, keep the
current blurple look, and keep this repository public under MIT.

One App Store listing covers all three platforms (Universal Purchase), so someone who downloads
it on iPhone also gets it on iPad and Mac.

## 1. One project, three platforms

- Move the parser, holiday, and timestamp code into a shared `MagicTimeCore` module. The Mac app,
  the iPhone and iPad app, the App Intents, and the `magic-time` command all build from it, so they
  can never disagree.
- Generate the Xcode project from a small `project.yml` (XcodeGen), so the project file stays
  readable in Git and `build.sh` keeps working for local Mac builds.
- Targets: Magic Time (iOS and iPadOS, iOS 17 or later), Magic Time (macOS, macOS 14 or later),
  a shared App Intents extension, and the existing test suite.
- Diwali and Holi need the Indian calendars in iOS 26 and macOS 26. On older systems the app
  explains that, the same way it does today.

## 2. iPhone and iPad app

- The same flow as the Mac panel: type a time, see how it was read, and tap a format to copy it,
  with a light haptic tap and a “Copied” confirmation.
- On iPad, a wider layout with the formats beside the input; keyboard shortcuts (⌘1–⌘9, Return)
  work with a hardware keyboard.
- **App Intents** are the iPhone version of ⌃⌥⌘T: “Make a Discord timestamp” appears in Spotlight,
  Siri, Shortcuts, and the Action button, takes a phrase, and returns the code (and copies it).
- Later, optional: a widget that shows the countdown for a saved event, and a keyboard extension
  that inserts codes directly in Discord.

## 3. Mac App Store version

- Turn on App Sandbox (required). The global hotkey (`RegisterEventHotKey`), Open at Login
  (`SMAppService`), and the clipboard all work inside the sandbox.
- The `magic-time` command and the Claude skill stay GitHub-only; the Mac App Store build doesn’t
  install anything outside the app.

## 4. Store requirements

- **Name:** “Magic Time: Chat Timestamps” (plain “MagicTime” is taken). Check availability by
  creating the app record in App Store Connect.
- **Bundle ID:** `cc.covell.magictime` for all platforms.
- **Privacy:** no data collected. Add a privacy manifest (`PrivacyInfo.xcprivacy`) that declares
  the app’s use of `UserDefaults` (reason CA92.1), set the App Privacy answers to “Data Not
  Collected,” and publish a one-paragraph privacy policy (for example, a GitHub Pages page).
- **Export compliance:** the app uses no encryption, so set `ITSAppUsesNonExemptEncryption` to NO.
- **Screenshots:** iPhone 6.9-inch, iPad 13-inch, and Mac, generated from the simulator and the app.
- **Description:** the copy drafted earlier (“One time. Every time zone.”), mentioning Discord only
  as compatibility, plus “Not affiliated with or endorsed by Discord Inc.”
- **Review risk to watch:** the blurple color and chat-bubble icon resemble Discord’s trade dress.
  If App Review objects (guideline 5.2.1, Intellectual Property), the fix is a recolor, not a rebuild.

## 5. What only CJ can do

1. Confirm the Apple Developer Program membership is active ($99/year).
2. In Xcode, choose Settings > Accounts, add the Apple ID, and select the personal team. Xcode then
   creates the signing certificates automatically.
3. In App Store Connect, accept the latest agreements. A free app doesn’t need tax or banking forms.
4. Approve the TestFlight build on a real iPhone, then press Submit for Review.

## 6. Order of work

1. Shared core module and generated Xcode project; the Mac app and command still build and pass tests.
2. iPhone and iPad interface, then App Intents.
3. Sandbox the Mac build; add the privacy manifest and export-compliance key.
4. Screenshots and store copy.
5. After CJ signs in to Xcode: archive, upload to TestFlight, test, and submit.
