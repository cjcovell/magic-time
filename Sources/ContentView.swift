import AppKit
import SwiftUI

/// What's typed, the chosen zone and format, and the copy/close actions the panel shares.
final class InputModel: ObservableObject {
    private let defaults = UserDefaults.standard

    @Published var text = "" {
        didSet { if text != oldValue { pickedDate = nil } }
    }
    @Published var pickedDate: Date?
    @Published var copiedStyle: DiscordStyle?
    @Published var zoneID: String {
        didSet { defaults.set(zoneID, forKey: "zone"); pickedDate = nil }
    }
    @Published var selectedStyle: DiscordStyle {
        didSet { defaults.set(selectedStyle.rawValue, forKey: "style") }
    }
    /// Bumped each time the panel opens, so the view can refocus the field.
    @Published private(set) var presentation = 0

    var dismiss: () -> Void = {}

    init() {
        zoneID = defaults.string(forKey: "zone") ?? ZoneOption.all[0].id
        selectedStyle = defaults.string(forKey: "style").flatMap(DiscordStyle.init(rawValue:)) ?? .fullDateShortTime
    }

    var zone: ZoneOption { ZoneOption.named(zoneID) }
    var date: Date? { pickedDate ?? TimeParser.parse(text, in: zone.timeZone) }
    var isEmpty: Bool { text.trimmingCharacters(in: .whitespaces).isEmpty && pickedDate == nil }

    func presented() {
        copiedStyle = nil
        presentation += 1
    }

    func moveSelection(by step: Int) {
        let styles = DiscordStyle.allCases
        guard let index = styles.firstIndex(of: selectedStyle) else { return }
        selectedStyle = styles[min(max(index + step, 0), styles.count - 1)]
    }

    /// Copies the code, flashes the confirmation, then closes so you can paste straight away.
    func copy(_ style: DiscordStyle) {
        guard let date else { NSSound.beep(); return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(style.code(for: date), forType: .string)

        selectedStyle = style
        withAnimation(.easeOut(duration: 0.12)) { copiedStyle = style }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            guard let self, self.copiedStyle == style else { return }
            self.dismiss()
        }
    }
}

struct ContentView: View {
    @ObservedObject var model: InputModel
    @FocusState private var fieldFocused: Bool

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
        .frame(width: 540)
        .background(.regularMaterial)
        .tint(.blurple)
        .onAppear(perform: focusField)
        .onChange(of: model.presentation) { focusField() }
    }

    private func focusField() {
        fieldFocused = true
        // Select the last query so typing replaces it, like Spotlight.
        DispatchQueue.main.async {
            NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil)
        }
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
                .onSubmit { model.copy(model.selectedStyle) }
                .onKeyPress(.upArrow) { model.moveSelection(by: -1); return .handled }
                .onKeyPress(.downArrow) { model.moveSelection(by: 1); return .handled }

            Menu {
                Picker("Time zone", selection: $model.zoneID) {
                    ForEach(ZoneOption.all) { option in
                        Text(option.label).tag(option.id)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                Text(model.zone.label)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .foregroundStyle(.secondary)
            .help("Read typed times in this time zone")
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 10)
    }

    @ViewBuilder
    private var statusRow: some View {
        HStack(spacing: 6) {
            if let date = model.date {
                DatePicker(
                    "",
                    selection: Binding(get: { date }, set: { model.pickedDate = TimeParser.floorToMinute($0) }),
                    displayedComponents: [.date, .hourAndMinute]
                )
                .labelsHidden()
                .datePickerStyle(.compact)
                .environment(\.timeZone, model.zone.timeZone)
                .fixedSize()

                Text(model.zone.timeZone.abbreviation(for: date) ?? model.zone.label)
                    .foregroundStyle(.secondary)
            } else {
                if !model.isEmpty { Image(systemName: "questionmark.circle") }
                Text(model.isEmpty ? "Type a time, like “fri 2pm” or “10/14 7pm”, or paste a <t:…> code"
                                   : "No time found. Try “tomorrow 9:30am” or “fri 2pm”.")
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
        let date = model.date ?? TimeParser.floorToMinute(now)
        let usable = model.date != nil

        return VStack(spacing: 2) {
            ForEach(Array(DiscordStyle.allCases.enumerated()), id: \.element) { index, style in
                FormatRow(
                    style: style,
                    number: index + 1,
                    preview: style.preview(for: date, now: now),
                    code: style.code(for: date),
                    isSelected: usable && style == model.selectedStyle,
                    isCopied: style == model.copiedStyle
                )
                .contentShape(.rect)
                .onTapGesture {
                    guard usable else { return }
                    model.copy(style)
                }
            }
        }
        .padding(8)
        .opacity(usable ? 1 : 0.35)
        .animation(.easeOut(duration: 0.12), value: model.selectedStyle)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            KeyHint(key: "↩", label: "Copy")
            KeyHint(key: "⌘1–\(DiscordStyle.allCases.count)", label: "Copy format")
            KeyHint(key: "↑↓", label: "Choose")
            KeyHint(key: "esc", label: "Close")
            Spacer()
            KeyHint(key: "⌃⌥⌘T", label: "Open anywhere")
        }
        .font(.caption)
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
    }
}

private struct FormatRow: View {
    let style: DiscordStyle
    let number: Int
    let preview: String
    let code: String
    let isSelected: Bool
    let isCopied: Bool

    var body: some View {
        HStack(spacing: 12) {
            TimestampChip(text: preview)
            Spacer(minLength: 12)
            Text(code)
                .font(.system(.callout, design: .monospaced))
                .foregroundStyle(isSelected ? .primary : .secondary)
            ZStack(alignment: .trailing) {
                Color.clear
                trailingMark
            }
            .frame(width: 64, height: 18)
        }
        .padding(.leading, 10)
        .padding(.trailing, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? AnyShapeStyle(.tint.opacity(0.16)) : AnyShapeStyle(.clear))
        }
        .help(style.name)
    }

    @ViewBuilder
    private var trailingMark: some View {
        if isCopied {
            Label("Copied", systemImage: "checkmark")
                .font(.caption.weight(.medium))
                .foregroundStyle(.green)
                .transition(.opacity.combined(with: .scale(scale: 0.9)))
        } else if isSelected {
            KeyCap("↩")
                .foregroundStyle(.secondary)
        } else {
            KeyCap("⌘\(number)")
                .foregroundStyle(.tertiary)
        }
    }
}

/// The highlighted pill Discord draws around a rendered timestamp.
private struct TimestampChip: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.body)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.primary.opacity(0.08), in: .rect(cornerRadius: 4, style: .continuous))
    }
}

private struct KeyCap: View {
    let key: String
    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(.system(.caption2, design: .rounded).weight(.semibold))
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary, in: .rect(cornerRadius: 4, style: .continuous))
    }
}

private struct KeyHint: View {
    let key: String
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            KeyCap(key)
            Text(label)
        }
    }
}

extension Color {
    /// Discord's brand color, matching the app icon.
    static let blurple = Color(red: 0x58 / 255, green: 0x65 / 255, blue: 0xF2 / 255)
}
