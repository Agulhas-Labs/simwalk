//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// A system sheet's control read twice, either side of the live reads a tap needs (SimWalk#51, item 1): only a second read of the same control lets the tap go ahead.
struct SystemControlRereadTests {
    /// The control read twice, unchanged: the tap goes ahead.
    @Test
    func theSameControlReadAgainIsConfirmed() {
        let allow = Self.allow

        #expect(SystemControlReread.confirms(allow, as: allow))
    }

    /// Less than half a point of drift between two reads of one box is the same control.
    @Test
    func aBoxThatDriftsUnderHalfAPointIsTheSameControl() {
        var drifted = Self.allow
        drifted.frame.y += 0.25

        #expect(SystemControlReread.confirms(drifted, as: Self.allow))
    }

    /// An element whose second snapshot could not be taken has gone, and is never tapped.
    @Test
    func aControlGoneByTheSecondReadIsNotConfirmed() {
        #expect(!SystemControlReread.confirms(nil, as: Self.allow))
    }

    /// **The reordered set** (SimWalk#51, item 1): index N now names another row, with its own identifier, of the same type and label.
    @Test
    func anotherControlAtTheSameIndexIsNotConfirmed() {
        var other = Self.allow
        other.identifier = "UIA.Health.AuthorizationSheet.DenyButton"

        #expect(!SystemControlReread.confirms(other, as: Self.allow))
    }

    /// A different label at the same index is another control.
    @Test
    func aDifferentLabelIsNotConfirmed() {
        var other = Self.allow
        other.label = "Don't Allow"

        #expect(!SystemControlReread.confirms(other, as: Self.allow))
    }

    /// A row's bare text that has turned into its `Button` while the table decelerates is not the element first read.
    @Test
    func aControlWhoseTypeChangedIsNotConfirmed() {
        var text = Self.allow
        text.type = "StaticText"

        #expect(!SystemControlReread.confirms(Self.allow, as: text))
    }

    /// A box that moved between the reads — a row sliding under them — is not tapped at the live frame read in between.
    @Test
    func aControlThatMovedIsNotConfirmed() {
        var moved = Self.allow
        moved.frame.y += 44

        #expect(!SystemControlReread.confirms(moved, as: Self.allow))
    }

    /// A control disabled by its second read would take no tap.
    @Test
    func aControlDisabledByTheSecondReadIsNotConfirmed() {
        var disabled = Self.allow
        disabled.isEnabled = false

        #expect(!SystemControlReread.confirms(disabled, as: Self.allow))
    }

    /// **The second read is taken, after the live reads, and checked** (SimWalk#55): a candidate whose row slid under the live reads is passed over for the next, and the sequence each candidate is read in is snapshot, live, snapshot.
    @Test
    func aCandidateThatMovedUnderItsLiveReadsIsPassedOverForTheNext() {
        var slid = Self.allow
        slid.frame.y += 44
        let reads = ScriptedReads(snapshots: [0: [Self.allow, slid], 1: [Self.allow, Self.allow]])

        let found = reads.firstTappable(among: [0, 1])

        #expect(found?.live == 1)
        #expect(reads.log == ["snapshot 0", "live 0", "snapshot 0", "snapshot 1", "live 1", "snapshot 1"])
    }

    /// `Button`s come before any other kind, whatever the tree order, and a confirmed control `accepts` refuses is not taken.
    @Test
    func buttonsComeFirstAndTheCallerHasTheLastWord() {
        var text = Self.allow
        text.type = "StaticText"
        let reads = ScriptedReads(snapshots: [0: [text, text], 1: [Self.allow, Self.allow]])

        #expect(reads.firstTappable(among: [0, 1])?.live == 1)
        #expect(reads.firstTappable(among: [0, 1]) { $0.type != "Button" }?.live == 0)
        #expect(reads.firstTappable(among: [0, 1]) { _ in false } == nil)
    }

    private static let allow = AXNode(
        type: "Button",
        frame: AXNode.Frame(x: 16, y: 700, width: 361, height: 50),
        label: "Allow",
        identifier: "UIA.Health.AuthorizationSheet.AllowButton"
    )
}

private extension SystemControlRereadTests {
    /// Each element's snapshots in the order they are taken, the last one held; every live read succeeds, answering the element; every read is logged.
    final class ScriptedReads {
        private var snapshots: [Int: [AXNode]]
        private(set) var log: [String] = []

        init(snapshots: [Int: [AXNode]]) {
            self.snapshots = snapshots
        }

        func firstTappable(among matches: [Int], where accepts: (AXNode) -> Bool = { _ in true }) -> SystemControlReread.Tappable<Int>? {
            SystemControlReread.firstTappable(among: matches, snapshot: snapshot, live: live, where: accepts)
        }

        private func snapshot(_ element: Int) -> AXNode? {
            log.append("snapshot \(element)")
            guard let queue = snapshots[element], let next = queue.first else { return nil }
            if queue.count > 1 {
                snapshots[element] = Array(queue.dropFirst())
            }
            return next
        }

        private func live(_ element: Int) -> Int? {
            log.append("live \(element)")
            return element
        }
    }
}
