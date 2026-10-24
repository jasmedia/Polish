import KeyboardShortcuts
import PolishCore
import SwiftUI

/// First-run window: the hotkey, the Accessibility permission, the model's availability and a sample rewrite.
struct OnboardingView: View {
    @Bindable var model: OnboardingModel
    let status: ModelStatusModel
    let done: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Welcome to Polish")
                    .font(.title2.bold())
                Text("Fixes grammar and spelling in your Slack drafts, entirely on this Mac.")
                    .foregroundStyle(.secondary)
            }

            step("keyboard", "Shortcut",
                 detail: "Click in a message and press the shortcut. Polish shows its fixes; Return puts them in, Esc keeps your text.") {
                KeyboardShortcuts.Recorder(for: .polish)
            }

            // Accessibility trust has no change notification, so re-check every second while this is open.
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                step("hand.raised", "Accessibility",
                     detail: "Lets Polish read the message you're typing and put the corrected text back.") {
                    if Accessibility.isTrusted {
                        checkmark("Allowed")
                    } else {
                        Button("Allow…") {
                            Accessibility.requestTrust()
                            SystemSettings.open(.accessibility)
                        }
                    }
                }
            }

            step("cpu", "On-device model", detail: status.status.menuTitle) {
                switch status.status {
                case .ready:
                    checkmark("Ready")
                case .unavailable(.appleIntelligenceNotEnabled):
                    Button("Open Settings…") { SystemSettings.open(.appleIntelligence) }
                case .unavailable(.modelNotReady):
                    ProgressView().controlSize(.small)
                case .unavailable:
                    EmptyView()
                }
            }

            step("sparkles", "Try it", detail: "Polish this sample, or type your own.") {
                Button("Polish Sample") {
                    Task { await model.polishSample() }
                }
                .disabled(!status.status.isReady || model.isRunning || model.sample.isBlank)
            }
            sample

            HStack {
                Spacer()
                Button("Done", action: done)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 500)
    }

    private var sample: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextEditor(text: $model.sample)
                .font(.body)
                .frame(height: 48)
                .scrollContentBackground(.hidden)
                .padding(6)
                .background(.background.secondary, in: .rect(cornerRadius: 6))
                .accessibilityLabel("Sample draft")
            switch model.state {
            case .idle:
                EmptyView()
            case .running:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Polishing…")
                }
            case .result(let result) where result.isUnchanged:
                Label("Looks good. No changes needed.", systemImage: "checkmark.circle")
            case .result(let result):
                Text(DiffText.attributed(result.diff, showRemovals: true))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel("Rewrite")
                    .accessibilityValue(result.text)
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
            }
        }
        .padding(.leading, 36)
    }

    private func step(_ icon: String, _ title: String, detail: String,
                      @ViewBuilder trailing: () -> some View) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .frame(width: 24)
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(detail)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            trailing()
        }
    }

    private func checkmark(_ text: String) -> some View {
        Label(text, systemImage: "checkmark.circle.fill")
            .foregroundStyle(.green)
    }
}

extension OnboardingModel {
    var isRunning: Bool {
        if case .running = state { true } else { false }
    }
}
