//
// Copyright © Agulhas Labs
//

import Foundation

/// The line a walk that failed in XCTest's own machinery adds when the Mac was far too loaded for XCTest to keep time (SimWalk#277).
public struct HostLoadLine {
    /// Failure texts that are XCTest or its host timing out or falling over, which a loaded Mac produces whatever the route.
    public static let signatures = [
        "Timed out while evaluating UI query",
        "Timed out while fetching snapshot",
        "Timed out while synthesizing event",
        "Critical process xctest crashed",
        "** TEST EXECUTE FAILED **",
    ]

    /// How many times the core count the one-minute load average must exceed.
    public static let multiple = 4.0

    /// The line, or `nil` unless a failure text holds a signature and the load is above ``multiple`` times `cores`.
    public static func line(failureTexts: [String], loadAverage: Double?, cores: Int) -> String? {
        guard let loadAverage, loadAverage > multiple * Double(cores) else { return nil }
        guard failureTexts.contains(where: { text in signatures.contains { text.contains($0) } }) else { return nil }
        return "host: load \(Int(loadAverage.rounded())) on \(cores) cores — XCTest timed out under it, so this is likely load, not the route; walk again when it falls"
    }
}
