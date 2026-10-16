//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// `bundle screen`'s core: how a step, a state and a capture are resolved, the screen's identifier, and the pricing against the one capture it reads rather than the bundle (SimWalk#20).
///
/// The text listing itself is `BundleScreenTextTests`.
struct BundleScreenQueryTests {
    /// The happy path: a step resolves to the screen `bundle inspect` would list at that position, and its labelled text comes back in accessibility order.
    @Test
    func arootIdentifierAndTextInAccessibilityOrderAnswerForOneScreen() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "today", captures: [
                CaptureBundleFixture.Capture(screenID: "today", state: Walkbook.CaptureState(theme: .light), tree: Self.tree(identifier: "TodayScreen", labels: [("StaticText", "Today")])),
            ]),
            CaptureBundleFixture.ScreenSpec(id: "sleep-detail", captures: [
                CaptureBundleFixture.Capture(screenID: "sleep-detail", state: Walkbook.CaptureState(theme: .light), tree: Self.sleepTree),
            ]),
        ])

        let answer = try BundleScreenQuery(bundle).answer(step: "2")

        #expect(answer.text.contains("ok — step 2 'sleep-detail' [light] — root 'SleepDetailScreen', 9 text elements on screen"))
        let sleepIndex = try #require(answer.text.range(of: "Sleep · StaticText ·"))
        let nothingIndex = try #require(answer.text.range(of: "Nothing earlier to compare with · StaticText ·"))
        let cyclingIndex = try #require(answer.text.range(of: "Cycling Distance"))
        #expect(sleepIndex.lowerBound < nothingIndex.lowerBound)
        #expect(nothingIndex.lowerBound < cyclingIndex.lowerBound)
        // The app's own display name sits on the root every real capture roots at — it is chrome, not
        // text on the screen, so it never appears among the text elements (SimWalk#20 round 2).
        #expect(!answer.text.contains("RouteFixture"))
    }

    /// A label, type and frame repeated on two different tree nodes is one element on screen, not two.
    ///
    /// A container mirroring its own child's text at the child's own geometry says nothing new, and the same label at a different frame (a tab labelled the same as a heading) is not touched.
    @Test
    func repeatedLabelTypeAndFrameCollapseToOneElement() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "sleep-detail", captures: [
                CaptureBundleFixture.Capture(screenID: "sleep-detail", state: Walkbook.CaptureState(theme: .light), tree: Self.sleepTree),
            ]),
        ])

        let answer = try BundleScreenQuery(bundle).answer(step: "1")

        // Two "Sleep" StaticText nodes at the same frame plus one "Sleep" Button at a different frame:
        // the pair collapses, the button does not — four of the screen's own, and the tab bar's five.
        #expect(answer.text.contains(", 9 text elements on screen"))
        let occurrences = answer.text.components(separatedBy: "Sleep · StaticText ·").count - 1
        #expect(occurrences == 1)
        #expect(answer.text.contains("Sleep · Button ·"))
    }

    /// A navigation bar's identifier is found and reported as the screen's root when nothing else on the screen carries one — the real shape a Heart detail screen took in review (SimWalk#20 round 2, finding 1).
    ///
    /// The bar is the fallback, not chrome to skip: its identifier is the screen's title, and nothing else on this screen names it.
    @Test
    func anavigationBarsIdentifierIsFoundWhenTheContentCarriesNone() throws {
        let directory = try TemporaryDirectory()
        let screen = AXNode(
            type: "Application",
            frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
            children: [
                AXNode(
                    type: "Window",
                    frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
                    children: [
                        AXNode(type: "NavigationBar", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 44), identifier: "Heart"),
                        AXNode(
                            type: "ScrollView",
                            frame: AXNode.Frame(x: 0, y: 44, width: 402, height: 830),
                            children: [
                                AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: 120, width: 200, height: 30), label: "Heart"),
                            ]
                        ),
                    ]
                ),
            ]
        )
        let bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "heart", captures: [
                CaptureBundleFixture.Capture(screenID: "heart", state: Walkbook.CaptureState(theme: .light), tree: screen),
            ]),
        ])

        let answer = try BundleScreenQuery(bundle).answer(step: "1")

        #expect(answer.text.contains("root 'Heart'"))
    }

    /// `<step>` also accepts the screen's own id, exact and validated, answering the same screen a position would (SimWalk#20 round 2, finding 4).
    @Test
    func astepGivenAsTheScreensOwnIDAnswersTheSameScreenAsItsPosition() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "today", captures: [CaptureBundleFixture.Capture(screenID: "today", state: Walkbook.CaptureState(theme: .light), tree: Self.tree(identifier: "TodayScreen", labels: [("StaticText", "Today")]))]),
            CaptureBundleFixture.ScreenSpec(id: "sleep-detail", captures: [CaptureBundleFixture.Capture(screenID: "sleep-detail", state: Walkbook.CaptureState(theme: .light), tree: Self.sleepTree)]),
        ])

        let byPosition = try BundleScreenQuery(bundle).answer(step: "2")
        let byID = try BundleScreenQuery(bundle).answer(step: "sleep-detail")

        #expect(byPosition.text == byID.text)
        #expect(byID.text.contains("step 2 'sleep-detail'"))
    }

    /// A step naming a screen id this walk does not hold refuses naming the ones it does, the same "refuse rather than guess" every other lookup here holds to.
    @Test
    func astepNamingAScreenIDThisWalkDoesNotHoldRefusesNamingTheOnesItHolds() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "today", captures: [CaptureBundleFixture.Capture(screenID: "today", state: Walkbook.CaptureState(theme: .light), tree: Self.tree(identifier: "TodayScreen", labels: [("StaticText", "Today")]))]),
        ])

        let thrown = #expect(throws: BundleScreenError.self) {
            try BundleScreenQuery(bundle).answer(step: "not-a-screen")
        }

        #expect(thrown == .screenIDNotFound(id: "not-a-screen", available: ["today"]))
    }

    /// `--match` narrows to labels that contain it, case-insensitively, and the verdict states the fraction rather than just the narrowed count.
    @Test
    func matchNarrowsToLabelsContainingItCaseInsensitively() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "sleep-detail", captures: [
                CaptureBundleFixture.Capture(screenID: "sleep-detail", state: Walkbook.CaptureState(theme: .light), tree: Self.sleepTree),
            ]),
        ])

        let answer = try BundleScreenQuery(bundle).answer(step: "1", match: "sleep")

        #expect(answer.text.contains("2 of 9 on-screen elements match 'sleep'"))
        #expect(answer.text.contains("Sleep · StaticText ·"))
        #expect(answer.text.contains("Sleep · Button ·"))
        #expect(!answer.text.contains("Nothing earlier to compare with"))
        #expect(!answer.text.contains("Cycling Distance"))
    }

    /// A step outside the walk's plan — too low or too high — refuses naming the range this walk actually holds, rather than an index-out-of-bounds crash or a silent wrap.
    @Test(arguments: [0, -1, 3])
    func astepOutsideTheWalksPlanRefusesNamingTheValidRange(_ step: Int) throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "today", captures: [CaptureBundleFixture.Capture(screenID: "today", state: Walkbook.CaptureState(theme: .light), tree: Self.tree(identifier: "TodayScreen", labels: [("StaticText", "Today")]))]),
            CaptureBundleFixture.ScreenSpec(id: "sleep-detail", captures: [CaptureBundleFixture.Capture(screenID: "sleep-detail", state: Walkbook.CaptureState(theme: .light), tree: Self.sleepTree)]),
        ])

        let thrown = #expect(throws: BundleScreenError.self) {
            try BundleScreenQuery(bundle).answer(step: String(step))
        }

        #expect(thrown == .stepOutOfRange(step: step, screenCount: 2))
        #expect(String(describing: thrown).contains("1 to 2"))
    }

    /// A step landing on a screen the walk never reached has no capture to read, and the refusal points at `bundle inspect` for the route rather than guessing at content that does not exist.
    @Test
    func astepLandingOnAnUnreachableScreenRefusesNamingTheOutcome() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "vault", outcome: .unreachable(routeTried: [.tap(label: "Vault")]), routeTaken: []),
        ])

        let thrown = #expect(throws: BundleScreenError.self) {
            try BundleScreenQuery(bundle).answer(step: "1")
        }

        #expect(thrown == .screenNotCaptured(step: 1, screenID: "vault", outcome: "UNREACHABLE"))
        #expect(String(describing: thrown).contains("bundle inspect"))
    }

    /// The refusal names the state the route failed in, as the walk summary does (SimWalk#122); an older bundle without it keeps the bare word.
    @Test
    func anUnreachableScreenNamesTheStateItsRouteFailedIn() throws {
        let directory = try TemporaryDirectory()
        let state = ScreenOutcome.UnreachableState(failing: "dark", among: ["light", "dark"])
        let bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "vault", outcome: .unreachable(routeTried: [.tap(label: "Vault")], state: state), routeTaken: []),
            CaptureBundleFixture.ScreenSpec(id: "old", outcome: .unreachable(routeTried: [.tap(label: "Old")]), routeTaken: []),
        ])

        let named = #expect(throws: BundleScreenError.self) { try BundleScreenQuery(bundle).answer(step: "1") }
        let bare = #expect(throws: BundleScreenError.self) { try BundleScreenQuery(bundle).answer(step: "2") }

        #expect(named == .screenNotCaptured(step: 1, screenID: "vault", outcome: "UNREACHABLE in state 'dark' (reached in light)"))
        #expect(bare == .screenNotCaptured(step: 2, screenID: "old", outcome: "UNREACHABLE"))
    }

    /// A screen captured in more than one state with none named answers for the first and names the others (SimWalk#101) — a refusal cost every read a second call carrying a state id.
    @Test
    func twoCapturedStatesWithNoStateNamedAnswersTheFirstAndNamesTheRest() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.twoStateSleepBundle(in: directory)

        let answer = try BundleScreenQuery(bundle).answer(step: "1")

        #expect(answer.text.contains("'sleep-detail' [light] (1 of 2 states; also dark; pick one with --state)"))
        #expect(!answer.text.contains("Sleep (dark)"))
    }

    /// A named state that is not one of the screen's planned captures is refused naming the ones it does hold.
    @Test
    func anamedStateThatIsNotOneOfTheScreensCapturesIsRefused() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.twoStateSleepBundle(in: directory)

        let thrown = #expect(throws: BundleScreenError.self) {
            try BundleScreenQuery(bundle).answer(step: "1", state: "loc_en_gb")
        }

        #expect(thrown == .stateNotFound(step: 1, screenID: "sleep-detail", requested: "loc_en_gb", available: ["light", "dark"]))
    }

    /// A named state that this walk refused, rather than one it never planned, says so — "refused" and "never such a thing" are different facts, and the manifest can tell them apart (SimWalk#20 round 2, nit).
    @Test
    func anamedStateThatWasRefusedSaysSoRatherThanClaimingItNeverExisted() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(
                id: "progress",
                outcome: .stateNotApplied(reason: "state 'dark' is no darker than 'light'"),
                captures: [CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: Self.tree(identifier: "ProgressScreen", labels: [("StaticText", "Progress")]))],
                refusedStates: [Walkbook.CaptureState(theme: .dark)]
            ),
        ])

        let thrown = #expect(throws: BundleScreenError.self) {
            try BundleScreenQuery(bundle).answer(step: "1", state: "dark")
        }

        #expect(thrown == .stateRefused(step: 1, screenID: "progress", requested: "dark", available: ["light"]))
        #expect(String(describing: thrown).contains("refused"))
    }

    /// A named state resolves the capture it names, among several.
    @Test
    func anamedStateResolvesTheRightCapture() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.twoStateSleepBundle(in: directory)

        let answer = try BundleScreenQuery(bundle).answer(step: "1", state: "dark")

        #expect(answer.text.contains("'sleep-detail' [dark]"))
        #expect(answer.text.contains("Sleep (dark)"))
    }

    /// A capture taken before its tree settled is evidence recorded mid-motion, and the answer says so rather than reading it as a finished screen.
    @Test
    func acaptureTakenBeforeItsTreeSettledQualifiesTheAnswer() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "today", captures: [
                CaptureBundleFixture.Capture(screenID: "today", state: Walkbook.CaptureState(theme: .light), tree: Self.tree(identifier: "TodayScreen", labels: [("StaticText", "Today")]), settled: false),
            ]),
        ])

        let answer = try BundleScreenQuery(bundle).answer(step: "1")

        #expect(answer.text.contains("qualified — 1 capture taken before the tree settled"))
    }

    /// A capture holding the app's chrome and nothing else is a screen that had not arrived, and the answer says so rather than reading a spinner as the screen's content.
    @Test
    func achromeOnlyCaptureQualifiesTheAnswerToo() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "today", captures: [
                CaptureBundleFixture.Capture(screenID: "today", state: Walkbook.CaptureState(theme: .light), tree: Self.tree(identifier: "TodayScreen", labels: [("StaticText", "Today")]), hasContent: false),
            ]),
        ])

        let answer = try BundleScreenQuery(bundle).answer(step: "1")

        #expect(answer.text.contains("qualified — 1 capture holding the app's chrome and nothing else"))
    }

    /// A still spinner is filed both unsettled and chrome-only (SimWalk#81); the answer states that one capture once, as the bare one it held, not also as taken before the tree settled.
    @Test
    func aBareCaptureIsOneQualificationNotTwo() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "today", captures: [
                CaptureBundleFixture.Capture(screenID: "today", state: Walkbook.CaptureState(theme: .light), tree: Self.tree(identifier: "TodayScreen", labels: [("StaticText", "Today")]), settled: false, hasContent: false),
            ]),
        ])

        let answer = try BundleScreenQuery(bundle).answer(step: "1")

        #expect(answer.text.contains("qualified — 1 capture holding the app's chrome and nothing else"))
        #expect(!answer.text.contains("before the tree settled"))
    }

    /// The saving is priced against the one screenshot this answer reads, never its tree — a reader answering a text question opens the screenshot or reads the tree, never both (SimWalk#20 round 2, finding 2).
    @Test
    func theAnswerIsPricedAgainstTheScreenshotAloneNeverTheTree() throws {
        let directory = try TemporaryDirectory()
        let firstTree = Self.tree(identifier: "TodayScreen", labels: [("StaticText", "Today")])
        let secondTree = Self.sleepTree
        let bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "today", captures: [CaptureBundleFixture.Capture(screenID: "today", state: Walkbook.CaptureState(theme: .light), tree: firstTree)]),
            CaptureBundleFixture.ScreenSpec(id: "sleep-detail", captures: [CaptureBundleFixture.Capture(screenID: "sleep-detail", state: Walkbook.CaptureState(theme: .light), tree: secondTree)]),
        ])

        let answer = try BundleScreenQuery(bundle).answer(step: "1")

        let saving = try #require(answer.saving)

        #expect(saving.screenshotTokens == [4070])
        #expect(saving.treeBytes == 0)
    }

    /// Every answer closes on the same standing note: a shape question still needs the screenshot.
    @Test
    func thetextOnlyNoteIsAlwaysInTheResidue() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "today", captures: [CaptureBundleFixture.Capture(screenID: "today", state: Walkbook.CaptureState(theme: .light), tree: Self.tree(identifier: "TodayScreen", labels: [("StaticText", "Today")]))]),
        ])

        let answer = try BundleScreenQuery(bundle).answer(step: "1")

        #expect(answer.text.contains("text only — colour, shape and visual emphasis (a capsule vs. a line) still need screen.png"))
    }

    /// A tree with no identifier anywhere below its root says so plainly rather than leaving the field blank — and a tab bar carrying one of its own (every real screen's does) is not read as the answer, because it is the same word on every screen (SimWalk#20 round 2, finding 1).
    @Test
    func ascreenWithNoRootIdentifierSaysSoRatherThanReadingTheTabBars() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "today", captures: [CaptureBundleFixture.Capture(screenID: "today", state: Walkbook.CaptureState(theme: .light), tree: Self.tree(identifier: nil, labels: [("StaticText", "Today")]))]),
        ])

        let answer = try BundleScreenQuery(bundle).answer(step: "1")

        #expect(answer.text.contains("root (no identifier — no container in the content carries one)"))
    }

    /// A step that is a valid position *and* the exact id of a different screen is refused naming both, rather than silently read as the position (SimWalk#20 round 3, nit).
    @Test
    func astepThatIsBothAPositionAndAnotherScreensIDIsAmbiguous() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.threeScreenBundle(in: directory, ids: ["today", "3", "sleep-detail"])

        let thrown = #expect(throws: BundleScreenError.self) {
            try BundleScreenQuery(bundle).answer(step: "3")
        }

        #expect(thrown == .ambiguousStep(step: "3", positionScreenID: "sleep-detail", idPosition: 2))
        #expect(String(describing: thrown).contains("'sleep-detail'"))
        #expect(String(describing: thrown).contains("step 2"))
    }

    /// A numeric id that is the screen at its own position is not ambiguous, and one that is no valid position resolves as the id.
    @Test
    func anumericIDThatCannotBeMisreadResolves() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.threeScreenBundle(in: directory, ids: ["today", "2", "7"])

        let atItsOwnPosition = try BundleScreenQuery(bundle).answer(step: "2")
        let beyondThePlan = try BundleScreenQuery(bundle).answer(step: "7")

        #expect(atItsOwnPosition.text.contains("step 2 '2'"))
        #expect(beyondThePlan.text.contains("step 3 '7'"))
    }

    /// Every number `bundle inspect` prints beside a screen is the step `bundle screen` resolves to that same screen — captured or not — so the listing can be read off and used as it stands.
    @Test
    func everyNumberInspectListsResolvesToTheSameScreenHere() throws {
        let directory = try TemporaryDirectory()
        let bundle = try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "today", captures: [CaptureBundleFixture.Capture(screenID: "today", state: Walkbook.CaptureState(theme: .light), tree: Self.tree(identifier: "TodayScreen", labels: [("StaticText", "Today")]))]),
            CaptureBundleFixture.ScreenSpec(id: "vault", outcome: .unreachable(routeTried: [.tap(label: "Vault")]), routeTaken: []),
            CaptureBundleFixture.ScreenSpec(id: "sleep-detail", captures: [CaptureBundleFixture.Capture(screenID: "sleep-detail", state: Walkbook.CaptureState(theme: .light), tree: Self.sleepTree)]),
        ])

        let listed = CaptureBundleSummary(bundle).render().split(separator: "\n").compactMap { line -> (Int, String)? in
            let words = line.split(separator: " ")
            guard line.hasPrefix("  "), words.count > 2, words[2] == "—", let number = Int(words[0]) else { return nil }
            return (number, String(words[1]))
        }

        #expect(listed.map(\.1) == ["today", "vault", "sleep-detail"])
        for (number, id) in listed {
            do {
                let answer = try BundleScreenQuery(bundle).answer(step: String(number))
                #expect(answer.text.contains("step \(number) '\(id)'"))
            } catch let error as BundleScreenError {
                #expect(error == .screenNotCaptured(step: number, screenID: id, outcome: "UNREACHABLE"))
            }
        }
    }

    /// The state refusal names what is missing — a capture — rather than claiming the state never existed, which is false for a planned state whose capture failed (SimWalk#20 round 3, nit).
    @Test
    func astateWithNoCaptureIsRefusedAsAMissingCaptureNotAMissingState() {
        let error = BundleScreenError.stateNotFound(step: 1, screenID: "sleep-detail", requested: "dark", available: ["light"])

        #expect(String(describing: error) == "step 1 ('sleep-detail') holds no 'dark' capture — it holds light")
    }

    /// Three captured screens under `ids`, in order.
    private static func threeScreenBundle(in directory: TemporaryDirectory, ids: [String]) throws -> CaptureBundle {
        try CaptureBundleFixture.writeWalk(in: directory, screens: ids.map { id in
            CaptureBundleFixture.ScreenSpec(id: id, captures: [CaptureBundleFixture.Capture(screenID: id, state: Walkbook.CaptureState(theme: .light), tree: tree(identifier: "Screen", labels: [("StaticText", id)]))])
        })
    }

    /// A screen captured in two states, for the first-state and named-state tests: light is clean, dark is what a reader who did name it would get.
    private static func twoStateSleepBundle(in directory: TemporaryDirectory) throws -> CaptureBundle {
        try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(id: "sleep-detail", captures: [
                CaptureBundleFixture.Capture(screenID: "sleep-detail", state: Walkbook.CaptureState(theme: .light), tree: sleepTree),
                CaptureBundleFixture.Capture(screenID: "sleep-detail", state: Walkbook.CaptureState(theme: .dark), tree: tree(identifier: "SleepDetailScreen", labels: [("StaticText", "Sleep (dark)")])),
            ]),
        ])
    }

    /// A screen root shaped like a real capture (SimWalk#20 round 2, finding 1): the app root itself carries no identifier and its own label is the app's display name, its content sits under `Window → ScrollView` with the given labels as direct children, and a tab bar shaped as every real one is — no identifier of its own, its items' images identified — sits beside it rather than under it.
    private static func tree(identifier: String?, labels: [(type: String, label: String)]) -> AXNode {
        let screenFrame = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)
        return AXNode(
            type: "Application",
            frame: screenFrame,
            label: "RouteFixture",
            children: [
                AXNode(
                    type: "Window",
                    frame: screenFrame,
                    children: [
                        AXNode(
                            type: "ScrollView",
                            frame: screenFrame,
                            identifier: identifier,
                            children: labels.enumerated().map { index, entry in
                                AXNode(type: entry.type, frame: AXNode.Frame(x: 14, y: 88 + Double(index) * 40, width: 374, height: 24), label: entry.label)
                            }
                        ),
                        // Shaped as every real tab bar is — no identifier of its own, identified item images — so the
                        // root lookup is exercised against the identifiers a real capture actually carries under it
                        // (SimWalk#20 round 3, finding 6). Its five labels are text on screen, as on a real capture.
                        ScreenTreeFixture.tabBar(),
                    ]
                ),
            ]
        )
    }

    /// The specimen from SimWalk#20's own field report: a row, its "nothing to compare" note, a dated line, and a tab sharing the row's label at a different frame — plus one exact duplicate of the row, which is what the dedup tests key off — beside a real-shaped tab bar, whose five labels (the bar's own, two items, two images) bring the screen to nine text elements.
    private static var sleepTree: AXNode {
        let screenFrame = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)
        return AXNode(
            type: "Application",
            frame: screenFrame,
            label: "RouteFixture",
            children: [
                AXNode(
                    type: "Window",
                    frame: screenFrame,
                    children: [
                        AXNode(
                            type: "ScrollView",
                            frame: screenFrame,
                            identifier: "SleepDetailScreen",
                            children: [
                                AXNode(type: "StaticText", frame: AXNode.Frame(x: 14, y: 88, width: 374, height: 24), label: "Sleep"),
                                AXNode(type: "StaticText", frame: AXNode.Frame(x: 14, y: 88, width: 374, height: 24), label: "Sleep"),
                                AXNode(type: "StaticText", frame: AXNode.Frame(x: 14, y: 120, width: 374, height: 24), label: "Nothing earlier to compare with"),
                                AXNode(type: "StaticText", frame: AXNode.Frame(x: 14, y: 700, width: 374, height: 24), label: "Cycling Distance · 5 Sep · 8.9 km"),
                                AXNode(type: "Button", frame: AXNode.Frame(x: 25, y: 795, width: 85, height: 54), label: "Sleep"),
                            ]
                        ),
                        ScreenTreeFixture.tabBar(),
                    ]
                ),
            ]
        )
    }
}
