//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// A live session's `step`: the screen hash a guard is checked against, the delta a step reports, the stepper's guard and per-step decisions, the route read back from the responses, and the answer the CLI prints.
struct LiveSessionStepTests {
    // MARK: - ScreenHash

    @Test
    func screenHashChangesWhenALabelValueOrFrameChanges() {
        let hash = ScreenHash.of(Self.home)

        #expect(ScreenHash.of(Self.home(label: "Fourth")) != hash)
        #expect(ScreenHash.of(Self.home(value: "on")) != hash)
        #expect(ScreenHash.of(Self.home(x: 17)) != hash)
        #expect(ScreenHash.of(Self.home(width: 99)) != hash)
    }

    @Test
    func screenHashIsStableForTheSameScreenReadAgainAndForSubPointGeometry() {
        let hash = ScreenHash.of(Self.home)

        #expect(ScreenHash.of(Self.home) == hash)
        #expect(ScreenHash.of(Self.home(x: 16.3)) == hash)
        #expect(hash.count == ShortHash.digits)
    }

    // MARK: - ScreenDelta

    @Test
    func deltaCountsWhatAppearedAndDisappearedInBundleScreensForm() {
        let delta = ScreenDelta(from: Self.home, to: Self.detail)

        #expect(delta.appearedCount == 1)
        #expect(delta.disappearedCount == 3)
        #expect(delta.appeared == ["Detail · StaticText · 16,100 370×40"])
        #expect(delta.disappeared.first == "First · Button · 16,100 100×44")
        #expect(delta.residue.first == "delta: 1 appeared, 3 disappeared")
        #expect(delta.residue.contains("+ Detail · StaticText · 16,100 370×40"))
        #expect(delta.residue.contains("- Third · Button · 232,100 100×44"))
    }

    @Test
    func deltaCountsInFullAndListsAtMostTwentyOfEach() {
        let rows = AXNode(type: "Application", frame: Self.screenFrame, label: "App", children: (0 ..< 45).map {
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: Double(20 + $0 * 18), width: 200, height: 16), label: "Row \($0)")
        })

        let delta = ScreenDelta(from: Self.home, to: rows)

        #expect(delta.appearedCount == 45)
        #expect(delta.appeared.count == ScreenDelta.cap)
        #expect(ScreenDelta.cap == 20)
        #expect(delta.appeared.first == "Row 0 · StaticText · 16,20 200×16")
        #expect(delta.residue.contains("+ … 25 more — `session read` lists them all"))
        #expect(ScreenDelta(from: Self.home, to: Self.home).residue == ["delta: nothing appeared or disappeared"])
    }

    // MARK: - LiveSessionStepper

    @Test
    func aStaleGuardIsRefusedBeforeAnythingActs() throws {
        var stepper = LiveSessionStepper(quiet: 0.25)
        let sheet = CountingTreeSource(tree: Self.home)
        var performed = 0
        var readsAfter = 0
        let request = LiveSessionRequest(n: 3, action: .step, step: .tap(label: "First"), guardHash: "00000000")

        let response = try stepper.answer(
            request,
            screen: CountingTreeSource(tree: Self.home),
            sheetReads: sheet,
            perform: { _, _ in
                performed += 1
                return .landed(.tap(label: "First"), sheetClosed: false, bound: nil)
            },
            read: {
                readsAfter += 1
                return Self.screen(Self.detail)
            }
        )

        #expect(performed == 0)
        #expect(readsAfter == 0)
        #expect(sheet.reads == 0)
        #expect(response == LiveSessionResponse(n: 3, action: .step, step: .snapshotChanged(expected: "00000000", found: ScreenHash.of(Self.home))))
    }

    @Test
    func aMatchingGuardTakesTheStepAndAnswersWithTheRecordedStepAndTheDelta() throws {
        var stepper = LiveSessionStepper(quiet: 0.25)
        let recorded = Walkbook.RouteStep.systemTap(label: "Allow", owner: .springboard)
        var taken: [Walkbook.RouteStep] = []

        let response = try stepper.answer(
            LiveSessionRequest(n: 1, action: .step, step: .systemTap(label: "Allow"), guardHash: ScreenHash.of(Self.home)),
            screen: CountingTreeSource(tree: Self.home),
            sheetReads: CountingTreeSource(tree: Self.home),
            perform: { step, scope in
                taken.append(step)
                #expect(scope != nil)
                return .landed(recorded, sheetClosed: true, bound: nil)
            },
            read: { Self.screen(Self.detail) }
        )

        #expect(taken == [.systemTap(label: "Allow")])
        #expect(response.step == .landed(recorded, delta: ScreenDelta(from: Self.home, to: Self.detail)))
        #expect(response.screen == Self.screen(Self.detail))
    }

    @Test
    func aBlockedStepIsAnsweredWithItsReasonAndTheScreenItLeft() throws {
        var stepper = LiveSessionStepper(quiet: 0.25)

        let response = try stepper.answer(
            LiveSessionRequest(n: 2, action: .step, step: .tap(label: "Nowhere")),
            screen: CountingTreeSource(tree: Self.home),
            sheetReads: CountingTreeSource(tree: Self.home),
            perform: { _, _ in .blocked(reason: "no element labelled 'Nowhere'") },
            read: { Self.screen(Self.home) }
        )

        #expect(response.step == .blocked(reason: "no element labelled 'Nowhere'", delta: ScreenDelta(from: Self.home, to: Self.home)))
    }

    @Test
    func theScreenAfterAStepIsReadOnlyOnceItHasHeldStill() throws {
        var stepper = LiveSessionStepper(quiet: 0.25)
        // Read before the step, then three reads of a pop still moving, then the screen at rest.
        let screen = CountingTreeSource(trees: [Self.home, Self.home(x: 60), Self.home(x: 40), Self.home(x: 20)], then: Self.detail)
        var readsWhenRead = 0

        _ = try stepper.answer(
            LiveSessionRequest(n: 1, action: .step, step: .back),
            screen: screen,
            sheetReads: CountingTreeSource(tree: Self.home),
            perform: { step, _ in .landed(step, sheetClosed: false, bound: nil) },
            read: {
                readsWhenRead = screen.reads
                return Self.screen(Self.detail)
            }
        )

        #expect(readsWhenRead >= 6)
    }

    // MARK: - The route, and the answer

    @Test
    func theRouteIsTheLandedStepsInRequestOrder() throws {
        let directory = try TemporaryDirectory()
        let channel = LiveSessionChannel(layout: LiveSessionLayout(directory: directory.url))
        try channel.prepare()
        let delta = ScreenDelta(from: Self.home, to: Self.detail)
        for _ in 1 ... 5 {
            _ = try channel.send(.read)
        }
        try channel.respond(LiveSessionResponse(n: 1, action: .step, step: .landed(.openURL(url: "x://detail"), delta: delta)))
        try channel.respond(LiveSessionResponse(n: 2, action: .read, screen: Self.screen(Self.detail)))
        try channel.respond(LiveSessionResponse(n: 3, action: .step, step: .blocked(reason: nil, delta: delta)))
        try channel.respond(LiveSessionResponse(n: 4, action: .step, step: .snapshotChanged(expected: "a", found: "b")))
        try channel.respond(LiveSessionResponse(n: 5, action: .step, step: .landed(.back, delta: delta)))

        #expect(try channel.route() == [.openURL(url: "x://detail"), .back])
    }

    @Test
    func aStepRequestRoundTripsWithItsGuardUnderTheGuardKey() throws {
        let request = LiveSessionRequest(n: 4, action: .step, step: .back, guardHash: "1a2b3c4d")

        let json = try #require(String(data: CaptureBundle.encoder().encode(request), encoding: .utf8))

        #expect(json.contains("\"guard\""))
        #expect(try CaptureBundle.decoder().decode(LiveSessionRequest.self, from: Data(json.utf8)) == request)
    }

    @Test
    func theAnswerPrintsTheLandedStepTheHashAndTheDelta() throws {
        let answer = try LiveSessionStepQuery(
            sent: .openURL(url: "x://detail"),
            answer: .landed(.openURL(url: "x://detail"), delta: ScreenDelta(from: Self.home, to: Self.detail)),
            screen: Self.screen(Self.detail)
        ).answer()

        #expect(answer.verdict == .unqualified("landed openURL 'x://detail' — now on root 'route-detail'"))
        #expect(answer.residue.prefix(3) == [#"step: {"openURL":{"url":"x://detail"}}"#, "screen \(ScreenHash.of(Self.detail))", "delta: 1 appeared, 3 disappeared"])
    }

    /// A landed step that bound an element names it on one line after `step:`, in the form `inspect` prints a node (SimWalk#93).
    @Test
    func aBoundElementPrintsAfterTheStepLine() throws {
        let cell = AXNode(type: "Cell", frame: AXNode.Frame(x: 16, y: 214, width: 370, height: 132), label: "Steps")
        let answer = try LiveSessionStepQuery(
            sent: .tap(label: "Steps"),
            answer: .landed(.tap(label: "Steps"), bound: cell, delta: ScreenDelta(from: Self.home, to: Self.detail)),
            screen: Self.screen(Self.detail)
        ).answer()

        #expect(answer.residue.prefix(2) == [#"step: {"tap":{"label":"Steps"}}"#, "bound: Steps · Cell · 16,214 370×132"])
        let unbound = try LiveSessionStepQuery(
            sent: .back,
            answer: .landed(.back, delta: ScreenDelta(from: Self.home, to: Self.detail)),
            screen: Self.screen(Self.detail)
        ).answer()
        #expect(!unbound.residue.contains { $0.hasPrefix("bound:") })
    }

    /// A landed `systemTap` prints as a walkbook writes it: the owner the runner found it in is a walk's record, and a walkbook that writes one is refused.
    @Test
    func aLandedSystemTapPrintsWithoutItsOwner() throws {
        let answer = try LiveSessionStepQuery(
            sent: .systemTap(label: "Allow"),
            answer: .landed(.systemTap(label: "Allow", owner: .springboard), delta: ScreenDelta(from: Self.home, to: Self.detail)),
            screen: Self.screen(Self.detail)
        ).answer()

        #expect(answer.residue.first == #"step: {"systemTap":{"label":"Allow"}}"#)
    }

    @Test
    func aBlockedStepIsQualifiedAndAStaleGuardRefusedNamingBothHashes() throws {
        let blocked = try LiveSessionStepQuery(sent: .tap(label: "Nowhere"), answer: .blocked(reason: "no match", delta: ScreenDelta(from: Self.home, to: Self.home)), screen: Self.screen(Self.home)).answer()

        #expect(blocked.verdict.exitCode == AnswerVerdict.qualifiedExitCode)
        #expect(blocked.verdict.line.contains("blocked: tap 'Nowhere' did not land — no match"))
        #expect(!blocked.residue.contains { $0.hasPrefix("step:") })

        let error = try #require(throws: LiveSessionError.self) {
            try LiveSessionStepQuery(sent: .back, answer: .snapshotChanged(expected: "aaaa1111", found: "bbbb2222"), screen: nil).answer()
        }

        #expect(error == .snapshotChanged(expected: "aaaa1111", found: "bbbb2222"))
        #expect(error.description.contains("the screen is bbbb2222, not aaaa1111 as guarded, so the step was not taken — read it again"))
    }
}

extension LiveSessionStepTests {
    static let screenFrame = AXNode.Frame(x: 0, y: 0, width: 402, height: 874)

    static let home = home()

    /// RouteFixture's home: an HStack of three buttons.
    static func home(label: String = "Third", value: String? = nil, x: Double = 16, width: Double = 100) -> AXNode {
        AXNode(type: "Application", frame: screenFrame, label: "RouteFixture", children: [
            AXNode(type: "Other", frame: screenFrame, identifier: "route-home", children: [
                AXNode(type: "Button", frame: AXNode.Frame(x: x, y: 100, width: width, height: 44), label: "First", value: value),
                AXNode(type: "Button", frame: AXNode.Frame(x: 124, y: 100, width: 100, height: 44), label: "Second"),
                AXNode(type: "Button", frame: AXNode.Frame(x: 232, y: 100, width: 100, height: 44), label: label),
            ]),
        ])
    }

    static let detail = AXNode(type: "Application", frame: screenFrame, label: "RouteFixture", children: [
        AXNode(type: "Other", frame: screenFrame, identifier: "route-detail", children: [
            AXNode(type: "StaticText", frame: AXNode.Frame(x: 16, y: 100, width: 370, height: 40), label: "Detail"),
        ]),
    ])

    static func screen(_ tree: AXNode) -> LiveScreen {
        LiveScreen(
            appBundleID: "dev.simwalk.route-fixture",
            device: CaptureManifest.Device(name: "iPhone 17", udid: "UDID-1", osVersion: "27.0"),
            runnerCommit: nil,
            readAt: Date(timeIntervalSince1970: 0),
            nonce: "s1",
            appState: .foreground,
            tree: tree,
            settled: true,
            screenPixels: nil
        )
    }

    /// A screen that counts its reads, on a clock that moves only when it is paused.
    final class CountingTreeSource: TreeSource {
        private let trees: [AXNode]
        private let rest: AXNode
        private(set) var reads = 0
        private var clock: TimeInterval = 0

        init(tree: AXNode) {
            trees = []
            rest = tree
        }

        /// Reads `trees` in turn, then `rest` for ever.
        init(trees: [AXNode], then rest: AXNode) {
            self.trees = trees
            self.rest = rest
        }

        func appTree() throws -> AXNode {
            reads += 1
            return reads <= trees.count ? trees[reads - 1] : rest
        }

        func elapsed() -> TimeInterval {
            clock
        }

        func pause(_ interval: TimeInterval) {
            clock += interval
        }
    }
}
