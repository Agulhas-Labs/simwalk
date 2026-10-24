//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// `BundleDiff` over bundles written from captures of `Fixtures/SegmenterFixture` (how each was made: `Fixtures/SegmenterFixture/README.md`): pairing, what is named rather than dropped, and the two gates the differ's law sets — a bundle against itself, and two runs a day apart.
struct BundleDiffTests {
    /// G3: a bundle diffed against itself has no difference, only the one defect it carries — the passage detail's degenerate Boat speed chart, flagged on both sides at once and so reported apart (#74), compares every screen and state, and says the diff measures the walk's own nondeterminism.
    @Test
    func aBundleAgainstItselfHasOnlyItsOwnDegenerateChartFlag() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.walk(in: directory, screens: [
            ("summary", [("segmenter-summary-light", Self.light), ("segmenter-summary-dark-axl", Self.darkLarge)]),
            ("passages", [("segmenter-passages-later-week", Self.light)]),
            ("passage-detail", [("segmenter-passage-detail", Self.light)]),
        ])

        let diff = BundleDiff.compare(run: bundle, against: bundle)
        let states = diff.screens.flatMap(\.states)
        let everyStateCompared = states.allSatisfy(\.isCompared)

        #expect(diff.flagCount == 0)
        #expect(diff.inheritedFlagCount == 1)
        #expect(diff.screens.last?.states.first?.flags.map(\.rule) == ["degenerate chart"])
        #expect(diff.unpairedScreens.isEmpty)
        #expect(diff.screens.map(\.id) == ["summary", "passages", "passage-detail"])
        #expect(everyStateCompared)
        #expect(states.count == 4)
    }

    /// G4: Passages in two weeks — another week's dates, other figures, three passages against four and two boats against three — raises no flag.
    @Test
    func twoRunsDifferingOnlyInValuesHaveNoFlag() throws {
        let (referenceDirectory, runDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let reference = try Self.walk(in: referenceDirectory, screens: [("passages", [("segmenter-passages-first-week", Self.light)])])
        let run = try Self.walk(in: runDirectory, screens: [("passages", [("segmenter-passages-later-week", Self.light)])])

        let diff = BundleDiff.compare(run: run, against: reference)

        #expect(diff.screens.first?.states.first?.isCompared == true)
        #expect(diff.flagCount == 0)
    }

    /// Screens pair by id and states by slug; what one side holds alone is named on its side, a screen either side refused is reported with both outcomes and not compared, and the builds are carried.
    @Test
    func whatIsUnpairedOrRefusedIsNamed() throws {
        let (referenceDirectory, runDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let reference = try Self.walk(in: referenceDirectory, screens: [
            ("summary", [("segmenter-summary-light", Self.light), ("segmenter-summary-dark-axl", Self.darkLarge)]),
            ("gone", [("segmenter-passage-detail", Self.light)]),
            ("passages", [("segmenter-passages-first-week", Self.light)]),
        ], buildHash: "a1b2c3d4")
        let run = try CaptureBundleFixture.writeWalk(in: runDirectory, screens: [
            Self.screen("summary", [("segmenter-summary-light", Self.light)]),
            CaptureBundleFixture.ScreenSpec(id: "passages", outcome: .unreachable(routeTried: [.tab(label: "Passages")]), routeTaken: []),
            Self.screen("new", [("segmenter-passage-detail", Self.light)]),
        ], buildHash: "e5f6a7b8")

        let diff = BundleDiff.compare(run: run, against: reference)
        let passages = try #require(diff.screens.first { $0.id == "passages" })

        #expect(diff.reference.appBuildHash == "a1b2c3d4")
        #expect(diff.run.appBuildHash == "e5f6a7b8")
        #expect(diff.unpairedScreens == [BundleDiff.UnpairedScreen(id: "gone", side: .reference), BundleDiff.UnpairedScreen(id: "new", side: .run)])
        #expect(diff.screens.first?.unpairedStates.map(\.slug) == [Self.darkLarge.slug])
        #expect(diff.screens.first?.unpairedStates.map(\.side) == [.reference])
        #expect(!passages.isCompared)
        #expect(passages.states.isEmpty)
        #expect(passages.runOutcome == .unreachable(routeTried: [.tab(label: "Passages")]))
    }

    /// The rendering names every flag with its crop under its state, what is unpaired or not compared, and the clean screens on one line — and no `toolbar` presence flag for the full-screen `Toolbar` iOS 27 adds to the run's tree and not the reference's (SimWalk#131); the result survives a JSON round trip unchanged.
    @Test
    func theRenderingIsCompactAndTheResultCodable() throws {
        let (referenceDirectory, runDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let reference = try Self.walk(in: referenceDirectory, screens: [
            ("summary", [("segmenter-summary-light", Self.light)]),
            ("passages", [("segmenter-passages-later-week", Self.light)]),
        ])
        let run = try Self.walk(in: runDirectory, screens: [
            ("summary", [("segmenter-passages-first-week", Self.light)]),
            ("passages", [("segmenter-passages-first-week", Self.light)]),
        ])

        let diff = BundleDiff.compare(run: run, against: reference)
        let lines = BundleDiffRendering.lines(of: diff)
        let decoded = try JSONDecoder().decode(BundleDiff.self, from: JSONEncoder().encode(diff))

        #expect(decoded == diff)
        #expect(lines.first == "bundle diff: run walk build a1b2c3d4 against reference walk build a1b2c3d4")
        #expect(lines.contains("summary/light: 8 flags · screens/summary/light/screen.png"))
        #expect(lines.contains("  row template  untitled  run only: Time under sail | {n} – {n} July (leading, trailing) · run @22,78 343×161"))
        #expect(lines.contains("  presence  Underway  reference only · list — may be data-driven · ref @14,173 374×81"))
        #expect(lines.contains("  presence  Too few passages yet  run only · run @22,981 358×106 not in screenshot"))
        #expect(!lines.contains { $0.hasPrefix("  presence  toolbar") })
        #expect(lines.last == "no form difference: passages")
        #expect(lines.count == 13)
    }

    /// The header states the facts — same or different build, same or changed walkbook — and asserts no cause for a flag.
    @Test
    func theHeaderStatesFactsAndNoCause() {
        let build = BundleDiff.Build(walkName: "walk", appBundleID: "app", appBuildHash: "a1b2c3d4", walkbookHash: "w1")
        var other = build
        other.appBuildHash = "e5f6a7b8"
        other.walkbookHash = "w2"

        let same = BundleDiffRendering.identityLines(BundleDiff(reference: build, run: build, screens: [], unpairedScreens: []))
        let different = BundleDiffRendering.identityLines(BundleDiff(reference: build, run: other, screens: [], unpairedScreens: []))

        #expect(same[1] == "build same · walkbook same")
        #expect(different[1] == "build different · walkbook changed w1 → w2")
        #expect((same + different).allSatisfy { !$0.contains("nondeterminism") })
    }

    /// A device walk cannot read the installed build: two such bundles are not the same build, and the header says the build is unread rather than cutting the placeholder to eight characters.
    @Test
    func twoUnreadDeviceBuildsAreNotTheSameBuild() {
        let unread = BundleDiff.Build(walkName: "walk", appBundleID: "app", appBuildHash: AppBuildIdentity.unreadOnDevice, walkbookHash: "w1")
        var known = unread
        known.appBuildHash = "a1b2c3d4"

        let both = BundleDiffRendering.identityLines(BundleDiff(reference: unread, run: unread, screens: [], unpairedScreens: []))
        let one = BundleDiffRendering.identityLines(BundleDiff(reference: known, run: unread, screens: [], unpairedScreens: []))

        #expect(!unread.isSameBuild(as: unread))
        #expect(both[1] == "build unread · walkbook same")
        #expect(one[1] == "build unread · walkbook same")
        #expect(both[0] == "bundle diff: run walk build unread (device) against reference walk build unread (device)")
    }

    /// An installed hash was taken on the Mac, so it counts: two bundles with the same one are the same build, and the header says how it was known.
    @Test
    func twoBundlesWithTheSameInstalledHashAreTheSameBuild() {
        let installed = BundleDiff.Build(walkName: "walk", appBundleID: "app", appBuildHash: "a1b2c3d4", walkbookHash: "w1", appBuildProvenance: .installed)
        var other = installed
        other.appBuildHash = "e5f6a7b8"
        var readBack = installed
        readBack.appBuildProvenance = nil

        let same = BundleDiffRendering.identityLines(BundleDiff(reference: installed, run: installed, screens: [], unpairedScreens: []))
        let mixed = BundleDiffRendering.identityLines(BundleDiff(reference: readBack, run: installed, screens: [], unpairedScreens: []))
        let different = BundleDiffRendering.identityLines(BundleDiff(reference: installed, run: other, screens: [], unpairedScreens: []))

        #expect(installed.isSameBuild(as: installed))
        #expect(same[1] == "build same (installed, not read back) · walkbook same")
        #expect(mixed[1] == "build same (installed, not read back) · walkbook same")
        #expect(!installed.isSameBuild(as: other))
        #expect(different[1] == "build different · walkbook same")
    }

    /// The answer states the compared tally once, and a state whose tree could not be read is not counted in it.
    @Test
    func theTallyIsOnceAndLeavesOutUnreadableStates() throws {
        let build = BundleDiff.Build(walkName: "walk", appBundleID: "app", appBuildHash: "a1b2c3d4", walkbookHash: "w")
        let readable = StateDiff.Segmentation(screenshotPath: "a.png", sectionCount: 1)
        let unreadable = StateDiff.Segmentation(screenshotPath: "b.png", sectionCount: 0, unreadable: "broken")
        let screen = ScreenDiff(id: "s", referenceOutcome: .captured, runOutcome: .captured, states: [
            StateDiff(slug: "light", reference: readable, run: readable, flags: []),
            StateDiff(slug: "dark", reference: readable, run: unreadable, flags: []),
        ], unpairedStates: [])
        let diff = BundleDiff(reference: build, run: build, screens: [screen], unpairedScreens: [])
        let directory = try TemporaryDirectory()
        let bundle = try Self.walk(in: directory, screens: [("summary", [("segmenter-summary-light", Self.light)])])

        let text = BundleDiffSummary(diff, reference: bundle, run: bundle).answer().text

        #expect(BundleDiffRendering.comparedTally(diff) == "1 screen compared, 1 state")
        #expect(text.components(separatedBy: "1 screen compared").count == 2)
        #expect(text.contains("1 state not compared for an unreadable tree"))
    }

    /// SimWalk#107: a bundle read through the added `.simwalk` suffix is named on the diff's first line, by role; with neither resolved the line is unchanged.
    @Test
    func aBundleReadThroughTheAddedSuffixIsNamedOnTheFirstLineByRole() throws {
        let directory = try TemporaryDirectory()
        let written = try Self.walk(in: directory, screens: [("summary", [("segmenter-summary-light", Self.light)])])
        let diff = BundleDiff.compare(run: written, against: written)
        let viaSuffix = try CaptureBundle.read(at: written.url.deletingPathExtension())
        let note = try #require(viaSuffix.pathNote)

        let first = { (run: CaptureBundle, reference: CaptureBundle) in
            BundleDiffSummary(diff, reference: reference, run: run).answer().text.components(separatedBy: "\n").first { $0.hasPrefix("bundle diff:") } ?? ""
        }
        let plain = first(written, written)

        #expect(first(viaSuffix, written) == "\(plain)  run \(note)")
        #expect(first(written, viaSuffix) == "\(plain)  reference \(note)")
        #expect(first(viaSuffix, viaSuffix) == "\(plain)  run \(note)  reference \(note)")
        #expect(!plain.contains("suffix added"))
    }

    /// The negative gate for the box rule (Brief §2.2): a longer figure that widens its card is no flag.
    ///
    /// The passage detail with its lead paragraph reading a figure of the same shape — `118.2 nm in 112:10` — and drawn 37 pt wider, which moves the lead card's edge with it. A value, so no flag beyond the Boat speed chart the tree already carries.
    @Test
    func aLongerFigureThatWidensItsCardIsNoFlag() throws {
        let (referenceDirectory, runDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
        let tree = try Self.tree("segmenter-passage-detail")
        let widened = Self.replacing(in: tree, label: "Coastal passage — 8.2 nm in 2:10.") { node in
            node.label = "Coastal passage — 118.2 nm in 112:10."
            node.frame.width = 348
        }
        let reference = try Self.walk(in: referenceDirectory, trees: [("passage-detail", tree)])
        let run = try Self.walk(in: runDirectory, trees: [("passage-detail", widened)])

        let diff = BundleDiff.compare(run: run, against: reference)
        let leadCard = { (tree: AXNode) in AXSegmenter().sections(of: tree).first { $0.key == "Coastal passage" }?.frame.width }

        #expect(leadCard(tree)?.rounded() == 311)
        #expect(leadCard(widened) == 348)
        #expect(diff.screens.first?.states.first?.flags.map(\.rule) == ["degenerate chart"])
    }

    static let light = Walkbook.CaptureState(theme: .light)
    static let darkLarge = Walkbook.CaptureState(theme: .dark, dynamicTypeSize: "UICTContentSizeCategoryAccessibilityL")

    /// The whole diff on a screen reached by a `scrollTo` or a `swipe`: every section on the run side shifted down 40 pt is no flag, and on a screen reached by a tap it is a box flag on the first section's top.
    @Test
    func aScrolledScreenIsNotFlaggedForWhereTheScrollLeftIt() throws {
        let tree = try Self.tree("segmenter-summary-light")
        let shifted = Self.shifted(tree, by: 40)
        func diff(route: [Walkbook.RouteStep]) throws -> BundleDiff {
            let (referenceDirectory, runDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
            func walk(_ directory: TemporaryDirectory, _ tree: AXNode) throws -> CaptureBundle {
                try CaptureBundleFixture.writeWalk(in: directory, screens: [
                    CaptureBundleFixture.ScreenSpec(id: "summary", routeTaken: route, captures: [CaptureBundleFixture.Capture(screenID: "summary", state: Self.light, tree: tree)]),
                ], buildHash: "a1b2c3d4")
            }
            return try BundleDiff.compare(run: walk(runDirectory, shifted), against: walk(referenceDirectory, tree))
        }

        let scrolled = try diff(route: [.tab(label: "Log"), .scrollTo(label: "Underway")])
        let swiped = try diff(route: [.tab(label: "Log"), .swipe(label: nil, direction: "up")])
        let tapped = try diff(route: [.tab(label: "Log")])

        #expect(scrolled.flagCount == 0)
        #expect(swiped.flagCount == 0)
        #expect(tapped.screens.first?.states.first?.flags.map(\.rule) == ["box"])
    }

    /// `node` with every element of the scrolling content (from the first row of controls down, above the tab bar) moved down `distance`.
    static func shifted(_ node: AXNode, by distance: Double) -> AXNode {
        var copy = node
        if copy.frame.y >= 62, copy.frame.y < 791 {
            copy.frame.y += distance
        }
        copy.children = copy.children.map { shifted($0, by: distance) }
        return copy
    }

    /// A walk of `screens`, each state's tree read from the named fixture.
    static func walk(in directory: TemporaryDirectory, screens: [(id: String, states: [(fixture: String, state: Walkbook.CaptureState)])], buildHash: String = "a1b2c3d4") throws -> CaptureBundle {
        try CaptureBundleFixture.writeWalk(in: directory, screens: screens.map { try screen($0.id, $0.states) }, buildHash: buildHash)
    }

    /// A walk of one light capture per screen, each of the given tree.
    static func walk(in directory: TemporaryDirectory, trees: [(id: String, tree: AXNode)]) throws -> CaptureBundle {
        try CaptureBundleFixture.writeWalk(in: directory, screens: trees.map { id, tree in
            CaptureBundleFixture.ScreenSpec(id: id, captures: [CaptureBundleFixture.Capture(screenID: id, state: light, tree: tree)])
        }, buildHash: "a1b2c3d4")
    }

    /// `node` with `change` made to every element labelled `label`.
    static func replacing(in node: AXNode, label: String, with change: (inout AXNode) -> Void) -> AXNode {
        var copy = node
        if copy.label == label {
            change(&copy)
        }
        copy.children = copy.children.map { replacing(in: $0, label: label, with: change) }
        return copy
    }

    static func screen(_ id: String, _ states: [(fixture: String, state: Walkbook.CaptureState)]) throws -> CaptureBundleFixture.ScreenSpec {
        try CaptureBundleFixture.ScreenSpec(id: id, captures: states.map { fixture, state in
            try CaptureBundleFixture.Capture(screenID: id, state: state, tree: tree(fixture))
        })
    }

    static func tree(_ fixture: String, sourceLocation: SourceLocation = #_sourceLocation) throws -> AXNode {
        let url = try #require(Bundle.module.url(forResource: fixture, withExtension: "json", subdirectory: "Fixtures"), sourceLocation: sourceLocation)
        return try JSONDecoder().decode(AXNode.self, from: Data(contentsOf: url))
    }
}
