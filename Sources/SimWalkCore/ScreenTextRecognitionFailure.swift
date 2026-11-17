//
// Copyright © Agulhas Labs
//

import Foundation

/// An error a `ScreenTextRecognizing` throws that can say, in one phrase, why recognition failed.
///
/// A rule that catches it keeps the cause so its answer can name it; any other error is described with `String(describing:)`.
public protocol ScreenTextRecognitionFailure: Error {
    /// What went wrong, in the recogniser's or the file system's words.
    var cause: String { get }
}
