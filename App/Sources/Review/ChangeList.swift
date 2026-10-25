import PolishCore
import SwiftUI

/// The fixes with a reason each ("their → there  wrong word"), collapsed under the diff (FR-9). Built
/// from the same diff, so it adds no time. Shown only when Settings › Show a list of changes is on.
struct ChangeList: View {
    let changes: [Change]
    @State private var isExpanded = false

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(changes.enumerated()), id: \.offset) { _, change in
                    Text(Self.line(change))
                        .lineLimit(3)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(Self.spoken(change))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 4)
        } label: {
            Text(Self.title(changes.count))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    /// "~~teh~~ → the  spelling"; a word only added or removed shows one side.
    static func line(_ change: Change) -> AttributedString {
        var line = AttributedString()
        if !change.from.isEmpty {
            var from = AttributedString(change.from)
            from.strikethroughStyle = .single
            from.foregroundColor = .secondary
            line += from
            if !change.to.isEmpty { line += AttributedString(" → ") }
        }
        line += AttributedString(change.to)
        var reason = AttributedString("  \(change.reason.rawValue)")
        reason.font = .caption
        reason.foregroundColor = .secondary
        return line + reason
    }

    static func spoken(_ change: Change) -> String {
        let reason = change.reason.rawValue
        if change.from.isEmpty { return "Added \(change.to), \(reason)" }
        if change.to.isEmpty { return "Removed \(change.from), \(reason)" }
        return "\(change.from) to \(change.to), \(reason)"
    }

    static func title(_ count: Int) -> String {
        count == 1 ? "1 change" : "\(count) changes"
    }
}
