import PolishCore
import SwiftUI

/// The panel's content. Keys: Return accept, ⌘E edit, ⌘C copy, Tab next tone, Esc cancel (FR-5, FR-8).
struct ReviewView: View {
    @Bindable var model: ReviewModel
    let controller: PolishController
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if model.canChangeTone {
                Button(action: controller.cycleTone) {
                    Label(model.tone.title, systemImage: "dial.medium")
                }
                .buttonStyle(.borderless)
                .font(.caption)
                .foregroundStyle(.secondary)
                .keyboardShortcut(.tab, modifiers: [])
                .help("Polish again in the next tone (Tab)")
                .accessibilityLabel("Tone: \(model.tone.title)")
                .accessibilityHint("Tab polishes again in the next tone")
            }
            content
            if let result = model.result, result.didFallBack {
                Label("Some parts were kept as you wrote them.", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            buttons
        }
        .padding(16)
        .frame(width: 420, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Polish review")
        .onChange(of: model.announcement, initial: true) { _, announcement in
            AccessibilityNotification.Announcement(announcement).post()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.loadingTitle)
                        .monospacedDigit()
                }
                if let progress = model.progress, progress.total > 1 {
                    ProgressView(value: Double(progress.completed), total: Double(progress.total))
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .combine)
        case .unchanged:
            Label("Looks good. No changes needed.", systemImage: "checkmark.circle")
        case .failed(let failure):
            Label(failure.message, systemImage: "exclamationmark.triangle")
                .fixedSize(horizontal: false, vertical: true)
        case .result(let result):
            if model.isEditing {
                TextEditor(text: $model.editedText)
                    .font(.body)
                    .frame(minHeight: 80, maxHeight: 240)
                    .focused($editorFocused)
                    .onAppear { editorFocused = true }
                    .accessibilityLabel("Edit rewrite")
            } else {
                ScrollView {
                    Text(DiffText.attributed(result.diff, showRemovals: model.showRemovals))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxHeight: 240)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityLabel("Rewrite")
                .accessibilityValue(result.text)
            }
        }
    }

    @ViewBuilder
    private var buttons: some View {
        HStack {
            if model.result != nil, !model.isEditing {
                Toggle("Show removed words", isOn: $model.showRemovals)
                    .toggleStyle(.checkbox)
                    .font(.caption)
            }
            Spacer()
            Button("Cancel", action: controller.cancel)
                .keyboardShortcut(.cancelAction)
                .help("Keep your text (Esc)")
            if model.result != nil {
                Button("Copy", action: controller.copy)
                    .keyboardShortcut("c")
                    .help("Copy the rewrite (⌘C)")
                if !model.isEditing {
                    Button("Edit") { model.isEditing = true }
                        .keyboardShortcut("e")
                        .help("Edit the rewrite before accepting (⌘E)")
                }
                // Return types a newline while editing, so Accept moves to ⌘Return there.
                Button("Accept", action: controller.accept)
                    .keyboardShortcut(.return, modifiers: model.isEditing ? .command : [])
                    .buttonStyle(.borderedProminent)
                    .help(model.isEditing ? "Put the edited text back (⌘Return)" : "Put the rewrite back (Return)")
            } else if let action = model.failure?.action {
                Button(action.title) { controller.perform(action) }
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private extension ReviewModel.Failure.Action {
    var title: String {
        switch self {
        case .openAccessibilitySettings: "Open Accessibility Settings"
        case .openAppleIntelligenceSettings: "Open Settings"
        }
    }
}
