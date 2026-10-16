//
// Copyright © Agulhas Labs
//

import Foundation

/// One walkbook screen present in both bundles: each side's outcome, the states paired by slug, and the states only one side holds.
public struct ScreenDiff: Codable, Equatable, Sendable {
    /// The walkbook screen id, which paired the two records.
    public var id: String
    /// The reference's verdict for the screen.
    public var referenceOutcome: ScreenOutcome
    /// The run's verdict for the screen.
    public var runOutcome: ScreenOutcome
    /// The states both sides captured, in the reference's capture order; empty when the screen is not compared.
    public var states: [StateDiff]
    /// The states one side captured and the other did not — reference-only first, each side in its capture order.
    public var unpairedStates: [UnpairedState]
    /// The layout shifts present on one side of a state both captured and absent on the other (SimWalk#67, M3); `nil` where no state had a shift record on both sides, so absent reads as "not compared", never "none".
    public var shiftFlags: [ShiftFlag]?
    /// The states whose shifts were not compared because only one side recorded them; `nil` when there are none.
    public var shiftNotes: [ShiftNote]?

    public init(
        id: String,
        referenceOutcome: ScreenOutcome,
        runOutcome: ScreenOutcome,
        states: [StateDiff],
        unpairedStates: [UnpairedState],
        shiftFlags: [ShiftFlag]? = nil,
        shiftNotes: [ShiftNote]? = nil
    ) {
        self.id = id
        self.referenceOutcome = referenceOutcome
        self.runOutcome = runOutcome
        self.states = states
        self.unpairedStates = unpairedStates
        self.shiftFlags = shiftFlags
        self.shiftNotes = shiftNotes
    }

    /// Whether both sides captured the screen, so its states were compared; a screen either side refused is reported with its outcomes and nothing else.
    public var isCompared: Bool {
        referenceOutcome.isCaptured && runOutcome.isCaptured
    }

    /// Every flag on every state of this screen that is a difference between the two bundles.
    public var flagCount: Int {
        states.reduce(0) { $0 + $1.flags.filter { !$0.isInherited }.count } + (shiftFlags?.count ?? 0)
    }

    /// Every flag on every state of this screen that the reference has too: reported, never counted as a difference.
    public var inheritedFlagCount: Int {
        states.reduce(0) { $0 + $1.flags.filter(\.isInherited).count }
    }
}

public extension ScreenDiff {
    /// A state one side captured and the other did not.
    struct UnpairedState: Codable, Equatable, Sendable {
        public var slug: String
        /// The side that holds it.
        public var side: BundleDiff.Side
        /// Its screenshot on that side, relative to that bundle.
        public var screenshotPath: String

        public init(slug: String, side: BundleDiff.Side, screenshotPath: String) {
            self.slug = slug
            self.side = side
            self.screenshotPath = screenshotPath
        }
    }

    /// A layout shift one side recorded on a state and the other did not (SimWalk#67, M3), matched by the element's type, identifier and label.
    ///
    /// **No screenshot crop**: a shift names an element rather than a section, and `bundle screen --match` finds the element in either bundle. Its figures are the side's own, kept so the line can say how far it moved and what displaced it; none of them was compared.
    struct ShiftFlag: Codable, Equatable, Sendable {
        /// The state's slug.
        public var slug: String
        /// The side that has the shift.
        public var side: BundleDiff.Side
        /// The shift as that side recorded it.
        public var shift: CaptureManifest.Motion.Shift

        public init(slug: String, side: BundleDiff.Side, shift: CaptureManifest.Motion.Shift) {
            self.slug = slug
            self.side = side
            self.shift = shift
        }
    }

    /// A state whose shifts were not compared, because one side's capture carries no shift record (motion off, or a bundle from before M2).
    struct ShiftNote: Codable, Equatable, Sendable {
        /// The state's slug.
        public var slug: String
        /// The side with no shift record.
        public var missingSide: BundleDiff.Side

        public init(slug: String, missingSide: BundleDiff.Side) {
            self.slug = slug
            self.missingSide = missingSide
        }
    }
}
