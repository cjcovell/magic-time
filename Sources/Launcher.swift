import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A Spotlight-style floating panel: takes typing without activating the app, appears on the
/// current Space (even over full-screen apps), and hides when it loses focus.
final class LauncherPanel: NSPanel {
    private let model: InputModel
    private let hostingView: NSHostingView<ContentView>
    private var escapeMonitor: Any?

    init(model: InputModel) {
        self.model = model
        hostingView = NSHostingView(rootView: ContentView(model: model))
        // The title bar is hidden, so don't let its inset pad the top and inflate the fitting size.
        hostingView.safeAreaRegions = []
        super.init(
            contentRect: .zero,
            styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        for button in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            standardWindowButton(button)?.isHidden = true
        }
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        hidesOnDeactivate = false
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        contentView = hostingView
        closeOnEscape()

        NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification, object: self, queue: .main
        ) { [weak self] _ in
            // Hide when focus moves to another app; stay up for our own date-picker popover.
            DispatchQueue.main.async {
                guard let self, self.isVisible, NSApp.keyWindow == nil else { return }
                self.model.dismiss()
            }
        }
    }

    override var canBecomeKey: Bool { true }

    /// Centers the panel in the upper part of the screen under the mouse, then focuses it.
    func present() {
        let size = hostingView.fittingSize
        let screen = NSScreen.screens.first { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) } ?? NSScreen.main
        if let area = screen?.visibleFrame {
            let top = area.maxY - area.height * 0.2
            setFrame(NSRect(x: area.midX - size.width / 2, y: top - size.height,
                            width: size.width, height: size.height), display: true)
        } else {
            setContentSize(size)
        }
        makeKeyAndOrderFront(nil)
    }

    /// Esc closes. A local monitor sees the key before SwiftUI's text field can swallow it.
    private func closeOnEscape() {
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self, event.keyCode == UInt16(kVK_Escape) else { return event }
            self.model.dismiss()
            return nil
        }
    }

    /// ⌘1–⌘9 copy a format. Editing shortcuts are routed here too, since an agent app's
    /// hidden main menu can't be relied on to deliver them to a non-activating panel.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard let key = event.charactersIgnoringModifiers?.lowercased() else {
            return super.performKeyEquivalent(with: event)
        }

        if flags == .command, let digit = Int(key), DiscordStyle.allCases.indices.contains(digit - 1) {
            model.copy(DiscordStyle.allCases[digit - 1])
            return true
        }

        let editing: [String: Selector] = [
            "a": #selector(NSText.selectAll(_:)),
            "c": #selector(NSText.copy(_:)),
            "v": #selector(NSText.paste(_:)),
            "x": #selector(NSText.cut(_:)),
            "z": Selector(("undo:")),
        ]
        if flags == .command, let action = editing[key], NSApp.sendAction(action, to: nil, from: self) {
            return true
        }
        if flags == [.command, .shift], key == "z", NSApp.sendAction(Selector(("redo:")), to: nil, from: self) {
            return true
        }
        if flags == .command, key == "w" {
            model.dismiss()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }
}

/// A system-wide hotkey via Carbon's RegisterEventHotKey — no Accessibility permission needed.
final class GlobalHotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: @MainActor () -> Void

    init?(keyCode: UInt32, modifiers: UInt32, action: @escaping @MainActor () -> Void) {
        self.action = action

        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let status = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData in
            guard let userData else { return OSStatus(eventNotHandledErr) }
            let hotKey = Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue()
            MainActor.assumeIsolated { hotKey.action() }
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)
        guard status == noErr else { return nil }

        let id = EventHotKeyID(signature: OSType(0x4D47_544D), id: 1) // 'MGTM'
        guard RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef) == noErr else {
            return nil
        }
    }

    deinit {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let handlerRef { RemoveEventHandler(handlerRef) }
    }
}

