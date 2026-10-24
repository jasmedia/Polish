import PolishCore
import SwiftUI

extension Tone {
    /// Menu, settings and panel name (FR-8).
    var title: String {
        switch self {
        case .keep: "Keep my tone"
        case .casual: "Casual"
        case .professional: "Professional"
        case .concise: "Concise"
        }
    }

    /// The tone Tab switches to in the review panel, wrapping around.
    var next: Tone {
        let all = Tone.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

/// The tone choice in the menu bar submenu and in Settings › General.
struct TonePicker: View {
    @Binding var tone: Tone
    let title: String

    var body: some View {
        Picker(title, selection: $tone) {
            ForEach(Tone.allCases, id: \.self) { tone in
                Text(tone.title).tag(tone)
            }
        }
    }
}
