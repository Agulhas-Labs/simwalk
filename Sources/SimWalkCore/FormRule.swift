//
// Copyright © Agulhas Labs
//

import Foundation

/// One question of form asked of two captures of the same screen in the same state: what is there on one side that is not there, in that order or in that box, on the other.
///
/// **Form, never value** (Brief §2.2). A rule reads sections — keys, roles, boxes, text runs by shape — and never a figure, a date or a row count: a different number than the reference is by definition not a flag. The differ says what is *there*; the model reading the answer decides what matters, so a rule flags a difference and names the crop that shows it rather than judging it.
public protocol FormRule: Sendable {
    /// The flags this rule raises on `run` against `reference`, in a stable order.
    func flags(reference: SegmentedCapture, run: SegmentedCapture) -> [FormFlag]
}
