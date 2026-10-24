import Observation
import PolishCore

/// Holds the on-device model's availability for the menu bar status line and the auto-retry (FR-7).
@MainActor
@Observable
final class ModelStatusModel {
    private(set) var status: ModelStatus
    /// Called after every change, so the review panel can retry once the model finishes downloading.
    @ObservationIgnored var onChange: ((ModelStatus) -> Void)?
    @ObservationIgnored private var task: Task<Void, Never>?

    /// Pass `ModelAvailability.updates()` to follow live changes; tests pass nothing.
    init(status: ModelStatus = .current(), updates: AsyncStream<ModelStatus>? = nil) {
        self.status = status
        Log.ui.info("Model status at launch: \(status.menuTitle, privacy: .public)")
        guard let updates else { return }
        task = Task { [weak self] in
            for await status in updates {
                self?.update(status)
            }
        }
    }

    func update(_ status: ModelStatus) {
        guard status != self.status else { return }
        self.status = status
        Log.ui.info("Model status: \(status.menuTitle, privacy: .public)")
        onChange?(status)
    }
}
