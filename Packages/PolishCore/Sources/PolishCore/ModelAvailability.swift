import FoundationModels
import Observation

/// Live availability of the on-device model, for the menu bar and the auto-retry after a download (FR-7).
public enum ModelAvailability {
    /// The current status first, then each change. Ends when the consuming task is cancelled.
    public static func updates(model: SystemLanguageModel = .default) -> AsyncStream<ModelStatus> {
        AsyncStream { continuation in
            let task = Task {
                var last: ModelStatus?
                for await status in Observations({ ModelStatus.current(model: model) }) where status != last {
                    last = status
                    continuation.yield(status)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }
}
