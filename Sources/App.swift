import AppKit
import SwiftUI

@main
struct DiscordTimeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Window("Discord Time", id: "main") {
            ContentView()
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

/// Typed text, a date picked by hand, and the copy confirmation.
final class InputModel: ObservableObject {
    @Published var text = ""
    @Published var pickedDate: Date?
    @Published var copiedStyle: DiscordStyle?
}

struct ContentView: View {
    @AppStorage("zone") private var zoneID = ZoneOption.all[0].id
    @AppStorage("style") private var selectedStyle = DiscordStyle.longDateTime.rawValue

    @StateObject private var model = InputModel()
    @FocusState private var fieldFocused: Bool

    private var zone: ZoneOption { ZoneOption.named(zoneID) }
    private var parsedDate: Date? { model.pickedDate ?? TimeParser.parse(model.text, in: zone.timeZone) }
    private var isEmpty: Bool { model.text.trimmingCharacters(in: .whitespaces).isEmpty && model.pickedDate == nil }
    private var selected: DiscordStyle { DiscordStyle(rawValue: selectedStyle) ?? .longDateTime }

    var body: some View {
        VStack(spacing: 0) {
            inputRow
            statusRow
            Divider()
            TimelineView(.everyMinute) { context in
                formatList(now: context.date)
            }
            Divider()
            footer
        }
        .frame(width: 460)
        .background(.regularMaterial)
        .background(alignment: .topLeading) { closeShortcut }
        .onAppear { fieldFocused = true }
        .onChange(of: model.text) { model.pickedDate = nil }
        .onChange(of: zoneID) { model.pickedDate = nil }
    }

    // MARK: Input

    private var inputRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock")
                .font(.system(size: 20, weight: .regular))
                .foregroundStyle(.secondary)

            TextField("tomorrow 9:30am", text: $model.text)
                .textFieldStyle(.plain)
                .font(.system(size: 22))
                .focused($fieldFocused)
                .onSubmit { copy(selected) }
                .onKeyPress(.upArrow) { moveSelection(by: -1); return .handled }
                .onKeyPress(.downArrow) { moveSelection(by: 1); return .handled }

            Menu {
                Picker("Time zone", selection: $zoneID) {
                    ForEach(ZoneOption.all) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Text(zone.label)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .foregroundStyle(.secondary)
            .help("Read typed times in this time zone")
        }
        .padding(.horizontal, 20)
        .padding(.top, 34)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: 6) {
            if let date = parsedDate {
                DatePicker(
                    "",
                    selection: Binding(get: { date }, set: { model.pickedDate = TimeParser.floorToMinute($0) }),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .environment(\.timeZone, zone.timeZone)
                .fixedSize()

                Text(zone.timeZone.abbreviation(for: date) ?? zone.label)
                    .foregroundStyle(.secondary)
            } else {
                Image(systemName: isEmpty ? "text.cursor" : "questionmark.circle")
                Text(isEmpty ? "Type a time — “tomorrow 9:30am”, “fri 2pm”, “10/14 7pm”"
                             : "Couldn’t read that. Try “tomorrow 9:30am” or “fri 2pm”.")
            }
            Spacer()
        }
        .font(.callout)
        .foregroundStyle(.secondary)
        .frame(height: 24)
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }

    // MARK: Formats

    private func formatList(now: Date) -> some View {
        let date = parsedDate ?? TimeParser.floorToMinute(now)
        let usable = parsedDate != nil

        return VStack(spacing: 2) {
            ForEach(DiscordStyle.allCases) { style in
                FormatRow(
                    style: style,
                    preview: style.preview(for: date, now: now),
                    code: style.code(for: date),
                    isSelected: usable && style == selected,
                    isCopied: style == model.copiedStyle
                )
                .contentShape(.rect)
                .onTapGesture {
                    guard usable else { return }
                    selectedStyle = style.rawValue
                    copy(style)
                }
            }
        }
        .padding(8)
        .opacity(usable ? 1 : 0.35)
        .animation(.easeOut(duration: 0.12), value: selectedStyle)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            KeyHint(key: "↩", label: "Copy")
            KeyHint(key: "↑↓", label: "Choose")
            KeyHint(key: "esc", label: "Close")
            Spacer()
            if model.copiedStyle != nil {
                Label("Copied", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .transition(.opacity)
            }
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }

    private var closeShortcut: some View {
        Button("Close") { NSApp.keyWindow?.close() }
            .keyboardShortcut(.cancelAction)
            .opacity(0)
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
    }

    // MARK: Actions

    private func moveSelection(by step: Int) {
        let styles = DiscordStyle.allCases
        guard let index = styles.firstIndex(of: selected) else { return }
        let next = min(max(index + step, 0), styles.count - 1)
        selectedStyle = styles[next].rawValue
    }

    private func copy(_ style: DiscordStyle) {
        guard let date = parsedDate else { NSSound.beep(); return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(style.code(for: date), forType: .string)

        withAnimation(.easeOut(duration: 0.15)) { model.copiedStyle = style }
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            withAnimation(.easeOut(duration: 0.3)) {
                if model.copiedStyle == style { model.copiedStyle = nil }
            }
        }
    }
}

private struct FormatRow: View {
    let style: DiscordStyle
    let preview: String
    let code: String
    let isSelected: Bool
    let isCopied: Bool

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(preview)
                    .font(.body)
                    .foregroundStyle(.primary)
                Text(code)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 8)
            Text(style.name)
                .font(.caption)
                .foregroundStyle(.tertiary)
            Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isCopied ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                .frame(width: 16)
                .opacity(isSelected || isCopied ? 1 : 0)
                .contentTransition(.symbolEffect(.replace))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(Color.accentColor.opacity(0.16)) : AnyShapeStyle(.clear))
        }
    }
}

private struct KeyHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(.caption2, design: .rounded).weight(.semibold))
                .padding(.horizontal, 5)
                .padding(.vertical, 1)
                .background(.quaternary, in: .rect(cornerRadius: 4, style: .continuous))
            Text(label)
        }
    }
}
