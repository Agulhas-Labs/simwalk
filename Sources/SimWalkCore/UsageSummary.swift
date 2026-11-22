//
// Copyright © Agulhas Labs
//

import Foundation

/// The figures over a set of usage lines, from one function: how many calls, how many were walks, how many failed, how many were refused, and what they saved.
///
/// `simwalk usage` builds one over the lines it reports and the status line builds one over its session's lines, so the two cannot come to different figures for the same rows — the call count, the failure and refusal counts and the saving all pass through ``add(_:)``. A `--parallel` walk's breakdown line is part of its `walk` call and is never a call of its own, so it is left out here, in the one place both faces read.
public struct UsageSummary: Codable, Equatable, Sendable {
    /// Every call the lines record, a breakdown line excluded.
    public private(set) var calls = 0

    /// How many of those were `walk` calls.
    public private(set) var walks = 0

    /// How many failed — ``UsageLog/Entry/isFailure``, which `simwalk usage` counts as a failure.
    public private(set) var failures = 0

    /// How many were refused — ``UsageLog/Entry/isRefusal``, a caller's own argument turned away, which is left out of the failures.
    public private(set) var refusals = 0

    /// What the calls saved, each screenshot once and every served byte charged.
    public private(set) var ledger = SavingsLedger()

    public init() {}

    /// The summary over `entries`, in log order.
    public init(_ entries: [UsageLog.Entry]) {
        for entry in entries {
            add(entry)
        }
    }

    /// The tokens saved over every line added.
    public var tokensSaved: Int {
        ledger.saved
    }

    /// Whether every call was a walk, which is when a count is worded as walks rather than calls.
    public var onlyWalks: Bool {
        calls == walks
    }

    /// Takes one line in; a breakdown line changes nothing.
    public mutating func add(_ entry: UsageLog.Entry) {
        guard entry.tool != UsageLog.parallelTool else { return }
        calls += 1
        walks += entry.tool == Self.walkTool ? 1 : 0
        failures += entry.isFailure ? 1 : 0
        refusals += entry.isRefusal ? 1 : 0
        ledger.add(entry)
    }

    private static var walkTool: String {
        "walk"
    }
}
