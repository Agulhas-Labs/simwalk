//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// A route-probe report that describes a dry run of a given walkbook — one probe per screen, with the outcome each is given.
///
/// A target rather than a copy per suite, as `CaptureBundleFixture` is: the core's report tests and the CLI's dry-run tests both need one, and a report built two ways is two answers to what the runner writes.
public struct RouteProbeFixture {
    /// The build every fixture report was followed against, unless a test names another.
    public static var buildHash: String {
        "58ebbd24aa00"
    }

    /// When every fixture report's runner started, unless a test names another.
    public static let startedAt = Date(timeIntervalSince1970: 1_786_867_200.125)

    /// The nonce every fixture report carries, unless a test names another — matched by `WalkDryRun.perform(nonce:)` in a test that stages one of these ahead of a run.
    public static var nonce: String {
        "fixture-nonce-0000"
    }

    /// A report of `walkbook` whose probes come to `outcomes`, in screen order — every route resolved when `outcomes` is empty.
    public static func report(
        of walkbook: Walkbook,
        outcomes: [RouteProbe.Outcome] = [],
        buildHash: String = buildHash,
        startedAt: Date = startedAt,
        nonce: String = nonce
    ) throws -> RouteProbeReport {
        let probes = walkbook.screens.enumerated().map { index, screen in
            RouteProbe(screenID: screen.id, route: screen.route, outcome: outcomes.indices.contains(index) ? outcomes[index] : .resolved)
        }
        return try RouteProbeReport(
            walkName: walkbook.name,
            appBundleID: walkbook.appBundleID,
            appBuildHash: buildHash,
            walkbookHash: WalkbookIdentity.hash(of: walkbook),
            runnerCommit: "c0ffee0000000000000000000000000000000000",
            device: CaptureManifest.Device(name: "iPhone 17 Pro", udid: "UDID-1", osVersion: "26.5"),
            startedAt: startedAt,
            nonce: nonce,
            probes: probes
        )
    }
}
