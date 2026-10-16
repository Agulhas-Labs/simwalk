//
// Copyright © Agulhas Labs
//

import Foundation

/// Two capture bundles compared for form: screens paired by walkbook id, states by slug, each pair of captures segmented and put to the form rules.
///
/// **Bundle against bundle** — a run against a run, or a capture against a reference frame that is itself a bundle. **Anything unpaired is named, never dropped**: a screen or a state on one side only, and a screen either side did not capture, are carried with what each side recorded, since a silent omission reads as "no difference". **Form, never value** (Brief §2.2): the rules read sections by key, box and text shape, and a different figure, date or row count than the reference is by definition not a flag. The differ says what is there; the model reading it is the adjudicator of what matters.
public struct BundleDiff: Codable, Equatable, Sendable {
    /// The build and plan the reference bundle records.
    public var reference: Build
    /// The build and plan the run bundle records.
    public var run: Build
    /// Every screen both bundles record, in the reference's walkbook order.
    public var screens: [ScreenDiff]
    /// Screens one bundle records and the other does not — reference-only first, each side in its walkbook order.
    public var unpairedScreens: [UnpairedScreen]

    public init(reference: Build, run: Build, screens: [ScreenDiff], unpairedScreens: [UnpairedScreen]) {
        self.reference = reference
        self.run = run
        self.screens = screens
        self.unpairedScreens = unpairedScreens
    }

    /// The rules a diff applies unless told otherwise, in the order their flags are listed.
    public static let standardRules: [any FormRule] = [PresenceRule(), OrderRule(), BoxRule(), RowTemplateRule(), OverlapRule(), DegenerateChartRule()]

    /// Compares `run` against `reference`.
    ///
    /// Reads each paired capture's tree from its bundle; a tree that cannot be read is recorded on its state as unreadable rather than thrown, so one bad artefact costs the state it belongs to and no more.
    public static func compare(
        run: CaptureBundle,
        against reference: CaptureBundle,
        segmenter: any Segmenter = AXSegmenter(),
        rules: [any FormRule] = BundleDiff.standardRules
    ) -> BundleDiff {
        let referenceScreens = reference.manifest.screens
        let runScreens = run.manifest.screens
        let referenceIDs = Set(referenceScreens.map(\.id))
        let runIDs = Set(runScreens.map(\.id))
        let screens = referenceScreens.compactMap { referenceScreen -> ScreenDiff? in
            guard let runScreen = runScreens.first(where: { $0.id == referenceScreen.id }) else { return nil }
            let sides = Sides(reference: reference, run: run, segmenter: segmenter, rules: rules)
            return sides.screenDiff(reference: referenceScreen, run: runScreen)
        }
        let unpaired = referenceScreens.filter { !runIDs.contains($0.id) }.map { UnpairedScreen(id: $0.id, side: .reference) }
            + runScreens.filter { !referenceIDs.contains($0.id) }.map { UnpairedScreen(id: $0.id, side: .run) }
        return BundleDiff(reference: Build(reference.manifest), run: Build(run.manifest), screens: screens, unpairedScreens: unpaired)
    }

    /// Every flag on every screen that is a difference between the two bundles: one the reference does not have.
    public var flagCount: Int {
        screens.reduce(0) { $0 + $1.flagCount }
    }

    /// Every flag on every screen that the reference has too (`also in reference`): still printed, never counted, so a bundle against itself has none to count.
    public var inheritedFlagCount: Int {
        screens.reduce(0) { $0 + $1.inheritedFlagCount }
    }
}

public extension BundleDiff {
    /// Which of the two bundles something is on.
    enum Side: String, Codable, Sendable {
        case reference
        case run
    }

    /// The identity a bundle's manifest records for what was walked.
    struct Build: Codable, Equatable, Sendable {
        public var walkName: String
        public var appBundleID: String
        public var appBuildHash: String
        public var walkbookHash: String
        /// How the build hash was known; `nil` means read back from the installed app.
        public var appBuildProvenance: CaptureManifest.AppBuildProvenance?

        public init(walkName: String, appBundleID: String, appBuildHash: String, walkbookHash: String, appBuildProvenance: CaptureManifest.AppBuildProvenance? = nil) {
            self.walkName = walkName
            self.appBundleID = appBundleID
            self.appBuildHash = appBuildHash
            self.walkbookHash = walkbookHash
            self.appBuildProvenance = appBuildProvenance
        }

        public init(_ manifest: CaptureManifest) {
            self.init(walkName: manifest.walkName, appBundleID: manifest.appBundleID, appBuildHash: manifest.appBuildHash, walkbookHash: manifest.walkbookHash, appBuildProvenance: manifest.appBuildProvenance)
        }

        /// Whether `other` is the same build of the same app; two builds a device walk could not read are not known to be, and an installed hash counts.
        public func isSameBuild(as other: Build) -> Bool {
            appBundleID == other.appBundleID && appBuildHash == other.appBuildHash && appBuildHash != AppBuildIdentity.unreadOnDevice
        }
    }

    /// A screen one bundle records and the other does not.
    struct UnpairedScreen: Codable, Equatable, Sendable {
        public var id: String
        /// The side that records it.
        public var side: Side

        public init(id: String, side: Side) {
            self.id = id
            self.side = side
        }
    }
}

extension BundleDiff {
    /// The two bundles and what to compare them with, for pairing one screen at a time.
    struct Sides {
        let reference: CaptureBundle
        let run: CaptureBundle
        let segmenter: any Segmenter
        let rules: [any FormRule]

        /// One paired screen: its states compared when both sides captured it, its outcomes alone when either did not.
        func screenDiff(reference referenceScreen: CaptureManifest.ScreenRecord, run runScreen: CaptureManifest.ScreenRecord) -> ScreenDiff {
            guard referenceScreen.outcome.isCaptured, runScreen.outcome.isCaptured else {
                return ScreenDiff(id: referenceScreen.id, referenceOutcome: referenceScreen.outcome, runOutcome: runScreen.outcome, states: [], unpairedStates: [])
            }
            let referenceSlugs = Set(referenceScreen.captures.map(\.state.slug))
            let runSlugs = Set(runScreen.captures.map(\.state.slug))
            var shifts = ShiftDiff()
            let states = referenceScreen.captures.compactMap { referenceCapture -> StateDiff? in
                guard let runCapture = runScreen.captures.first(where: { $0.state.slug == referenceCapture.state.slug }) else { return nil }
                let compared = ShiftDiff.compare(slug: referenceCapture.state.slug, reference: referenceCapture.motion, run: runCapture.motion)
                shifts.flags += compared.flags
                shifts.notes += compared.notes
                shifts.compared = shifts.compared || compared.compared
                return stateDiff(reference: referenceCapture, run: runCapture, referenceScrolled: referenceScreen.scrolls, runScrolled: runScreen.scrolls)
            }
            let unpaired = referenceScreen.captures.filter { !runSlugs.contains($0.state.slug) }
                .map { ScreenDiff.UnpairedState(slug: $0.state.slug, side: .reference, screenshotPath: $0.screenshotPath) }
                + runScreen.captures.filter { !referenceSlugs.contains($0.state.slug) }
                .map { ScreenDiff.UnpairedState(slug: $0.state.slug, side: .run, screenshotPath: $0.screenshotPath) }
            return ScreenDiff(
                id: referenceScreen.id,
                referenceOutcome: referenceScreen.outcome,
                runOutcome: runScreen.outcome,
                states: states,
                unpairedStates: unpaired,
                shiftFlags: shifts.compared ? shifts.flags : nil,
                shiftNotes: shifts.notes.isEmpty ? nil : shifts.notes
            )
        }

        /// One paired state: both captures segmented and put to every rule, or the side whose tree could not be read named.
        func stateDiff(
            reference referenceCapture: CaptureManifest.StateCapture,
            run runCapture: CaptureManifest.StateCapture,
            referenceScrolled: Bool = false,
            runScrolled: Bool = false
        ) -> StateDiff {
            let referenceSide = segmented(referenceCapture, in: reference, scrolled: referenceScrolled)
            let runSide = segmented(runCapture, in: run, scrolled: runScrolled)
            guard case let .success(referenceSegmented) = referenceSide.capture, case let .success(runSegmented) = runSide.capture else {
                return StateDiff(slug: referenceCapture.state.slug, reference: referenceSide.segmentation, run: runSide.segmentation, flags: [])
            }
            let flags = rules.flatMap { $0.flags(reference: referenceSegmented, run: runSegmented) }
            return StateDiff(slug: referenceCapture.state.slug, reference: referenceSide.segmentation, run: runSide.segmentation, flags: flags)
        }

        /// One capture's tree, segmented — or the reason it could not be read.
        func segmented(_ capture: CaptureManifest.StateCapture, in bundle: CaptureBundle, scrolled: Bool = false) -> (capture: Result<SegmentedCapture, Error>, segmentation: StateDiff.Segmentation) {
            do {
                let segmentedCapture = try SegmentedCapture(tree: bundle.axTree(for: capture), screenshotPath: capture.screenshotPath, segmenter: segmenter, scrolled: scrolled)
                return (.success(segmentedCapture), StateDiff.Segmentation(screenshotPath: capture.screenshotPath, sectionCount: segmentedCapture.sections.count))
            } catch {
                return (.failure(error), StateDiff.Segmentation(screenshotPath: capture.screenshotPath, sectionCount: 0, unreadable: String(describing: error)))
            }
        }
    }
}

private extension CaptureManifest.ScreenRecord {
    /// Whether the route the runner completed scrolled to a label.
    var scrolls: Bool {
        routeTaken.contains { step in
            if case .scrollTo = step {
                true
            } else {
                false
            }
        }
    }
}
