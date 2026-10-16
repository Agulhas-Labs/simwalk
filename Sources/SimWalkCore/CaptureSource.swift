//
// Copyright © Agulhas Labs
//

import Foundation

/// What `SettledCapture.take` reads one state's capture from: the runner's device, or a test's script (SimWalk#39 item 5).
///
/// **The runner only reads; the core decides.** Each requirement is something only the device can do — read a tree and wait (`TreeSource`), take the picture — so the sequence built on them, and the refusal under a system alert with it, is the core's and replayed in tests. SpringBoard's tree is a requirement rather than an option, so a source that cannot say whether an alert covers the app does not compile.
public protocol CaptureSource: TreeSource {
    /// SpringBoard's tree now, where a system alert over the app is drawn.
    func springboardTree() throws -> AXNode
    /// The screen's picture now, as PNG data.
    func screenshot() -> Data
}
