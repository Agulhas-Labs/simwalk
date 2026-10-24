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
            pixels: { _ in nil },
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
            pixels: { _ in nil },
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
            pixels: { _ in nil },
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
            pixels: { _ in nil },
            perform: { step, _ in .landed(step, sheetClosed: false, bound: nil) },
            read: {
                readsWhenRead = screen.reads
                return Self.screen(Self.detail)
            }
        )

        #expect(readsWhenRead >= 6)
    }

    /// A relaunch launches, waits for the relaunched app to hold still, and answers with the screen under its own action.
    @Test
    func aRelaunchLaunchesThenReadsTheScreenOnceItHasHeldStill() throws {
        var stepper = LiveSessionStepper(quiet: 0.25)
        let screen = CountingTreeSource(trees: [Self.home(x: 60), Self.home(x: 40)], then: Self.home)
        var launched = 0
        var readsWhenRead = 0

        let response = try stepper.relaunch(
            LiveSessionRequest(n: 4, action: .relaunch),
            screen: screen,
            launch: {
                launched += 1
                return false
            },
            read: {
                readsWhenRead = screen.reads
                return Self.screen(Self.home)
            }
        )

        #expect(launched == 1)
        #expect(readsWhenRead >= 3)
        #expect(response == LiveSessionResponse(n: 4, action: .relaunch, screen: Self.screen(Self.home)))
    }

    /// A relaunch that turned the device to match a landscape app says so in its answer (SimWalk#225); one that did not turn says nothing.
    @Test
    func aRelaunchThatTurnedTheDeviceCarriesTheNote() throws {
        var stepper = LiveSessionStepper(quiet: 0.25)
        let screen = CountingTreeSource(trees: [Self.home(x: 60)], then: Self.home)

        let response = try stepper.relaunch(
            LiveSessionRequest(n: 4, action: .relaunch),
            screen: screen,
            launch: { true },
            read: { Self.screen(Self.home) }
        )

        #expect(response.notes == [DeviceAlignment.note()])
        #expect(response.screen == Self.screen(Self.home))
    }

    /// An answer written before `notes` existed decodes with none, and an answer with none writes no key.
    @Test
    func anAnswerWithNoNotesKeyDecodesAndWritesNone() throws {
        let plain = LiveSessionResponse(n: 4, action: .relaunch, screen: Self.screen(Self.home))
        let json = try JSONEncoder().encode(plain)

        #expect(try JSONDecoder().decode(LiveSessionResponse.self, from: json).notes == nil)
        #expect(!String(decoding: json, as: UTF8.self).contains("notes"))

        let noted = LiveSessionResponse(n: 4, action: .relaunch, notes: ["a"])
        #expect(try JSONDecoder().decode(LiveSessionResponse.self, from: JSONEncoder().encode(noted)) == noted)
    }

    /// A scroll drags once, waits for the screen to hold still, and answers with the screen read after the drag under its own action.
    @Test
    func aScrollDragsOnceThenReadsTheScreenOnceItHasHeldStill() throws {
        var stepper = LiveSessionStepper(quiet: 0.25)
        let screen = CountingTreeSource(trees: [Self.home(x: 60), Self.home(x: 40)], then: Self.home)
        let scroll = LiveSessionScroll(direction: .down, container: AXNode.Frame(x: 0, y: 100, width: 390, height: 600))
        var dragged = 0
        var readsWhenRead = 0

        let response = try stepper.scroll(
            LiveSessionRequest(n: 5, action: .scroll, scroll: scroll),
            screen: screen,
            drag: { dragged += 1 },
            read: {
                readsWhenRead = screen.reads
                return Self.screen(Self.home)
            }
        )

        #expect(dragged == 1)
        #expect(readsWhenRead >= 3)
        #expect(response == LiveSessionResponse(n: 5, action: .scroll, screen: Self.screen(Self.home)))
    }

    /// A scroll request that names no scroll is refused with nothing dragged.
    @Test
    func aScrollRequestWithNoScrollIsRefusedAndNothingIsDragged() {
        var stepper = LiveSessionStepper(quiet: 0.25)
        var dragged = 0

        #expect(throws: (any Error).self) {
            try stepper.scroll(
                LiveSessionRequest(n: 5, action: .scroll),
                screen: CountingTreeSource(trees: [], then: Self.home),
                drag: { dragged += 1 },
                read: { Self.screen(Self.home) }
            )
        }
        #expect(dragged == 0)
    }

    /// A scroll request is one JSON object with its direction and the container's box, on the simulator's file and the device's frame alike.
    @Test
    func aScrollRequestKeepsItsScrollOnTheWire() throws {
        let scroll = LiveSessionScroll(direction: .up, container: AXNode.Frame(x: 0, y: 100, width: 390, height: 600))
        let request = LiveSessionRequest(n: 3, action: .scroll, scroll: scroll)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let json = try String(decoding: encoder.encode(request), as: UTF8.self)

        #expect(json.contains(#""action":"scroll""#))
        #expect(json.contains(#""scroll":{"container":{"height":600,"width":390,"x":0,"y":100},"direction":"up"}"#))
        #expect(try JSONDecoder().decode(LiveSessionRequest.self, from: Data(json.utf8)) == request)
        #expect(DeviceSessionRequest(action: .scroll, scroll: scroll).numbered(3) == request)
        let device = try encoder.encode(DeviceSessionRequest(action: .scroll, scroll: scroll))
        #expect(try JSONDecoder().decode(DeviceSessionRequest.self, from: device).scroll == scroll)
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

    /// A relaunch puts the app back at launch, so the steps before it are not on the way to where the session ends.
    @Test
    func theRouteStartsAfterTheLastRelaunch() throws {
        let directory = try TemporaryDirectory()
        let channel = LiveSessionChannel(layout: LiveSessionLayout(directory: directory.url))
        try channel.prepare()
        let delta = ScreenDelta(from: Self.home, to: Self.detail)
        for _ in 1 ... 5 {
            _ = try channel.send(.read)
        }
        try channel.respond(LiveSessionResponse(n: 1, action: .step, step: .landed(.openURL(url: "x://one"), delta: delta)))
        try channel.respond(LiveSessionResponse(n: 2, action: .step, step: .landed(.openURL(url: "x://two"), delta: delta)))
        try channel.respond(LiveSessionResponse(n: 3, action: .step, step: .landed(.back, delta: delta)))
        try channel.respond(LiveSessionResponse(n: 4, action: .relaunch, screen: Self.screen(Self.home)))
        try channel.respond(LiveSessionResponse(n: 5, action: .step, step: .landed(.openURL(url: "x://detail"), delta: delta)))

        #expect(try channel.route() == [.openURL(url: "x://detail")])
        #expect(try channel.landedSteps(since: 1).map(\.request) == [5])
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

    /// A landed screen-point `tapPoint` names the frame its point was taken in, from the tree's root, so a landscape app's reader is not misled by a portrait screenshot (SimWalk#149).
    @Test(arguments: [
        (AXNode.Frame(x: 0, y: 0, width: 874, height: 402), " in the app's 874×402 pt frame (landscape)"),
        (AXNode.Frame(x: 0, y: 0, width: 402, height: 874), " in the app's 402×874 pt frame (portrait)"),
        (AXNode.Frame(x: 0, y: 0, width: 500, height: 500), " in the app's 500×500 pt frame"),
        (AXNode.Frame(x: 0, y: 0, width: 0, height: 0), ""),
    ])
    func aLandedScreenPointTapNamesTheFrameItWasTakenIn(frame: AXNode.Frame, clause: String) throws {
        let root = AXNode(type: "Application", frame: frame, label: "RouteFixture")
        let step = Walkbook.RouteStep.tapPoint(label: nil, point: [437, 273])

        let answer = try LiveSessionStepQuery(sent: step, answer: .landed(step, delta: ScreenDelta(from: Self.home, to: root)), screen: Self.screen(root)).answer()

        #expect(answer.verdict.line.contains("landed tap at 437,273 pt\(clause) — now on root"))
    }

    @Test
    func aLabelledTapPointNamesNoFrame() throws {
        let step = Walkbook.RouteStep.tapPoint(label: "Steps chart", point: [0.8, 0.5])
        let root = AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 874, height: 402), label: "RouteFixture")

        let answer = try LiveSessionStepQuery(sent: step, answer: .landed(step, delta: ScreenDelta(from: Self.home, to: root)), screen: Self.screen(root)).answer()

        #expect(!answer.verdict.line.contains("in the app's"))
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

    // MARK: - Pixels for a tree with no text (SimWalk#150)

    /// A game's tree: one view, nothing a reader lists.
    static let canvas = AXNode(type: "Application", frame: screenFrame, children: [AXNode(type: "Other", frame: screenFrame)])

    /// A step on `source`'s canvas, whose after-read carries `after`'s picture.
    private func stepOnCanvas(_ source: CountingTreeSource, after: Data, guardHash: String? = nil) throws -> LiveSessionResponse {
        var stepper = LiveSessionStepper(quiet: 0.25)
        return try stepper.answer(
            LiveSessionRequest(n: 1, action: .step, step: .tapPoint(label: nil, point: [200, 400]), guardHash: guardHash),
            screen: source,
            sheetReads: CountingTreeSource(tree: Self.canvas),
            pixels: { _ in PixelSignature(png: source.screenshot()) },
            perform: { _, _ in .landed(.tapPoint(label: nil, point: [200, 400]), sheetClosed: false, bound: nil) },
            read: { Self.screen(Self.canvas, pixels: PixelSignature(png: after)) }
        )
    }

    @Test
    func aTextlessScreenThatChangedItsPixelsIsToldApartAndSaysHowMuch() throws {
        let black = try PixelSignatureTests.png()
        let half = try PixelSignatureTests.png(whiteTopFraction: 0.5)
        let source = CountingTreeSource(tree: Self.canvas)
        source.pictures = [black]

        let response = try stepOnCanvas(source, after: half)

        let step = try #require(response.step)
        let delta = try #require(step.delta)
        #expect(delta.residue.contains { $0.hasPrefix("pixels: 5") && $0.contains("% of the screen changed") })
        let hash = try ScreenHash.of(Self.canvas, pixels: PixelSignatureTests.signature(half))
        let printed = try LiveSessionStepQuery(sent: .tapPoint(label: nil, point: [200, 400]), answer: step, screen: response.screen).answer()
        #expect(printed.residue.contains("screen \(hash)"))
        #expect(try hash != ScreenHash.of(Self.canvas, pixels: PixelSignatureTests.signature(black)))
        #expect(source.screenshots == 1)
    }

    @Test
    func aTextlessScreenWithTheSamePixelsIsTheSameScreen() throws {
        let black = try PixelSignatureTests.png()
        let source = CountingTreeSource(tree: Self.canvas)
        source.pictures = [black]

        let response = try stepOnCanvas(source, after: black)

        let delta = try #require(response.step?.delta)
        let residue = delta.residue

        #expect(residue.first == "delta: nothing appeared or disappeared")
        #expect(residue.contains { $0.hasPrefix("pixels: nothing changed") })
    }

    @Test
    func aGuardBuiltFromTheHashAReadPrintedMatchesAnUntouchedTextlessScreenAndRefusesAChangedOne() throws {
        let black = try PixelSignatureTests.png()
        let half = try PixelSignatureTests.png(whiteTopFraction: 0.5)
        let printed = try ScreenHash.of(Self.canvas, pixels: PixelSignatureTests.signature(black))
        let untouched = CountingTreeSource(tree: Self.canvas)
        untouched.pictures = [black]

        let landed = try stepOnCanvas(untouched, after: black, guardHash: printed)
        #expect(landed.step?.outcome == .landed)

        let changed = CountingTreeSource(tree: Self.canvas)
        changed.pictures = [half]
        let refused = try stepOnCanvas(changed, after: black, guardHash: printed)
        #expect(try refused.step == .snapshotChanged(expected: printed, found: ScreenHash.of(Self.canvas, pixels: PixelSignatureTests.signature(half))))
    }

    /// A step on `source`'s canvas by `stepper`, which keeps what it remembers from call to call.
    private func step(_ stepper: inout LiveSessionStepper, on source: CountingTreeSource, of tree: AXNode, guardHash: String?) throws -> LiveSessionResponse {
        try stepper.answer(
            LiveSessionRequest(n: 1, action: .step, step: .tapPoint(label: nil, point: [200, 400]), guardHash: guardHash),
            screen: source,
            sheetReads: CountingTreeSource(tree: tree),
            pixels: { _ in PixelSignature(png: source.screenshot()) },
            perform: { _, _ in .landed(.tapPoint(label: nil, point: [200, 400]), sheetClosed: false, bound: nil) },
            read: { Self.screen(tree, pixels: PixelSignature(png: source.screenshot())) }
        )
    }

    /// A stepper that has read `tree` with `picture`, as a `session read` would have.
    private func stepperThatRead(_ tree: AXNode, _ picture: Data) throws -> (LiveSessionStepper, printed: String) {
        var stepper = LiveSessionStepper(quiet: 0.25)
        let signature = try PixelSignatureTests.signature(picture)
        stepper.remember(Self.screen(tree, pixels: signature))
        return (stepper, ScreenHash.of(tree, pixels: signature))
    }

    /// SimWalk#226: an idle animation moves a few cells and must not refuse the guard.
    @Test
    func aTextlessGuardHoldsWhenThePictureMovedUnderTheToleranceAndTheStepSaysSo() throws {
        let black = try PixelSignatureTests.png()
        let nudged = try PixelSignatureTests.png(whiteTopFraction: 0.05)
        var (stepper, printed) = try stepperThatRead(Self.canvas, black)
        let source = CountingTreeSource(tree: Self.canvas)
        source.pictures = [nudged]
        #expect(try ScreenHash.of(Self.canvas, pixels: PixelSignatureTests.signature(nudged)) != printed)

        let response = try step(&stepper, on: source, of: Self.canvas, guardHash: printed)

        #expect(response.step?.outcome == .landed)
        let moved = try #require(response.step?.pixelsMoved)
        #expect(moved > 0 && moved <= PixelSignature.guardTolerance)
        let residue = try LiveSessionStepQuery(sent: .back, answer: #require(response.step), screen: response.screen).answer().residue
        #expect(residue.contains { $0.hasPrefix("guard: held, ") && $0.contains("of the screen moved since \(printed)") })
    }

    @Test
    func aTextlessGuardOverTheToleranceIsRefusedNamingHowMuchChanged() throws {
        let black = try PixelSignatureTests.png()
        let third = try PixelSignatureTests.png(whiteTopFraction: 0.3)
        var (stepper, printed) = try stepperThatRead(Self.canvas, black)
        let source = CountingTreeSource(tree: Self.canvas)
        source.pictures = [third]

        let response = try step(&stepper, on: source, of: Self.canvas, guardHash: printed)

        let moved = try #require(response.step?.pixelsMoved)
        #expect(moved > PixelSignature.guardTolerance)
        let error = try #require(throws: LiveSessionError.self) {
            try LiveSessionStepQuery(sent: .back, answer: #require(response.step), screen: nil).answer()
        }
        #expect(error.description.contains("\(Int((moved * 100).rounded()))% of the screen changed since it was read"))
    }

    /// SimWalk#226: the picture is compared only for the same tree; a different text-less screen whose picture is close is still another screen.
    @Test
    func aTextlessGuardIsRefusedWhenTheTreeIsNotTheOneTheHashWasPrintedFor() throws {
        let black = try PixelSignatureTests.png()
        let nudged = try PixelSignatureTests.png(whiteTopFraction: 0.05)
        let otherCanvas = AXNode(type: "Application", frame: Self.screenFrame, children: [
            AXNode(type: "Other", frame: AXNode.Frame(x: 0, y: 0, width: 200, height: 874)),
        ])
        var (stepper, printed) = try stepperThatRead(Self.canvas, black)
        let source = CountingTreeSource(tree: otherCanvas)
        source.pictures = [nudged]

        let response = try step(&stepper, on: source, of: otherCanvas, guardHash: printed)

        #expect(response.step?.outcome == .snapshotChanged)
        #expect(response.step?.pixelsMoved == nil)
    }

    /// SimWalk#226: a step remembers the screen it left, so the next step can guard on the hash this one printed.
    @Test
    func aStepRemembersItsAfterScreenSoTheNextGuardOnItsHashHolds() throws {
        let black = try PixelSignatureTests.png()
        let nudged = try PixelSignatureTests.png(whiteTopFraction: 0.05)
        var stepper = LiveSessionStepper(quiet: 0.25)
        let source = CountingTreeSource(tree: Self.canvas)
        // Step 1 reads black before and after; step 2 finds the canvas nudged.
        source.pictures = [black, black, nudged]
        let first = try step(&stepper, on: source, of: Self.canvas, guardHash: nil)
        let printed = try ScreenHash.of(Self.canvas, pixels: #require(first.screen?.pixels))

        let second = try step(&stepper, on: source, of: Self.canvas, guardHash: printed)

        #expect(second.step?.outcome == .landed)
        #expect(try #require(second.step?.pixelsMoved) <= PixelSignature.guardTolerance)
    }

    @Test
    func aHashTheSessionNeverPrintedIsRefusedWithNoPictureComparedAndATreeWithTextStillNeedsTheExactHash() throws {
        let black = try PixelSignatureTests.png()
        let nudged = try PixelSignatureTests.png(whiteTopFraction: 0.05)
        var (stepper, _) = try stepperThatRead(Self.canvas, black)
        let source = CountingTreeSource(tree: Self.canvas)
        source.pictures = [nudged]
        let refused = try step(&stepper, on: source, of: Self.canvas, guardHash: "00000000")
        #expect(refused.step?.outcome == .snapshotChanged)
        #expect(refused.step?.pixelsMoved == nil)

        var other = LiveSessionStepper(quiet: 0.25)
        other.remember(Self.screen(Self.home))
        let text = CountingTreeSource(tree: Self.home)
        let stale = try step(&other, on: text, of: Self.home, guardHash: "00000000")
        #expect(stale.step == .snapshotChanged(expected: "00000000", found: ScreenHash.of(Self.home)))
    }

    @Test
    func theSessionRemembersTheLast32TextlessHashesAndDropsTheOldest() throws {
        let black = try PixelSignatureTests.png()
        let nudged = try PixelSignatureTests.png(whiteTopFraction: 0.05)
        func tree(_ i: Int) -> AXNode {
            AXNode(type: "Application", frame: Self.screenFrame, children: [AXNode(type: "Other", frame: AXNode.Frame(x: Double(i), y: 0, width: 402, height: 874))])
        }
        var (stepper, first) = try stepperThatRead(tree(0), black)
        let source = CountingTreeSource(tree: tree(0))
        source.pictures = [nudged]
        var kept = stepper
        #expect(try step(&kept, on: source, of: tree(0), guardHash: first).step?.outcome == .landed)

        for i in 1 ..< LiveSessionStepper.memory {
            try stepper.remember(Self.screen(tree(i), pixels: PixelSignatureTests.signature(black)))
        }
        kept = stepper
        #expect(try step(&kept, on: source, of: tree(0), guardHash: first).step?.outcome == .landed)
        try stepper.remember(Self.screen(tree(LiveSessionStepper.memory), pixels: PixelSignatureTests.signature(black)))
        let forgotten = try step(&stepper, on: source, of: tree(0), guardHash: first)
        #expect(forgotten.step?.outcome == .snapshotChanged)
        #expect(forgotten.step?.pixelsMoved == nil)
    }

    /// SimWalk#150: the before-hash comes from the injected picture source (the runner's one function, shared with a read), never from the screen source's own screenshot, which can be the device's grid in another orientation.
    @Test
    func theBeforeHashTakesItsPictureFromTheInjectedSourceAndNotTheScreensOwn() throws {
        let black = try PixelSignatureTests.png()
        let half = try PixelSignatureTests.png(whiteTopFraction: 0.5)
        let source = CountingTreeSource(tree: Self.canvas)
        source.pictures = [black]
        var asked = 0
        var stepper = LiveSessionStepper(quiet: 0.25)

        let response = try stepper.answer(
            LiveSessionRequest(n: 1, action: .step, step: .tapPoint(label: nil, point: [200, 400]), guardHash: "00000000"),
            screen: source,
            sheetReads: CountingTreeSource(tree: Self.canvas),
            pixels: { _ in
                asked += 1
                return PixelSignature(png: half)
            },
            perform: { _, _ in .landed(.tapPoint(label: nil, point: [200, 400]), sheetClosed: false, bound: nil) },
            read: { Self.screen(Self.canvas) }
        )

        #expect(asked == 1)
        #expect(source.screenshots == 0)
        #expect(try response.step == .snapshotChanged(expected: "00000000", found: ScreenHash.of(Self.canvas, pixels: PixelSignatureTests.signature(half))))
    }

    @Test
    func aTreeWithTextTakesNoScreenshotAndAnswersAsBefore() throws {
        var stepper = LiveSessionStepper(quiet: 0.25)
        let source = CountingTreeSource(tree: Self.home)

        let response = try stepper.answer(
            LiveSessionRequest(n: 1, action: .step, step: .tap(label: "First"), guardHash: ScreenHash.of(Self.home)),
            screen: source,
            sheetReads: CountingTreeSource(tree: Self.home),
            pixels: { _ in nil },
            perform: { _, _ in .landed(.tap(label: "First"), sheetClosed: false, bound: nil) },
            read: { Self.screen(Self.detail) }
        )

        #expect(source.screenshots == 0)
        #expect(response.step == .landed(.tap(label: "First"), delta: ScreenDelta(from: Self.home, to: Self.detail)))
        #expect(response.step?.delta?.pixelsChanged == nil)
    }

    @Test
    func aReadWrittenBeforeThePixelsExistedStillDecodes() throws {
        let withPixels = try Self.screen(Self.canvas, pixels: PixelSignature(png: PixelSignatureTests.png()))
        let data = try CaptureBundle.encoder().encode(withPixels)
        var object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["pixels"] != nil)
        object["pixels"] = nil

        let decoded = try CaptureBundle.decoder().decode(LiveScreen.self, from: JSONSerialization.data(withJSONObject: object))

        #expect(decoded.pixels == nil)
        #expect(decoded == Self.screen(Self.canvas))
    }

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

    static func screen(_ tree: AXNode, pixels: PixelSignature? = nil) -> LiveScreen {
        LiveScreen(
            appBundleID: "dev.simwalk.route-fixture",
            device: CaptureManifest.Device(name: "iPhone 17", udid: "UDID-1", osVersion: "27.0"),
            runnerCommit: nil,
            readAt: Date(timeIntervalSince1970: 0),
            nonce: "s1",
            appState: .foreground,
            tree: tree,
            settled: true,
            screenPixels: nil,
            pixels: pixels
        )
    }

    /// A screen that counts its reads, on a clock that moves only when it is paused.
    final class CountingTreeSource: CaptureSource {
        private let trees: [AXNode]
        private let rest: AXNode
        private(set) var reads = 0
        /// The pictures `screenshot()` returns in turn, the last for ever; how many it was asked for is `screenshots`.
        var pictures: [Data] = []
        private(set) var screenshots = 0
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

        func springboardTree() throws -> AXNode {
            AXNode(type: "Application", frame: LiveSessionStepTests.screenFrame)
        }

        func screenshot() -> Data {
            screenshots += 1
            return pictures.isEmpty ? Data() : pictures[min(screenshots, pictures.count) - 1]
        }

        func elapsed() -> TimeInterval {
            clock
        }

        func pause(_ interval: TimeInterval) {
            clock += interval
        }
    }
}
