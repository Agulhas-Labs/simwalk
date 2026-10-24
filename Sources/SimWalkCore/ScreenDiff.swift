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
    /// The Apple accessibility-audit issues the run has and the reference lacks (E1b), by identity and never frame; `nil` where no state was audited on both sides, so absent reads as "not compared", never "none".
    public var appleFlags: [AppleFlag]?
    /// The states whose audits were not compared, with the side and why; `nil` when there are none.
    public var appleNotes: [AppleNote]?

    public init(
        id: String,
        referenceOutcome: ScreenOutcome,
        runOutcome: ScreenOutcome,
        states: [StateDiff],
        unpairedStates: [UnpairedState],
        shiftFlags: [ShiftFlag]? = nil,
        shiftNotes: [ShiftNote]? = nil,
        appleFlags: [AppleFlag]? = nil,
        appleNotes: [AppleNote]? = nil
    ) {
        self.id = id
        self.referenceOutcome = referenceOutcome
        self.runOutcome = runOutcome
        self.states = states
        self.unpairedStates = unpairedStates
        self.shiftFlags = shiftFlags
        self.shiftNotes = shiftNotes
        self.appleFlags = appleFlags
        self.appleNotes = appleNotes
    }

    /// Whether both sides captured the screen, so its states were compared; a screen either side refused is reported with its outcomes and nothing else.
    public var isCompared: Bool {
        referenceOutcome.isCaptured && runOutcome.isCaptured
    }

    /// Every flag on every state of this screen that is a difference between the two bundles.
    public var flagCount: Int {
        states.reduce(0) { $0 + $1.flags.filter { !$0.isInherited }.count } + (shiftFlags?.count ?? 0) + (appleFlags?.count ?? 0)
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

    /// An Apple accessibility-audit issue the run has and the reference lacks (E1b), matched by type, element and Apple's description, never by frame.
    ///
    /// **No screenshot crop**: the record's frame is read after the audit, which can scroll, so it need not line up with the state's screenshot.
    struct AppleFlag: Codable, Equatable, Sendable {
        /// The state's slug.
        public var slug: String
        /// The `bundle audit` rule that reads the issue's type, else the raw type.
        public var rule: String
        /// The element's type by the tree's name; `nil` for an issue with no element.
        public var elementType: String?
        /// The element's identifier, else its label; `nil` where it has neither.
        public var name: String?
        /// Apple's one-line description of the issue.
        public var compactDescription: String
        /// Why the element could not be read after the audit, when that is why there is none.
        public var elementUnreadable: String?
        /// Whether the issue's record says each element was read after the audit.
        public var elementsRead: Bool?

        public init(slug: String, rule: String, elementType: String?, name: String?, compactDescription: String, elementUnreadable: String? = nil, elementsRead: Bool? = nil) {
            self.slug = slug
            self.rule = rule
            self.elementType = elementType
            self.name = name
            self.compactDescription = compactDescription
            self.elementUnreadable = elementUnreadable
            self.elementsRead = elementsRead
        }

        init(slug: String, issue: AppleAuditRecord.Issue, elementsRead: Bool) {
            self.init(
                slug: slug,
                rule: AuditRuleName.allCases.first { $0.appleIssueType == issue.type }?.rawValue ?? issue.type,
                elementType: issue.element?.type,
                name: AppleAuditIdentity.name(of: issue.element),
                compactDescription: issue.compactDescription,
                elementUnreadable: issue.elementUnreadable,
                elementsRead: elementsRead ? true : nil
            )
        }
    }

    /// A state whose Apple audits were not compared, because one side's capture has no readable record (E1b).
    struct AppleNote: Codable, Equatable, Sendable {
        /// The state's slug.
        public var slug: String
        /// The side whose audit could not be read.
        public var side: BundleDiff.Side
        public var reason: Reason

        public init(slug: String, side: BundleDiff.Side, reason: Reason) {
            self.slug = slug
            self.side = side
            self.reason = reason
        }
    }
}

public extension ScreenDiff.AppleNote {
    /// Why a side's audit cannot be read as evidence.
    enum Reason: String, Codable, Sendable {
        case notAudited
        case failed
        case unreadable
    }
}
