import PolishCore
import SwiftUI

/// The quick window's content. Keys: ⌘Return polish, ⇧⌘C copy the result (⌘C stays the editor's copy).
struct QuickWindowView: View {
    @Bindable var model: QuickWindowModel
    @FocusState private var editorFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextEditor(text: $model.text)
                .font(.body)
                .frame(minHeight: 120)
                .focused($editorFocused)
                .accessibilityLabel("Text to polish")
                .overlay(alignment: .topLeading) {
                    if model.text.isEmpty {
                        Text("Type or paste a message")
                            .foregroundStyle(.tertiary)
                            .padding(.leading, 5)
                            .allowsHitTesting(false)
                    }
                }
            HStack {
                TonePicker(tone: $model.tone, title: "Tone")
                    .fixedSize()
                Spacer()
                Button("Polish", action: model.polish)
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canPolish)
                    .help("Polish the text (⌘Return)")
            }
            output
        }
        .padding(16)
        .frame(minWidth: 440, idealWidth: 480, minHeight: 300)
        .onAppear { editorFocused = true }
        .onChange(of: model.result?.text) { _, text in
            if let text { AccessibilityNotification.Announcement("Rewrite ready: \(text)").post() }
        }
    }

    @ViewBuilder
    private var output: some View {
        switch model.state {
        case .idle:
            EmptyView()
        case .running:
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(model.runningTitle).monospacedDigit()
                }
                if let progress = model.progress, progress.total > 1 {
                    ProgressView(value: Double(progress.completed), total: Double(progress.total))
                        .accessibilityHidden(true)
                }
                if let preview = model.preview, !preview.isEmpty {
                    resultBox(Text(preview).foregroundStyle(.secondary))
                        .defaultScrollAnchor(.bottom)
                        .accessibilityHidden(true)
                }
            }
            .accessibilityElement(children: .combine)
        case .result(let result):
            if result.isUnchanged {
                Label("Looks good. No changes needed.", systemImage: "checkmark.circle")
            } else {
                resultBox(Text(DiffText.attributed(result.diff, showRemovals: model.showRemovals)))
                    .accessibilityLabel("Rewrite")
                    .accessibilityValue(result.text)
                if model.showsChanges, case let changes = result.changes, !changes.isEmpty {
                    ChangeList(changes: changes)
                }
                if result.didFallBack {
                    Label("Some parts were kept as you wrote them.", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Toggle("Show removed words", isOn: $model.showRemovals)
                        .toggleStyle(.checkbox)
                        .font(.caption)
                    Spacer()
                    Button("Copy", action: model.copyResult)
                        .keyboardShortcut("c", modifiers: [.command, .shift])
                        .help("Copy the rewrite (⇧⌘C)")
                }
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func resultBox(_ text: Text) -> some View {
        ScrollView {
            text
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(8)
        }
        .frame(minHeight: 60, maxHeight: 240)
        .fixedSize(horizontal: false, vertical: true)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 6))
    }
}
