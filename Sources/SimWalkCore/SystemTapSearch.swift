//
// Copyright © Agulhas Labs
//

import Foundation

/// One `systemTap`'s search of the app's window, poll by poll: what it admits, what it passed over, and why it found nothing it could take (SimWalk#48, #55).
///
/// **The only way the runner admits a control in the app's window, and the only way it gets a refusal**, so each poll's live matches are noted where they are judged: before, the runner kept a `PassedOver` beside the loop and called `poll` itself, and deleting that call left `swift test` green while every snapshot-blind refusal read as a missing control (SimWalk#55 item 1). The runner keeps the live query — `find` walks the matches, offering each it reads to the predicate it is handed — and this value decides.
public struct SystemTapSearch {
    private let label: String
    private let scope: SystemSheetScope
    private var passedOver = SystemSheetScope.PassedOver()
    private var sawSheet = false
    private var sawSpringBoardAlert = false
    private var sawAppWindowSheet = false

    /// A search for `label`, admitting only what `scope` admits.
    public init(label: String, scope: SystemSheetScope) {
        self.label = label
        self.scope = scope
    }

    /// Why the step found nothing it could take, from every poll made: what its UNREACHABLE says, and the cause the walk's verdict names it under where there is one.
    ///
    /// `bootAge` is the seconds since the device booted as the runner reads it now, `nil` where the host could not tell; a refusal that saw no sheet on a freshly booted device names the boot (SimWalk#88). **A sheet seen by any poll keeps the answered-sheet wording**: a sheet that was up and whose control the label missed is not one HealthKit failed to raise, and "wait and walk again" would be wrong advice for it.
    public func refusal(bootAge: TimeInterval?) -> Refusal {
        Refusal(reason: scope.refusal(for: label, passedOver: passedOver, bootAge: sawSheet ? nil : bootAge, springBoardShowedAlert: sawSpringBoardAlert, appWindowShowedSheet: sawAppWindowSheet), cause: passedOver.unseenByTree ? .snapshotBlind : nil)
    }

    /// One poll of the app's window, whose tree read `tree`, through `find`.
    ///
    /// `springBoardShowedSheet` is whether SpringBoard showed a sheet or alert this iteration, whether or not it held the label, so `refusal` does not take the device for one that raised none (SimWalk#88), and says SpringBoard showed an alert rather than none (SimWalk#91 item 3). **Required rather than a separate call**: a `sawSpringBoardSheet()` the runner could delete left `swift test` green with the fresh-boot wording wrong on a device that had shown a sheet, and the runner has no unit tests; as an argument, deleting the read's argument stops the runner compiling (SimWalk#91 item 11). It pins the call, not its honesty: a literal `false` in its place would still compile.
    ///
    /// `find` offers each live match it reads to the predicate it is given and returns the first taken, or `nil`. Where nothing is taken, the matches it offered are noted for `refusal`.
    public mutating func poll<Control>(_ tree: AXNode, springBoardShowedSheet: Bool, find: ((AXNode) -> Bool) throws -> Control?) rethrows -> Control? {
        sawSpringBoardAlert = sawSpringBoardAlert || springBoardShowedSheet
        sawAppWindowSheet = sawAppWindowSheet || scope.showsSheet(in: tree)
        sawSheet = sawSheet || springBoardShowedSheet || scope.showsSheet(in: tree)
        var reached: [AXNode] = []
        let found = try find { node in
            reached.append(node)
            return scope.admits(node, in: tree)
        }
        if found == nil {
            passedOver.poll(reached, in: tree)
        }
        return found
    }
}

public extension SystemTapSearch {
    /// A `systemTap` that found nothing it could take.
    struct Refusal: Equatable, Sendable {
        /// What the screen's UNREACHABLE says.
        public let reason: String
        /// `.snapshotBlind` where the last poll that found a live match found the tree holding none of it (SimWalk#48), else `nil`.
        public let cause: ScreenOutcome.UnreachableCause?
    }
}
