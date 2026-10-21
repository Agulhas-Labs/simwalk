//
// Copyright © Agulhas Labs
//

import Foundation

/// Reads the text off a screenshot, so a rule that needs to know what was drawn (not what the tree says) can ask without the core linking a recognition framework.
///
/// The `bundle audit` command supplies the host's recogniser; a face without one passes none, and `truncatedText` then says it did not run.
public protocol ScreenTextRecognizing: Sendable {
    /// The lines recognised in the PNG at `url`, each placed as fractions of the image with a top-left origin.
    func lines(inPNGAt url: URL) throws -> [MirrorTextLine]
}
