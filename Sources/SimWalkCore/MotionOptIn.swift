//
// Copyright © Agulhas Labs
//

import Foundation

/// Which screens of a walk file a `motion` record with their captures (SimWalk#67): a screen's own `"motion": true`, or every screen when the walk is run with `--motion`.
///
/// **A capture option rather than a verb**, because the figures come from the watch between a route's last step and its capture, which a walk already makes; a separate verb would have to walk again to get them. The host writes ``hostEnvironmentKey`` for `--motion` and the runner reads it back through ``records(_:in:)`` — both ends name the key and the decision here, in the package the runner links, so a typo on either side fails a test in `swift test` rather than quietly recording nothing, as `DeviceBootTime` does for its key.
public struct MotionOptIn {
    /// The runner-side variable: `1` when the walk was run with `--motion`; absent means each screen decides for itself.
    public static var environmentKey: String {
        "SIMWALK_MOTION"
    }

    /// The variable the host sets, which `xcodebuild` forwards to the test process as ``environmentKey``.
    public static var hostEnvironmentKey: String {
        "TEST_RUNNER_" + environmentKey
    }

    /// The value the host sets ``hostEnvironmentKey`` to for `--motion`.
    public static var walkWideValue: String {
        "1"
    }

    /// Whether `screen`'s captures record `motion`, read from the runner's `environment`: always under `--motion`, otherwise only where the screen says `"motion": true`.
    ///
    /// **A screen with a motion budget records too** (`settleMs`, `layoutShifts`): a budget nothing records can only answer UNREACHABLE in `bundle audit`, so declaring one is asking for the motion it is checked against. A performance-only budget does not — it asks for `measure` (`MeasureOptIn`), not for a watch.
    ///
    /// **`--motion` wins over a screen's `"motion": false`**: the flag asks for every screen, and a walk that answered it with fewer would be a request neither honoured nor refused.
    public static func records(_ screen: Walkbook.Screen, in environment: [String: String]) -> Bool {
        environment[environmentKey] == walkWideValue || screen.motion == true || screen.budgets?.hasMotionBudget == true
    }
}
