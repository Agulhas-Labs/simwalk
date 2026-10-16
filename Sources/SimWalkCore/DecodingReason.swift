//
// Copyright © Agulhas Labs
//

import Foundation

/// Turns a `DecodingError` into one sentence naming the key path that failed.
///
/// The single generator for that sentence: a walkbook and a manifest are both JSON read from disk, and both refuse in the author's terms rather than handing back Foundation's multi-line dump of a context object. Two copies of this would drift into two different vocabularies for the same failure.
struct DecodingReason {
    static func sentence(for error: Error) -> String {
        guard let decodingError = error as? DecodingError else {
            return error.localizedDescription
        }
        return switch decodingError {
        case let .keyNotFound(key, context):
            "missing key '\(key.stringValue)'\(pathSuffix(context))"
        case let .typeMismatch(type, context):
            "expected \(type)\(pathSuffix(context))"
        case let .valueNotFound(type, context):
            "missing value of type \(type)\(pathSuffix(context))"
        case let .dataCorrupted(context):
            // `.dataCorrupted` is Foundation's own case for torn JSON, *and* for a value its field cannot
            // take (`"theme":"purple"` — "Cannot initialize Theme from invalid String value purple"), *and*
            // this repo's for a schema violation it wrote itself (`StrictKeyDecoding`, a route step naming
            // the wrong keys). Only the first is malformed JSON. What tells it apart is the parser's own
            // complaint, attached as `underlyingError` when the bytes did not parse; the other two carry
            // none, and their `debugDescription` is already a sentence in the author's terms. Calling a
            // well-formed document "malformed JSON" for a key it merely does not recognise was the sharpest
            // case of getting this wrong: the JSON parsed perfectly well.
            context.underlyingError == nil
                ? "\(context.debugDescription)\(pathSuffix(context))"
                : "malformed JSON\(pathSuffix(context)): \(context.debugDescription)"
        @unknown default:
            decodingError.localizedDescription
        }
    }

    /// The path spelled the way `WalkbookProblem.unknownKey` spells it (`screens[0].states[1]`), because a walkbook refusal now lists the two side by side — Foundation's own `screens.Index 0.states.Index 1` beside it read as two different places.
    private static func pathSuffix(_ context: DecodingError.Context) -> String {
        let path = StrictKeyDecoding.renderedPath(context.codingPath)
        return path.isEmpty ? "" : " at \(path)"
    }
}
