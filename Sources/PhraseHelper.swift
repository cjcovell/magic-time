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

    /// The model's answers vary from one request to the next, so a rejected rewrite gets another try.
    static let attempts = 3

    static func suggestion(for text: String, in zone: TimeZone, now: Date = .now) async -> Suggestion? {
        guard text.split(whereSeparator: \.isWhitespace).count >= minimumWords else { return nil }
        for _ in 0..<attempts {
            guard let reply = await shorten(text) else { return nil }           // no model on this device
            if let suggestion = accept(reply, for: text, in: zone, now: now) { return suggestion }
            if reply.lowercased().contains("none") { return nil }               // the model sees no time here
        }
        return nil
    }

    /// Every check a rewrite must pass before anyone sees it: it's short, it keeps the sentence's
    /// meaning, and the reader, by its own rules, turns it into a moment.
    static func accept(_ reply: String, for text: String, in zone: TimeZone, now: Date = .now) -> Suggestion? {
        let phrase = reply.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"“”."))).lowercased()
        guard !phrase.isEmpty, phrase != "none", phrase.count <= 60, keepsMeaning(of: text, in: phrase) else { return nil }
        guard case .moment(let date) = TimeParser.interpret(phrase, in: zone, now: now) else { return nil }
        return Suggestion(phrase: phrase, date: date)
    }

    /// The model drops words ("third friday of may" → "fri"), swaps them ("christmas" → "chrissy"),
    /// and adds zones nobody mentioned ("8:30pm est"). Each of those would silently change the
    /// answer, so a rewrite is thrown away unless it:
    /// - names exactly the same days, dates, months, and holidays as the sentence,
    /// - names the same zones (or one the sentence described in words: "west coast", "new york time"),
    /// - and adds no word that is neither from the sentence nor one the reader knows.
    static func keepsMeaning(of original: String, in phrase: String) -> Bool {
        guard NaturalTime.dateWords(in: original) == NaturalTime.dateWords(in: phrase) else { return false }

        let words = NaturalTime.tokenize(original)
        let named = NaturalTime.zones(in: original), suggested = NaturalTime.zones(in: phrase)
        guard named.isSubset(of: suggested) else { return false }
        guard suggested.isSubset(of: named) || speaksOfAZone(words) else { return false }

        let said = Set(words)
        return NaturalTime.tokenize(phrase).allSatisfy { said.contains($0) || NaturalTime.isKnownWord($0) }
    }

    private static func speaksOfAZone(_ words: [String]) -> Bool {
        if words.contains("coast") || words.contains("zone") || words.contains("timezone") { return true }
        let articles: Set<String> = ["what", "the", "a", "any", "some", "this", "that", "which", "same", "good"]
        return words.indices.contains { words[$0] == "time" && $0 > 0 && !articles.contains(words[$0 - 1]) }
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
