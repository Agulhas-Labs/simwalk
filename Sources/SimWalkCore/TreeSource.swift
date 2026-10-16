//
// Copyright © Agulhas Labs
//

import Foundation

/// A device's app tree read over time: the reads and the wait a watch for a still screen is built on, while the core decides when the screen has held still (SimWalk#39).
///
/// The runner's device, or a test's script. `CaptureSource` adds what a capture needs on top — the picture and SpringBoard's tree.
public protocol TreeSource {
    /// The app's accessibility tree now.
    func appTree() throws -> AXNode
    /// How long the source has been watching.
    func elapsed() -> TimeInterval
    /// Waits `interval` before the next read.
    func pause(_ interval: TimeInterval)
}
