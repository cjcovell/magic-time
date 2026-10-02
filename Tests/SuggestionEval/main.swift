import Foundation

// A local check of the Apple Intelligence suggestions, run by scripts/suggestion-eval.sh on a Mac
// with Apple Intelligence turned on. It can't run in CI (no model there), and the model's answers
// vary, so it reports rather than pins: for each sentence, what was suggested, and proof that every
// suggestion shown is one the reader itself turns into a time.

let sentences = [
    "the 15th at eight thirty at night",
    "raid on the 15th, eight thirty at night",
    "raid is on the 15th at eight thirty at night for the west coast folks",
    "let's get everyone together next saturday evening, say quarter past seven, new york time",
    "movie night two fridays from now at 9 in the evening",
    "stream starts at twelve noon on halloween for everyone",
    "can everyone make it the day before thanksgiving at like seven in the evening",
    "how about half six tomorrow evening, london time",
    "game night this friday around eight at night pacific",
    "we should do lunch on christmas eve at about one in the afternoon",
    "what should we eat for dinner tonight then",
    "thinking sometime this weekend maybe, not sure yet",
    "new years eve party kicks off at ten at night eastern",
    "call me the third friday of may around six in the evening",
]
let zone = TimeZone(identifier: "America/New_York")!
let rounds = Int(CommandLine.arguments.dropFirst().first ?? "") ?? 3
var shown = 0, unreadable = 0, asked = 0

for sentence in sentences {
    print("“\(sentence)”")
    for _ in 0..<rounds {
        asked += 1
        guard let suggestion = await PhraseHelper.suggestion(for: sentence, in: zone) else {
            print("    no suggestion")
            continue
        }
        shown += 1
        // Independently of PhraseHelper: does the reader, on its own, read the phrase as that time?
        let reads = TimeParser.interpret(suggestion.phrase, in: zone).date == suggestion.date
        if !reads { unreadable += 1 }
        let when = suggestion.date.formatted(.dateTime.weekday().month().day().hour().minute())
        print("    \(reads ? "ok " : "BAD") “\(suggestion.phrase)” → \(when)")
    }
}
print("\n\(shown) suggestions shown in \(asked) requests; \(unreadable) the reader couldn’t read.")
exit(unreadable == 0 ? 0 : 1)
