//
// Copyright © Agulhas Labs
//

import Foundation

/// Renders a valid walkbook's verdict in the contract's shape — what `simwalk validate` prints when there is nothing to complain about.
///
/// It lives in the core rather than in the CLI so the MCP face answers the same question with the same words; a verdict that reads differently depending on which face asked is two contracts.
///
/// **It states no saving, and that is the honest answer rather than a missing feature.** A validation stands in for nothing: no screenshot was taken, no tree was read, and a reader who skipped this answer would have skipped a file they already have. An answer that stood in for nothing says nothing about a saving, where claiming zero would be a measurement of something that was never weighed.
public struct WalkbookSummary {
    private let walkbook: Walkbook
    private let onDevice: Bool

    /// `onDevice` is `validate --device`: the walkbook is checked against the device target's rules, where the measured screens *are* measured, so the device-only note is left out.
    public init(_ walkbook: Walkbook, onDevice: Bool = false) {
        self.walkbook = walkbook
        self.onDevice = onDevice
    }

    /// Throws only if the walkbook cannot be encoded for hashing, which is the same operation a capture would have to perform to record its identity — so a walkbook this cannot summarise is one no bundle could attribute either.
    public func answer() throws -> Answer {
        let captureCount = walkbook.screens.reduce(0) { $0 + $1.states.count }
        let stepCount = walkbook.screens.reduce(0) { $0 + $1.route.count }
        var residue = walkbook.screens.map { screen in
            let states = screen.states.map(\.slug).joined(separator: ", ")
            return "  \(screen.id) — \(screen.route.count) step\(screen.route.count == 1 ? "" : "s") → [\(states)]"
        }
        // Stated in the verdict's residue rather than left to the docs, because "ok" over a list of every
        // screen reads as a green light for the walk and is not one. Nothing here boots a device or looks
        // at the app, so a route naming a control the current build stopped rendering validates perfectly
        // and then goes UNREACHABLE — which is exactly how it was met in the field.
        // A note and not a problem: the walkbook is valid, and only a device walk (`device walk`) measures.
        if !onDevice {
            MeasureOptIn.deviceOnlyNote(for: walkbook.screens).map { residue.append($0) }
        }
        MeasureOptIn.launchEnvironmentNote(for: walkbook).map { residue.append($0) }
        residue.append("checked without a device — a route naming a control this build no longer renders still validates; only `walk` can catch that")
        return try Answer(
            // The name, the app and the hash sit exactly where a bundle's header puts them — a manifest
            // records all three, so this is where a bundle's stated plan is checked against the plan in
            // hand — and the two counters a walkbook has that a bundle does not follow them.
            header: [
                "walk: '\(walkbook.name)'",
                "app: \(walkbook.appBundleID)",
                "walkbook: \(ShortHash.of(WalkbookIdentity.hash(of: walkbook)))",
                "screens: \(walkbook.screens.count)",
                "steps: \(stepCount)",
            ].joined(separator: "  "),
            verdict: .unqualified("\(captureCount) capture\(captureCount == 1 ? "" : "s") planned"),
            residue: residue
        )
    }

    /// The whole answer as text.
    public func render() throws -> String {
        try answer().text
    }
}
