//
// Copyright © Agulhas Labs
//

import Foundation

/// When a live session's runner stops on its own: after ``timeout`` without a request.
///
/// A resident runner holds the simulator's XCUITest session for as long as it runs, so one an agent forgot must not hold it for ever. The decision lives here rather than in the runner, which `swift test` never compiles, and time arrives as a parameter.
public struct LiveSessionIdle: Equatable, Sendable {
    public let timeout: TimeInterval

    public init(timeout: TimeInterval) {
        self.timeout = timeout
    }

    /// Fifteen minutes.
    public static var standardTimeout: TimeInterval {
        15 * 60
    }

    /// The host environment variable that shortens the timeout — for a test of the timeout itself, which would otherwise wait fifteen minutes.
    public static var overrideVariable: String {
        "SIMWALK_SESSION_IDLE_SECONDS"
    }

    /// The timeout `value` states in whole or fractional seconds, when it states a positive one; the standard fifteen minutes otherwise.
    public static func timeout(fromOverride value: String?) -> TimeInterval {
        guard let value, let seconds = TimeInterval(value), seconds > 0 else { return standardTimeout }
        return seconds
    }

    /// Whether a session whose last request arrived at `lastRequest` (or which became ready then) has now gone unused for the whole timeout.
    public func hasExpired(lastRequest: Date, now: Date) -> Bool {
        now.timeIntervalSince(lastRequest) >= timeout
    }

    /// `15 min`, or `20 s` below a minute.
    static func describe(_ timeout: TimeInterval) -> String {
        timeout >= 60 && timeout.truncatingRemainder(dividingBy: 60) == 0 ? "\(Int(timeout / 60)) min" : "\(Int(timeout.rounded())) s"
    }
}
