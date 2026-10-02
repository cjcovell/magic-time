import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Optional help for long, chatty sentences the reader can't follow ("let's do the raid on the
/// 15th at eight thirty at night for the west coast folks"). On devices with Apple Intelligence,
/// Apple's on-device model shortens the sentence to a phrase; the reader must then understand
/// that phrase on its own, and the person must tap the suggestion to use it. The model never
/// produces a date, never runs off the device, and is never trusted without both checks.
enum PhraseHelper {
    struct Suggestion: Equatable {
        let phrase: String
        let date: Date
    }

    /// Short inputs are the reader's job; only sentences are worth a second opinion.
    static let minimumWords = 4

    static func suggestion(for text: String, in zone: TimeZone, now: Date = .now) async -> Suggestion? {
        guard text.split(whereSeparator: \.isWhitespace).count >= minimumWords else { return nil }
        guard let reply = await shorten(text) else { return nil }
        let phrase = reply.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”."))).lowercased()
        guard !phrase.isEmpty, phrase != "none", phrase.count <= 60, keepsMeaning(of: text, in: phrase) else { return nil }
        guard case .moment(let date) = TimeParser.interpret(phrase, in: zone, now: now) else { return nil }
        return Suggestion(phrase: phrase, date: date)
    }

    /// Words that move a date. The model sometimes drops them ("next saturday" → "sat"), which
    /// would silently change the day, so a rewrite that loses one is thrown away.
    static let shiftWords: Set<String> = [
        "next", "after", "before", "last", "following", "from", "other", "every", "ago", "weeks", "week",
    ]

    static func keepsMeaning(of original: String, in phrase: String) -> Bool {
        let kept = Set(NaturalTime.tokenize(phrase))
        return NaturalTime.tokenize(original).allSatisfy { !shiftWords.contains($0) || kept.contains($0) }
    }

    private static let instructions = """
        You shorten a sentence about when something happens into a short time phrase. \
        Keep only the day, date, time, and time zone, in the user's own words. Do not work out dates. \
        Do not add anything the sentence doesn't say. Reply with the phrase only, in lowercase. \
        If the sentence has no day or time, reply with the single word none.
        Examples:
        let's do the raid this friday around 8 at night, pacific -> fri 8pm PT
        can everyone make it the day before thanksgiving at like 7 in the evening -> day before thanksgiving 7pm
        how about half six tomorrow, london time -> tomorrow 6:30pm london
        what should we eat -> none
        """

    private static func shorten(_ text: String) async -> String? {
        #if canImport(FoundationModels)
        guard #available(iOS 26.0, macOS 26.0, *) else { return nil }
        guard case .available = SystemLanguageModel.default.availability else { return nil }
        let session = LanguageModelSession(instructions: instructions)
        return try? await session.respond(to: text).content
        #else
        return nil
        #endif
    }
}
