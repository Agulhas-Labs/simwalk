//
// Copyright © Agulhas Labs
//

import Foundation

public extension String {
    /// The string with surrounding whitespace and newlines removed — the one spelling of "blank" the validators share.
    ///
    /// Package-wide rather than private to each validator because "is this field blank" must mean the same thing in a walkbook, in a manifest, and in a line read back from a child process: the walkbook's checks and the manifest's are supposed to be the same checks at two moments, and a second private copy is where that stops being true.
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// A path as it is written down rather than as it is resolved — an answer about a machine's own state should not publish that machine's username.
    ///
    /// Shared rather than private to the one report that first needed it: every face that names a path under `$HOME` owes a reader the same spelling, and a second copy is where one of them starts printing `/Users/…`.
    var tildedPath: String {
        #if os(macOS)
        let home = HomeDirectories.user().path
        #else
        let home = NSHomeDirectory()
        #endif
        return hasPrefix(home) ? "~" + dropFirst(home.count) : self
    }

    /// The string padded on the left to `width`, so a column of counts reads down its own units rather than its first digits.
    func leftPadded(_ width: Int) -> String {
        count >= width ? self : String(repeating: " ", count: width - count) + self
    }

    /// The string padded on the right to `width`, for a column of names the figures beside it have to line up under.
    func rightPadded(_ width: Int) -> String {
        count >= width ? self : self + String(repeating: " ", count: width - count)
    }
}
