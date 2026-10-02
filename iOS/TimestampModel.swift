import Observation
import SwiftUI
import UIKit

/// What's typed, the zone it's read in, and copying — shared by the screen, keyboard shortcuts,
/// and nothing else (App Intents parse on their own so they never touch the screen's state).
@MainActor
@Observable
final class TimestampModel {
    var text = "" {
        didSet { if text != oldValue { pickedDate = nil; reread() } }
    }
    var pickedDate: Date?
    var zoneID: String {
        didSet {
            UserDefaults.standard.set(zoneID, forKey: "zone")
            pickedDate = nil
            reread()
        }
    }
    private(set) var reading: Reading = .nothing
    /// The zone the text named ("london noon"), which the result is then shown in.
    private(set) var shownIn: TimeZone?
    /// A shorter phrase for a sentence the reader couldn't follow; used only if the person accepts it.
    private(set) var suggestion: PhraseHelper.Suggestion?
    @ObservationIgnored private var suggestionTask: Task<Void, Never>?
    private(set) var copiedStyle: DiscordStyle?
    /// Bumped on every copy so the success haptic fires even when copying the same row twice.
    private(set) var copyCount = 0

    init() {
        zoneID = UserDefaults.standard.string(forKey: "zone") ?? ZoneOption.defaultID
    }

    var zone: ZoneOption { ZoneOption.named(zoneID) }
    var date: Date? { pickedDate ?? reading.date }
    var isEmpty: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty && pickedDate == nil }

    /// Re-read relative phrases ("in 2 hours") when the app comes back to the foreground.
    func refresh() { reread() }

    private func reread() {
        let read = TimeParser.read(text, in: zone.timeZone)
        reading = read.reading
        shownIn = read.shownIn
        suggest()
    }

    private func suggest() {
        suggestionTask?.cancel()
        suggestion = nil
        guard reading == .nothing, !isEmpty else { return }
        let asked = text, timeZone = zone.timeZone
        suggestionTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(600))          // wait for a pause in typing
            guard !Task.isCancelled, let found = await PhraseHelper.suggestion(for: asked, in: timeZone) else { return }
            if !Task.isCancelled, self?.text == asked { self?.suggestion = found }
        }
    }

    func acceptSuggestion() {
        if let suggestion { text = suggestion.phrase }
    }

    var displayZone: TimeZone { shownIn ?? zone.timeZone }

    /// Under the field: the zone typed times use, or, when the text named one, where the result
    /// is shown and what that is in the chosen zone.
    var zoneHint: String {
        guard let shownIn, let date else { return zone.inputHint + "." }
        let name = ZoneOption.name(of: shownIn)
        let shown = name == "UTC" ? "Shown in UTC." : "Shown in \(name) time."
        guard let here = zone.equivalent(of: date, shownIn: shownIn) else { return shown }
        return "\(shown) That’s \(here)."
    }

    func copy(_ style: DiscordStyle) {
        guard let date else { return }
        UIPasteboard.general.string = style.code(for: date)
        copiedStyle = style
        copyCount += 1
        let count = copyCount
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            if copyCount == count { withAnimation { copiedStyle = nil } }
        }
    }

    func copyPreview(_ style: DiscordStyle) {
        guard let date else { return }
        UIPasteboard.general.string = style.preview(for: date)
        copyCount += 1
    }
}
