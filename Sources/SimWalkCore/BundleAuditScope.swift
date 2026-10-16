//
// Copyright © Agulhas Labs
//

import Foundation

/// What every rule of `bundle audit` reads a bundle through: the captures it may file under a screen's id, and the account of which screens those do not cover.
///
/// Extracted from `DisclosureAffordanceAudit` when `bundle audit` gained more rules, because the reading and the coverage are properties of the bundle and not of a rule — a second rule that re-derived which screens are readable would be a second opinion on it, and the rules would come to disagree about what "audited 11 of 11" means.
public struct BundleAuditScope {
    private let bundle: CaptureBundle

    public init(_ bundle: CaptureBundle) {
        self.bundle = bundle
    }

    /// Every capture the audit may read, in screen then state order.
    ///
    /// **Skips a screen recorded as `unexpectedScreen` (round 2).** Its captures are real files on disk, but they are of whatever screen the walk actually reached — filing their contents under the screen id the walkbook asked for would attribute another screen's shapes to this one, which is exactly the wrong attribution `coverage()` exists to prevent. `coverage()` names these screens rather than silently dropping them.
    public func captures() throws -> [Capture] {
        var found: [Capture] = []
        for screen in bundle.manifest.screens where !Self.isWrongScreen(screen) {
            for capture in screen.captures {
                try found.append(Capture(screenID: screen.id, stateSlug: capture.state.slug, tree: bundle.axTree(for: capture)))
            }
        }
        return found
    }

    /// Which of the walk's screens an audit could actually read, and which it could not.
    public func coverage() -> Coverage {
        var read: [String] = []
        var notRead: [String] = []
        var partial: [String] = []
        var wrongScreen: [String] = []
        for screen in bundle.manifest.screens {
            if Self.isWrongScreen(screen) {
                // Captured, but not of this screen — neither "read" (its rows would be filed under the
                // wrong id) nor "not read" (the walk did reach and record something here); its own
                // category, so the coverage line can say what actually happened rather than picking the
                // nearer-sounding wrong answer.
                wrongScreen.append(screen.id)
            } else if screen.captures.isEmpty {
                notRead.append(screen.id)
            } else {
                read.append(screen.id)
                // A screen may hold some of its states and have failed on another; the states it does
                // hold are real evidence, and the ones it does not are still unaudited.
                if !screen.outcome.isCaptured {
                    partial.append(screen.id)
                }
            }
        }
        // Whether a capture is evidence and whether it was recorded mid-motion are different questions,
        // and the audit reads rows out of trees: a capture taken while the hierarchy was still populating
        // may hold rows that no longer exist, or be missing rows that arrived a frame later. Read from
        // the manifest's one generator rather than re-derived, so the audit, the walk's exit code and
        // the summary all count the same captures — narrowed to the captures `rows()` actually read, since
        // a wrong screen's are skipped and a caveat about rows the audit never took is about nothing.
        return Coverage(
            screensRead: read,
            screensNotRead: notRead,
            screensPartlyRead: partial,
            screensWrongScreen: wrongScreen,
            unsettledCaptures: bundle.manifest.unsettledCaptures.filter { !wrongScreen.contains($0.screenID) }
        )
    }

    /// Whether a screen's captures are of a different screen than its walkbook expected — evidence that exists but must not be filed under this screen's id.
    private static func isWrongScreen(_ screen: CaptureManifest.ScreenRecord) -> Bool {
        if case .unexpectedScreen = screen.outcome {
            return true
        }
        return false
    }
}

public extension BundleAuditScope {
    /// One readable capture: where it came from and the tree it recorded.
    struct Capture: Sendable {
        public let screenID: String
        public let stateSlug: String
        public let tree: AXNode

        public init(screenID: String, stateSlug: String, tree: AXNode) {
            self.screenID = screenID
            self.stateSlug = stateSlug
            self.tree = tree
        }
    }

    /// What the audit was able to look at.
    ///
    /// A verdict over a subset of a walk is a verdict about that subset, and saying so is the difference between "this bundle is clean" and "the part of this bundle that exists is clean".
    struct Coverage: Equatable, Sendable {
        /// Screens holding at least one capture — the ones the audit read.
        public let screensRead: [String]
        /// Screens holding no captures at all: unreachable, build-mismatched, or failed before writing anything.
        public let screensNotRead: [String]
        /// Screens that were read and whose own outcome says they are incomplete — some states present, others never captured.
        public let screensPartlyRead: [String]
        /// Screens recorded as `unexpectedScreen` — captured, but of a different screen than the walkbook expected, so their captures are excluded from `rows()` rather than filed under the wrong id (round 2).
        public let screensWrongScreen: [String]
        /// Captures the audit read whose accessibility tree had not stopped changing when they were taken.
        ///
        /// Coverage is about what the verdict rests on, and a capture recorded mid-motion is evidence of a screen that was still assembling itself — rows it holds may have gone, rows it lacks may have arrived a frame later. A screen present only in such a capture used to count as fully audited, so eleven half-caught screens rendered "audited 11 of 11 screens — no disclosure rows found" and exited 0.
        public let unsettledCaptures: [CaptureManifest.CaptureReference]

        public init(
            screensRead: [String],
            screensNotRead: [String],
            screensPartlyRead: [String] = [],
            screensWrongScreen: [String] = [],
            unsettledCaptures: [CaptureManifest.CaptureReference] = []
        ) {
            self.screensRead = screensRead
            self.screensNotRead = screensNotRead
            self.screensPartlyRead = screensPartlyRead
            self.screensWrongScreen = screensWrongScreen
            self.unsettledCaptures = unsettledCaptures
        }

        /// Every screen the walk was asked for.
        public var screensInWalk: Int {
            screensRead.count + screensNotRead.count + screensWrongScreen.count
        }

        /// Whether the audit saw everything the walk set out to capture, and saw it still.
        ///
        /// An unsettled capture disqualifies the verdict for the same reason a missing one does: it is the difference between "this bundle is clean" and "the part of this bundle that was standing still is clean". It is what moves `bundle audit` to exit 2, which is the honest answer for a check whose evidence was recorded mid-motion. A screen that captured the wrong one disqualifies it too — this verdict says nothing about the screen the walkbook actually named.
        public var isComplete: Bool {
            screensNotRead.isEmpty && screensPartlyRead.isEmpty && screensWrongScreen.isEmpty && unsettledCaptures.isEmpty
        }
    }
}
