import SwiftUI

struct RootView: View {
    @Bindable var model: TimestampModel
    @FocusState private var fieldFocused: Bool
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var sizeClass

    var body: some View {
        NavigationStack {
            List {
                inputSection
                formatsSection
            }
            .listStyle(.insetGrouped)
            .overlay { if model.date == nil { emptyState.allowsHitTesting(false) } }
            .scrollDismissesKeyboard(.interactively)
            .navigationTitle("Magic Time")
            // On iPad the content is a centered column, so center the title over it too.
            .navigationBarTitleDisplayMode(sizeClass == .regular ? .inline : .large)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { zoneMenu }
            }
            .frame(maxWidth: 720)
            .frame(maxWidth: .infinity)
            .background(Color(.systemGroupedBackground))
        }
        .tint(.blurple)
        .sensoryFeedback(.success, trigger: model.copyCount)
        .onAppear {
            #if DEBUG
            // Screenshots and UI checks: `-MTPrefill "fri 8pm PT"` on the launch command line.
            if let prefill = UserDefaults.standard.string(forKey: "MTPrefill") { model.text = prefill; return }
            #endif
            if model.text.isEmpty { fieldFocused = true }
        }
        .onChange(of: scenePhase) { _, phase in if phase == .active { model.refresh() } }
    }

    // MARK: Input

    private var inputSection: some View {
        Section {
            HStack(spacing: 12) {
                Image(systemName: "clock")
                    .font(.title3)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("tomorrow 9:30am", text: $model.text)
                    .font(.title2)
                    .focused($fieldFocused)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.done)
                    .accessibilityLabel("Time")
                    .accessibilityHint("Type a time, like fri 8pm or 3rd friday in may at 6pm")
                if !model.text.isEmpty {
                    Button {
                        model.text = ""
                        fieldFocused = true
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Clear")
                }
            }
            .padding(.vertical, 4)

            if let date = model.date {
                DatePicker(
                    selection: Binding(get: { date }, set: { model.pickedDate = TimeParser.floorToMinute($0) }),
                    displayedComponents: [.date, .hourAndMinute]
                ) {
                    Text("Read as")
                        .foregroundStyle(.secondary)
                }
                .environment(\.timeZone, model.zone.timeZone)
            }
        } footer: {
            // Always visible, because the toolbar may show only the globe icon.
            Text(model.zone.id == "UTC" ? "Times you type use UTC." : "Times you type use \(model.zone.label) time.")
        }
    }

    private var zoneMenu: some View {
        Menu {
            Picker("Time Zone", selection: $model.zoneID) {
                ForEach(ZoneOption.all) { option in
                    Text(option.label).tag(option.id)
                }
            }
        } label: {
            // An icon and a title, so iPhone Duo can show it in a vertical bar (icon) or an overflow
            // menu (both); a custom label view would be dropped from vertical bars.
            Label("Time Zone: \(model.zone.label)", systemImage: "globe")
        }
    }

    // MARK: Formats

    @ViewBuilder
    private var formatsSection: some View {
        if let date = model.date {
            Section {
                TimelineView(.everyMinute) { context in
                    ForEach(DiscordStyle.allCases) { style in
                        FormatRow(
                            style: style,
                            preview: style.preview(for: date, now: context.date),
                            code: style.code(for: date),
                            isCopied: model.copiedStyle == style
                        ) {
                            model.copy(style)
                        }
                        .contextMenu {
                            Button("Copy Code", systemImage: "doc.on.doc") { model.copy(style) }
                            Button("Copy What Discord Shows", systemImage: "text.quote") { model.copyPreview(style) }
                            ShareLink(item: style.code(for: date))
                        }
                    }
                }
            } header: {
                Text("Tap to copy")
            } footer: {
                Text("Each reader sees the time in their own time zone. Not affiliated with Discord.")
            }
        }
    }

    // MARK: Empty states

    @ViewBuilder
    private var emptyState: some View {
        switch (model.isEmpty, model.reading) {
        case (true, _):
            ContentUnavailableView {
                Label("Type a time", systemImage: "sparkles")
            } description: {
                Text("Try “fri 8pm PT” or “3rd friday in may at 6pm”.")
            }
        case (false, .note(let why)):
            ContentUnavailableView {
                Label("Magic Time won’t guess this one", systemImage: "calendar.badge.exclamationmark")
            } description: {
                Text(why)
            }
        default:
            ContentUnavailableView {
                Label("No date or time found", systemImage: "calendar")
            } description: {
                Text("Try “tomorrow 9:30am”, “the 15th at noon”, or “christmas eve 7pm”.")
            }
        }
    }
}

private struct FormatRow: View {
    let style: DiscordStyle
    let preview: String
    let code: String
    let isCopied: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(preview)
                        .foregroundStyle(.primary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.primary.opacity(0.08), in: .rect(cornerRadius: 5, style: .continuous))
                    Text(code)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Image(systemName: isCopied ? "checkmark.circle.fill" : "doc.on.doc")
                    .foregroundStyle(isCopied ? AnyShapeStyle(.green) : AnyShapeStyle(.tint))
                    .contentTransition(.symbolEffect(.replace))
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 2)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(preview). \(style.name).")
        .accessibilityValue(isCopied ? "Copied" : "")
        .accessibilityHint("Copies \(code)")
    }
}

extension Color {
    /// The app's accent, matching the icon.
    static let blurple = Color(red: 0x58 / 255, green: 0x65 / 255, blue: 0xF2 / 255)
}
