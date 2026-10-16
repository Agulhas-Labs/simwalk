//
// Copyright © Agulhas Labs
//

import Foundation

/// The locale identifiers accepted by `Walkbook.CaptureState.locale`.
///
/// Checked against `Locale.availableIdentifiers` rather than a list of our own, since the host and the simulator run the same Foundation and therefore the same ICU data. The residual risk is a host whose data differs from the simulator's, which would refuse a locale that would in fact have worked — a loud, immediately fixable wrong answer, against a silent one that captures the default under a slug naming the locale. That trade is the whole reason this check exists.
public struct LocaleIdentifierName {
    private static let available: Set<String> = Set(Locale.availableIdentifiers)

    /// Whether the simulator would honour this identifier.
    public static func isValid(_ identifier: String) -> Bool {
        available.contains(identifier)
    }

    /// The identifier the author probably meant, when a rejected value is recognisably a near miss.
    ///
    /// The miss worth naming is BCP-47 punctuation: `en-GB` is the spelling every web API uses and the one Foundation does not take here. Case is the other, since `en_gb` reads correct to a human. Anything else returns `nil` — a language that simply is not available has no near neighbour worth guessing at.
    public static func suggestion(for identifier: String) -> String? {
        let underscored = identifier.replacingOccurrences(of: "-", with: "_")
        if underscored != identifier, available.contains(underscored) {
            return underscored
        }
        return available.first { $0.lowercased() == underscored.lowercased() }
    }
}
