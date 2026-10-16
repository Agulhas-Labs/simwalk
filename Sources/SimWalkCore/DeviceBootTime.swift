//
// Copyright © Agulhas Labs
//

import Foundation

/// When the simulator booted, as the host hands it to the XCUITest runner and the runner reads it back (SimWalk#88, #90 item 3).
///
/// The host writes ``environmentKey`` (with the `TEST_RUNNER_` prefix `xcodebuild` strips) and the runner reads it through ``age(in:now:)``. Both ends name the key and the parse here, in the package the runner links, so a typo on either side fails a test in `swift test` rather than quietly dropping the fresh-boot hint.
public struct DeviceBootTime {
    /// The runner-side variable: when the device booted, in seconds since 1970 as a decimal; absent means the host could not read it.
    public static var environmentKey: String {
        "SIMWALK_DEVICE_BOOTED_AT"
    }

    /// The variable the host sets, which `xcodebuild` forwards to the test process as ``environmentKey``.
    public static var hostEnvironmentKey: String {
        "TEST_RUNNER_" + environmentKey
    }

    /// The seconds since the device booted, read from the runner's `environment` at `now`.
    ///
    /// `nil` where the key is missing, is not a finite number, or names a time after `now` — a boot in the future is a wrong clock or a wrong read, and the refusal keeps its answered-sheet wording rather than name an age that cannot be.
    public static func age(in environment: [String: String], now: Date) -> TimeInterval? {
        guard let raw = environment[environmentKey], let seconds = TimeInterval(raw), seconds.isFinite else {
            return nil
        }
        let age = now.timeIntervalSince1970 - seconds
        return age >= 0 ? age : nil
    }
}
