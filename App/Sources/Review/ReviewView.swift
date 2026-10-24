import PolishCore
import SwiftUI

/// The panel's content. Keys: Return accept, ⌘E edit, ⌘C copy, Esc cancel (FR-5).
struct ReviewView: View {
    @Bindable var model: ReviewModel
    let controller: PolishController
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
            if model.result != nil, model.pastesMentionsAsText {
                Label("Mentions will paste as plain text.", systemImage: "at")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
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
    }

    @ViewBuilder
    private var content: some View {
        switch model.state {
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Polishing…")
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
            if model.result != nil {
                Button("Copy", action: controller.copy)
                    .keyboardShortcut("c")
                if !model.isEditing {
                    Button("Edit") { model.isEditing = true }
                        .keyboardShortcut("e")
                }
                // Return types a newline while editing, so Accept moves to ⌘Return there.
                Button("Accept", action: controller.accept)
                    .keyboardShortcut(.return, modifiers: model.isEditing ? .command : [])
                    .buttonStyle(.borderedProminent)
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
