import Observation
import PolishCore

/// Holds the on-device model's availability for the menu bar status line.
/// Phase 3 replaces the one-time read with live updates (model downloading → ready).
@MainActor
@Observable
final class ModelStatusModel {
    private(set) var status: ModelStatus

    init(status: ModelStatus = .current()) {
        self.status = status
        Log.ui.info("Model status at launch: \(status.menuTitle, privacy: .public)")
    }
}
