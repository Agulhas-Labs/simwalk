//
// Copyright © Agulhas Labs
//

import Foundation

/// Whether a walk records Apple's accessibility audit on every state it captures (E1a).
///
/// Either the walkbook's top-level `"appleAudit": true` or `walk --apple-audit` turns it on for the whole walk.
///
/// **Opt-in because it costs** — about two seconds a state on a simulator (the floor is about 1.7 s; the slowest of 29 measured states took 6.6 s) — and because the audit moves scroll position, so the runner makes it after a state's capture and never mid-route. The host writes ``hostEnvironmentKey`` for the flag and the runner reads it back through ``records(_:in:)``, as `MotionOptIn` does, so a typo on either side fails a test rather than quietly recording nothing.
public struct AppleAuditOptIn {
    /// The runner-side variable: `1` when the walk was run with `--apple-audit`.
    public static var environmentKey: String {
        "SIMWALK_APPLE_AUDIT"
    }

    /// The variable the host sets, which `xcodebuild` forwards to the test process as ``environmentKey``.
    public static var hostEnvironmentKey: String {
        "TEST_RUNNER_" + environmentKey
    }

    /// The value the host sets ``hostEnvironmentKey`` to for `--apple-audit`.
    public static var walkWideValue: String {
        "1"
    }

    /// Whether the walk audits every state, read from the runner's `environment`: under `--apple-audit`, or where the walkbook says `"appleAudit": true`.
    public static func records(_ walkbook: Walkbook, in environment: [String: String]) -> Bool {
        environment[environmentKey] == walkWideValue || walkbook.appleAudit == true
    }
}
