import Testing
@testable import Polish
import PolishCore

@MainActor
struct PolishAppTests {
    @Test func statusModelKeepsInjectedStatus() {
        let model = ModelStatusModel(status: .unavailable(.deviceNotEligible))
        #expect(model.status == .unavailable(.deviceNotEligible))
    }
}
