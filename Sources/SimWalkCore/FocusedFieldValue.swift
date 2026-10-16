//
// Copyright © Agulhas Labs
//

import Foundation

/// The text-entry field holding keyboard focus, as a key tap read it.
///
/// Three states, because two were once one (SimWalk#96): no field holding focus is a fact about the screen, an unreadable one is a fact about the read, and only the first may stand for "the field's first character is coming".
public enum FocusedFieldValue: Equatable, Sendable {
    /// No text-entry element holds keyboard focus.
    case none
    /// One may, but the live read of it failed.
    case unreadable
    /// The focused field's string value.
    case value(String)
}
