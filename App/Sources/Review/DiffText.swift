import PolishCore
import SwiftUI

/// Renders the word diff: insertions underlined in green; removals struck through in red, shown on request.
enum DiffText {
    static func attributed(_ diff: [DiffSegment], showRemovals: Bool) -> AttributedString {
        var text = AttributedString()
        for segment in diff {
            var run = AttributedString(segment.text)
            switch segment.kind {
            case .same:
                break
            case .inserted:
                run.swiftUI.underlineStyle = .single
                run.swiftUI.foregroundColor = .green
            case .removed:
                guard showRemovals else { continue }
                run.swiftUI.strikethroughStyle = .single
                run.swiftUI.foregroundColor = .red
            }
            text += run
        }
        return text
    }
}
