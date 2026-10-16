//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import Testing

/// `SystemTapScroll.keepsDragging`: the drags stop at the first read that finds an enabled match a tap would land on, still moving or not (SimWalk#59).
struct SystemTapScrollTests {
    /// **The bouncing list** (SimWalk#59): `Allow` enabled and hittable, its box read at y 566.67 then 580.00, stops the drags.
    ///
    /// The two-read check refuses it — that stays the step poll's to do — where before the drags ran on to the twelfth.
    @Test
    func anEnabledMatchStillMovingStopsTheDrags() {
        var settling = Self.allow
        settling.frame.y = 580
        var snapshots = [Self.allow, settling]
        let read: (Int) -> AXNode? = { _ in snapshots.isEmpty ? nil : snapshots.removeFirst() }

        #expect(!SystemTapScroll.keepsDragging(over: [0], snapshot: read, hittable: { _ in true }))

        snapshots = [Self.allow, settling]
        #expect(SystemControlReread.firstTappable(among: [0], snapshot: read, live: { $0 }) == nil)
    }

    /// A read that finds no match drags on.
    @Test
    func noMatchKeepsDragging() {
        #expect(SystemTapScroll.keepsDragging(over: [Int](), snapshot: { _ in Self.allow }, hittable: { _ in true }))
    }

    /// A disabled match would take no tap, so it does not stop the drags — nor does a later one that reads disabled while an earlier one has gone.
    @Test
    func aDisabledMatchKeepsDragging() {
        var disabled = Self.allow
        disabled.isEnabled = false

        #expect(SystemTapScroll.keepsDragging(over: [0], snapshot: { _ in disabled }, hittable: { _ in true }))
        #expect(SystemTapScroll.keepsDragging(over: [0, 1], snapshot: { $0 == 0 ? nil : disabled }, hittable: { _ in true }))
    }

    /// A match a tap would not land on — HealthKit's below-the-fold cell reads as bare text with a made-up frame — is not in reach, and the drags go on; one enabled, hittable match among several stops them.
    @Test
    func onlyAHittableMatchStopsTheDrags() {
        #expect(SystemTapScroll.keepsDragging(over: [0], snapshot: { _ in Self.allow }, hittable: { _ in false }))
        #expect(!SystemTapScroll.keepsDragging(over: [0, 1], snapshot: { _ in Self.allow }, hittable: { $0 == 1 }))
    }

    private static let allow = AXNode(
        type: "Button",
        frame: AXNode.Frame(x: 16, y: 566.67, width: 361, height: 50),
        label: "Allow",
        identifier: "UIA.Health.Allow.Button"
    )
}
