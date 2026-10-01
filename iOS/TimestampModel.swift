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

    private func reread() { reading = TimeParser.interpret(text, in: zone.timeZone) }

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
