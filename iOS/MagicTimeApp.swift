import SwiftUI

@main
struct MagicTimeApp: App {
    @State private var model = TimestampModel()

    var body: some Scene {
        WindowGroup {
            RootView(model: model)
        }
        .commands {
            // Hardware-keyboard shortcuts on iPad, listed in the ⌘-hold overlay.
            CommandMenu("Copy") {
                ForEach(Array(DiscordStyle.allCases.enumerated()), id: \.element) { index, style in
                    Button("Copy \(style.name)") { model.copy(style) }
                        .keyboardShortcut(KeyEquivalent(Character("\(index + 1)")), modifiers: .command)
                        .disabled(model.date == nil)
                }
            }
        }
    }
}
