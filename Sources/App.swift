import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

@main
struct MagicTimeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra {
            MenuContent(delegate: appDelegate, loginItem: appDelegate.loginItem)
        } label: {
            Image(nsImage: .menuBarGlyph)
                .accessibilityLabel("Magic Time")
        }
    }
}

/// Runs in the background (no Dock icon) so ⌃⌥⌘T can summon the panel from any app.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = InputModel()
    let loginItem = LoginItem()
    private var panel: LauncherPanel!
    private var hotKey: GlobalHotKey?

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = LauncherPanel(model: model)
        model.dismiss = { [weak self] in self?.hidePanel() }

        hotKey = GlobalHotKey(
            keyCode: UInt32(kVK_ANSI_T),
            modifiers: UInt32(controlKey | optionKey | cmdKey)
        ) { [weak self] in
            self?.togglePanel()
        }

        if !Self.launchedAsLoginItem { showPanel() }
    }

    /// Opening the app again from Spotlight or Finder while it's already running.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return false
    }

    func togglePanel() {
        panel.isVisible ? hidePanel() : showPanel()
    }

    func showPanel() {
        model.presented()
        panel.present()
    }

    func hidePanel() {
        panel.orderOut(nil)
        // If Spotlight or the menu bar activated us, hand focus back to the previous app.
        if NSApp.isActive { NSApp.hide(nil) }
    }

    private static var launchedAsLoginItem: Bool {
        guard let event = NSAppleEventManager.shared().currentAppleEvent,
              event.eventID == AEEventID(kAEOpenApplication) else { return false }
        return event.paramDescriptor(forKeyword: AEKeyword(keyAEPropData))?.enumCodeValue
            == OSType(keyAELaunchedAsLogInItem)
    }
}

final class LoginItem: ObservableObject {
    @Published private(set) var isEnabled = SMAppService.mainApp.status == .enabled

    func set(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSSound.beep()
        }
        isEnabled = SMAppService.mainApp.status == .enabled
    }
}

private struct MenuContent: View {
    let delegate: AppDelegate
    @ObservedObject var loginItem: LoginItem

    var body: some View {
        Button("Open Magic Time") { delegate.showPanel() }
            .keyboardShortcut("t", modifiers: [.control, .option, .command])
        Divider()
        Toggle("Open at Login", isOn: Binding(get: { loginItem.isEnabled }, set: { loginItem.set($0) }))
        Divider()
        Button("Quit Magic Time") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }
}

private extension NSImage {
    /// "<t:>" in SF Mono, as a template image so it follows the menu bar's light/dark tint.
    static let menuBarGlyph: NSImage = {
        let text = "<t:>" as NSString
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
            .kern: -1.2,
        ]
        let size = text.size(withAttributes: attributes)
        let image = NSImage(size: NSSize(width: ceil(size.width), height: 18), flipped: false) { rect in
            text.draw(at: NSPoint(x: 0, y: (rect.height - size.height) / 2), withAttributes: attributes)
            return true
        }
        image.isTemplate = true
        return image
    }()
}
