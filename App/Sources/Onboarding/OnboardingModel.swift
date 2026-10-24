import Observation
import PolishCore

/// The first-run window's sample rewrite. It polishes text typed in Polish's own window, so it goes
/// straight to the pipeline: the text bridge never reads from Polish itself.
@MainActor
@Observable
final class OnboardingModel {
    enum SampleState {
        case idle
        case running
        case result(PolishResult)
        case failed(String)
    }

    var sample = "hey team, i will send the report tmrw. can you review it befor friday?"
    private(set) var state: SampleState = .idle

    @ObservationIgnored private let pipeline: Pipeline

    init(pipeline: Pipeline) {
        self.pipeline = pipeline
    }

    func polishSample() async {
        state = .running
        do {
            state = .result(try await pipeline.polish(text: sample))
        } catch {
            let polishError = error as? PolishError ?? .generationFailed(code: String(describing: type(of: error)))
            Log.ui.error("Sample rewrite failed: \(polishError.code, privacy: .public)")
            state = .failed(polishError.message)
        }
    }
}
