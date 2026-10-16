//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkDriver
import Testing

/// `simwalk mirror …` against a fake stepper: no window, no events, no capture — what each verb hands the driver, what it answers, and the exit code a lost focus earns.
struct MirrorCommandTests {
    @Test
    func readHandsTheDriverNoActionAndPassesItsAnswerThrough() throws {
        let fake = FakeStepper()
        let command = try MirrorReadCommand.parse(["--settle-ms", "500", "--match", "row"])

        let answer = try command.perform(makeStepper: fake.factory, timeZone: .gmt)

        #expect(fake.actions.count == 1)
        #expect(fake.actions[0] == nil)
        #expect(fake.settles == [500])
        #expect(answer.text.contains("Rowing"))
    }

    @Test
    func tapHandsTheDriverTheFraction() throws {
        let fake = FakeStepper()
        let command = try MirrorTapCommand.parse(["0.25", "0.75"])

        _ = try command.perform(makeStepper: fake.factory)

        #expect(try fake.actions == [.tap(MirrorFraction(x: 0.25, y: 0.75))])
        #expect(fake.settles == [3000])
    }

    @Test
    func aFractionOutsideTheWindowIsRefusedNamingTheValueAndNothingIsRun() throws {
        let fake = FakeStepper()
        let command = try MirrorTapCommand.parse(["1.5", "0.5"])

        let thrown = try #require(#expect(throws: MirrorFraction.OutOfRange.self) {
            try command.perform(makeStepper: fake.factory)
        })

        #expect(thrown.description.contains("1.5"))
        #expect(fake.actions.isEmpty)
    }

    @Test
    func swipeHandsTheDriverBothEndsAndTheDuration() throws {
        let fake = FakeStepper()
        let defaulted = try MirrorSwipeCommand.parse(["0.5", "0.8", "0.5", "0.2"])
        let slow = try MirrorSwipeCommand.parse(["0.5", "0.8", "0.5", "0.2", "--ms", "900"])

        _ = try defaulted.perform(makeStepper: fake.factory)
        _ = try slow.perform(makeStepper: fake.factory)

        let start = try MirrorFraction(x: 0.5, y: 0.8)
        let end = try MirrorFraction(x: 0.5, y: 0.2)

        #expect(fake.actions == [.swipe(from: start, to: end, milliseconds: 350), .swipe(from: start, to: end, milliseconds: 900)])
    }

    @Test
    func scrollDefaultsToTheCentreAndTakesANegativeCountAfterTheTerminator() throws {
        let fake = FakeStepper()
        let down = try MirrorScrollCommand.parse(["5"])
        let left = try MirrorScrollCommand.parse(["--horizontal", "--at", "0.2,0.9", "--", "-3"])

        _ = try down.perform(makeStepper: fake.factory)
        _ = try left.perform(makeStepper: fake.factory)

        #expect(try fake.actions == [
            .scroll(lines: 5, horizontal: false, position: MirrorFraction(x: 0.5, y: 0.5)),
            .scroll(lines: -3, horizontal: true, position: MirrorFraction(x: 0.2, y: 0.9)),
        ])
    }

    @Test
    func scrollRefusesAnAtThatIsNotTwoFractions() throws {
        let fake = FakeStepper()
        let command = try MirrorScrollCommand.parse(["2", "--at", "0.5"])

        #expect(throws: InputRefusal.self) { try command.perform(makeStepper: fake.factory) }
        #expect(fake.actions.isEmpty)
    }

    @Test
    func scrollRefusesALineCountOutsideOneToFiftyEitherWay() throws {
        let fake = FakeStepper()

        for lines in ["0", "51", "-51", "100000", "9999999999"] {
            let command = try MirrorScrollCommand.parse(["--", lines])
            let refusal = #expect(throws: InputRefusal.self) { try command.perform(makeStepper: fake.factory) }
            #expect(refusal.map(UsageFailureKind.of) == .inputRefused)
        }
        _ = try MirrorScrollCommand.parse(["--", "-50"]).perform(makeStepper: fake.factory)
        _ = try MirrorScrollCommand.parse(["1"]).perform(makeStepper: fake.factory)

        #expect(fake.actions.count == 2)
    }

    @Test
    func swipeRefusesADurationOutsideFiftyToFiveThousand() throws {
        let fake = FakeStepper()

        for ms in ["0", "49", "5001", "600000"] {
            let command = try MirrorSwipeCommand.parse(["0.5", "0.8", "0.5", "0.2", "--ms", ms])
            let refusal = #expect(throws: InputRefusal.self) { try command.perform(makeStepper: fake.factory) }
            #expect(refusal.map(UsageFailureKind.of) == .inputRefused)
        }
        _ = try MirrorSwipeCommand.parse(["0.5", "0.8", "0.5", "0.2", "--ms", "50"]).perform(makeStepper: fake.factory)
        _ = try MirrorSwipeCommand.parse(["0.5", "0.8", "0.5", "0.2", "--ms", "5000"]).perform(makeStepper: fake.factory)

        #expect(fake.actions.count == 2)
    }

    @Test
    func menuHomeAnswersAsIsAndSwitcherAddsTheTwiceResidue() throws {
        let fake = FakeStepper()

        let home = try MirrorMenuCommand.parse(["home"]).perform(makeStepper: fake.factory)
        let switcher = try MirrorMenuCommand.parse(["switcher"]).perform(makeStepper: fake.factory)

        #expect(fake.actions == [.menu(.homeScreen), .menu(.appSwitcher)])
        #expect(!home.text.contains("send it twice"))
        #expect(switcher.residue.last == "next: 'menu home' from the App Switcher lands in the last app first — send it twice")
        #expect(throws: InputRefusal.self) { try MirrorMenuCommand.parse(["dock"]).perform(makeStepper: fake.factory) }
    }

    @Test
    func outChoosesTheDirectoryItIsGiven() throws {
        let fake = FakeStepper()

        _ = try MirrorReadCommand.parse(["--out", "/tmp/kept-here"]).perform(makeStepper: fake.factory)

        #expect(fake.store?.directory.path == "/tmp/kept-here")
    }

    @Test
    func burstPassesItsPointAndFramesAndNamesTheSheetOnlyWhenAsked() throws {
        let fake = FakeStepper()
        let sheet = URL(fileURLWithPath: "/tmp/burst-dir/sheet.png")

        let noSheet: (MirrorBurst) throws -> URL? = { _ in
            Issue.record("no sheet was asked for")
            return nil
        }
        let writeSheet: (MirrorBurst) throws -> URL? = { _ in sheet }
        let plainCommand = try MirrorBurstCommand.parse(["0.5", "0.5", "--frames", "8"])
        let sheetedCommand = try MirrorBurstCommand.parse(["0.5", "0.5", "--frames", "8", "--sheet"])

        let plain = try plainCommand.perform(makeStepper: fake.factory, makeSheet: noSheet)
        let sheeted = try sheetedCommand.perform(makeStepper: fake.factory, makeSheet: writeSheet)

        #expect(fake.bursts.map(\.1) == [8, 8])
        #expect(!plain.text.contains("sheet "))
        #expect(sheeted.residue[1] == "sheet /tmp/burst-dir/sheet.png")
    }

    @Test
    func burstRefusesFramesOutsideOneToSixty() throws {
        let fake = FakeStepper()

        for frames in ["0", "61"] {
            let command = try MirrorBurstCommand.parse(["0.5", "0.5", "--frames", frames])
            #expect(throws: InputRefusal.self) { try command.perform(makeStepper: fake.factory) }
        }

        #expect(fake.bursts.isEmpty)
    }

    /// Lost focus is the one refusal a caller retries, so it alone exits 3.
    @Test
    func aLostFocusExitsThreeAndAnyOtherRefusalExitsOne() throws {
        let recorder = StreamRecorder()
        let focus = MirrorFocusRefusal(frontmost: "Safari", moment: .beforeAction)

        let lost = try #require(#expect(throws: ExitCode.self) {
            try TimedCall.run(tool: "mirror tap", target: nil, log: nil, emit: recorder.emit, emitError: recorder.emitError, defaultFailureKind: .toolError, isStdoutPiped: Self.notPiped) { throw focus }
        })
        let other = try #require(#expect(throws: ExitCode.self) {
            try TimedCall.run(tool: "mirror tap", target: nil, log: nil, emit: recorder.emit, emitError: recorder.emitError, defaultFailureKind: .toolError, isStdoutPiped: Self.notPiped) { throw MirrorControlError.noWindow }
        })

        #expect(lost == ExitCode(3))
        #expect(other == ExitCode(1))
        #expect(recorder.err.first == "refused — \(focus.description)")
        #expect(recorder.err.first?.contains("Safari") == true)
    }
}

extension MirrorCommandTests {
    /// Stdout is not a pipe, so no pipe-status nudge is added to stderr.
    static func notPiped() -> Bool {
        false
    }

    /// Records what it was asked and answers a fixed screen.
    final class FakeStepper: MirrorStepping {
        private(set) var actions: [MirrorAction?] = []
        private(set) var settles: [Int] = []
        private(set) var bursts: [(MirrorFraction, Int)] = []
        private(set) var store: MirrorCaptureStore?

        func run(_ action: MirrorAction?, settleMilliseconds: Int) throws -> MirrorObservation {
            actions.append(action)
            settles.append(settleMilliseconds)
            return MirrorObservation(action: action, window: Self.window, before: nil, read: Self.read, reason: nil, eventAt: Date(timeIntervalSince1970: 0), reads: 1, boundMilliseconds: settleMilliseconds)
        }

        func burst(at point: MirrorFraction, frames: Int) throws -> MirrorBurst {
            bursts.append((point, frames))
            let frame = MirrorBurst.Frame(index: 1, millisecondsSinceTap: 120, read: Self.read)
            return MirrorBurst(point: point, window: Self.window, requested: frames, frames: [frame], stoppedBy: nil, directory: URL(fileURLWithPath: "/tmp/burst-dir"))
        }

        static let window = MirrorWindowFrame(windowID: 1, x: 0, y: 0, width: 300, height: 650)

        static let read = MirrorRead(
            path: URL(fileURLWithPath: "/tmp/x.png"), pixelSize: nil, capturedAt: Date(timeIntervalSince1970: 0),
            lines: [MirrorTextLine(text: "Rowing", centreX: 0.5, centreY: 0.3, width: 0.3, height: 0.02, confidence: 0.9)]
        )

        /// A stepper factory that remembers the store it was handed and always returns this fake.
        func factory(_ store: MirrorCaptureStore) -> any MirrorStepping {
            self.store = store
            return self
        }
    }
}
