//
// Copyright © Agulhas Labs
//

import SwiftUI

/// One row: a title on the leading side and a value on the trailing side.
///
/// The baseline is the standard adaptive row: an `HStack` at ordinary sizes and, at an accessibility size, a `VStack` with the title above the value, so the value never wraps up beside the title and VoiceOver reads title first. With `truncation` on each title is a single line in a fixed 150-point width, so it fits at the default size and ends in an ellipsis at an accessibility size. With `regression` on the row is a `ZStack` whose two texts are each pinned to their own edge at full width, so at an accessibility size they draw over each other. Both texts stay separate accessibility elements either way.
struct AccountRow: View {
    let title: LocalizedStringKey
    let value: LocalizedStringKey
    let regression: Bool
    let truncation: Bool
    let identifier: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        if truncation {
            VStack(alignment: .leading) {
                Text(title)
                    .lineLimit(1)
                    .frame(width: 150, alignment: .leading)
                    .accessibilityIdentifier(identifier)
                Text(value)
                    .foregroundStyle(.secondary)
            }
        } else if regression {
            ZStack {
                Text(title)
                    .accessibilityIdentifier(identifier)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(value)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        } else if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading) {
                Text(title)
                    .accessibilityIdentifier(identifier)
                Text(value)
                    .foregroundStyle(.secondary)
            }
        } else {
            HStack {
                Text(title)
                    .accessibilityIdentifier(identifier)
                Spacer()
                Text(value)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
