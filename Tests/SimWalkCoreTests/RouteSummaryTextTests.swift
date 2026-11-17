//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// A long route prints short on an answer line (SimWalk#256), and a dry run leads with the routes that did not resolve (SimWalk#260).
struct RouteSummaryTextTests {
    @Test
    func alongCapturedRouteExtendingAnEarlierOnePrintsTheEarlierIDAndTheRest() {
        let lines = Self.bundleLines([
            Self.captured("breakdown", Self.steps(115)),
            Self.captured("complete", Self.steps(115) + [.tap(label: "Done"), .tap(label: "Finish")]),
        ])

        #expect(lines[1].contains("via breakdown + tap 'Done' → tap 'Finish'"))
        #expect(!lines[1].contains("s0"))
    }

    @Test
    func alongCapturedRouteWithNoPrefixPrintsItsCountAndEnds() {
        let lines = Self.bundleLines([Self.captured("long", Self.steps(117))])

        #expect(lines[0].contains("via 117 steps: tap 's0' … tap 's116'"))
    }

    @Test
    func alongRouteIdenticalToAnEarlierOnePrintsThatScreensRoute() {
        let lines = Self.bundleLines([
            Self.captured("first", Self.steps(20)),
            Self.captured("second", Self.steps(20)),
        ])

        #expect(lines[1].contains("via first's route"))
    }

    @Test
    func anEarlierUnreachableScreenIsNeverNamedAsAPrefix() {
        let unreachable = CaptureManifest.ScreenRecord(id: "stuck", outcome: .unreachable(routeTried: Self.steps(30)), routeTaken: Self.steps(20))
        let lines = Self.bundleLines([unreachable, Self.captured("later", Self.steps(25))])

        #expect(lines[1].contains("via 25 steps: tap 's0' … tap 's24'"))
        #expect(!lines[1].contains("stuck"))
    }

    @Test
    func aRouteOfFourStepsOrFewerPrintsInFull() {
        let lines = Self.bundleLines([Self.captured("short", Self.steps(4))])

        #expect(lines[0].contains("via tap 's0' → tap 's1' → tap 's2' → tap 's3'"))
    }

    @Test
    func anUnreachableLongRoutePrintsBothPartsShort() {
        let screen = CaptureManifest.ScreenRecord(id: "stuck", outcome: .unreachable(routeTried: Self.steps(30)), routeTaken: Self.steps(20))
        let lines = Self.bundleLines([screen])

        #expect(lines[0].contains("route tried: 30 steps: tap 's0' … tap 's29'; completed: 20 steps: tap 's0' … tap 's19'"))
    }

    @Test
    func aDryRunListsTheDriftedRouteFirstKeepingItsPositionAndShortensWhatResolved() {
        let long = Self.steps(60)
        var probes = (0 ..< 7).map { RouteProbe(screenID: "p\($0)", route: Self.steps(10), outcome: .resolved) }
        probes[0] = RouteProbe(screenID: "p0", route: Array(long.prefix(58)), outcome: .resolved)
        probes[5] = RouteProbe(screenID: "p5", route: long, outcome: .drifted(step: 58, reason: nil))
        let report = RouteProbeReport(
            walkName: "w", appBundleID: "b", appBuildHash: "h", walkbookHash: "x", runnerCommit: nil,
            device: CaptureManifest.Device(name: "d", udid: "u", osVersion: "26"),
            startedAt: Date(timeIntervalSince1970: 0), nonce: "n", probes: probes
        )

        let residue = RouteProbeSummary(report).answer().residue

        #expect(residue[0].hasPrefix("  6 p5 — DRIFTED at step 59 of 60"))
        #expect(residue[0].contains("resolved before it: p0's route; not reached: tap 's59'"))
        #expect(residue[1].hasPrefix("  1 p0 — resolved: 58 steps:"))
        #expect(residue[2] == "  2 p1 — resolved: p0's first 10 steps")
        #expect(residue[3] == "  3 p2 — resolved: p1's route")
    }

    @Test
    func aLongRouteTurningOffAnEarlierOneNamesTheRunItSharesAndWhereItTurns() {
        let lines = Self.bundleLines([
            Self.captured("complete", Self.steps(117) + [.tapPoint(label: nil, point: [200, 250]), .scrollTo(label: "1-day streak")]),
            Self.captured("home-after", Self.steps(117) + [.tap(label: "Done"), .scrollTo(label: "1-day streak")]),
        ])

        #expect(lines[1].hasSuffix("via complete's first 117 steps + tap 'Done' → scrollTo '1-day streak'"))
    }

    @Test
    func aRunSharedPastTheFullRouteLimitIsNamedAndALongerRestPrintsShort() {
        let lines = Self.bundleLines([
            Self.captured("trunk", Self.steps(30)),
            Self.captured("branch", Self.steps(10) + Self.steps(20, named: "b")),
        ])

        #expect(lines[1].hasSuffix("via trunk's first 10 steps + 20 steps: tap 'b0' … tap 'b19'"))
    }

    @Test
    func aRunOfFourStepsOrFewerSharedWithAnEarlierRouteIsNotNamed() {
        let lines = Self.bundleLines([
            Self.captured("trunk", Self.steps(30)),
            Self.captured("branch", Self.steps(4) + Self.steps(20, named: "b")),
        ])

        #expect(lines[1].hasSuffix("via 24 steps: tap 's0' … tap 'b19'"))
    }

    private static func steps(_ count: Int, named prefix: String = "s") -> [Walkbook.RouteStep] {
        (0 ..< count).map { .tap(label: "\(prefix)\($0)") }
    }

    private static func captured(_ id: String, _ route: [Walkbook.RouteStep]) -> CaptureManifest.ScreenRecord {
        CaptureManifest.ScreenRecord(
            id: id,
            outcome: .captured,
            routeTaken: route,
            captures: [CaptureManifest.StateCapture(screenID: id, state: Walkbook.CaptureState(theme: .light))]
        )
    }

    /// The screen lines of the summary of a manifest holding `screens`.
    private static func bundleLines(_ screens: [CaptureManifest.ScreenRecord]) -> [String] {
        var manifest = CaptureBundleTests.manifest()
        manifest.screens = screens
        let bundle = CaptureBundle(url: URL(fileURLWithPath: "/tmp/example.simwalk"), manifest: manifest)
        return Array(CaptureBundleSummary(bundle).answer().residue.prefix(screens.count))
    }
}
