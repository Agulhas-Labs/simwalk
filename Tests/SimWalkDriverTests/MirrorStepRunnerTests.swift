//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// A whole mirror call replayed over scripted seams: the order of guard, window, reads and event, the settle loop's waits, and what is left on disk.
///
/// No event is posted and nothing is captured from a screen.
struct MirrorStepRunnerTests {
    private static let window = MirrorWindowFrame(windowID: 7, x: 0, y: 0, width: 383, height: 843)
    private static let utc = TimeZone(identifier: "UTC") ?? .gmt

    private let point: MirrorFraction

    init() throws {
        point = try MirrorFraction(x: 0.5, y: 0.5)
    }

    private func runner(_ script: MirrorStepScript, _ directory: TemporaryDirectory) -> MirrorStepRunner {
        MirrorStepRunner(
            seams: script.seams,
            store: MirrorCaptureStore(directory: directory.url.appendingPathComponent("captures")),
            lock: script.lock(directory.url)
        )
    }

    private func pngs(_ directory: TemporaryDirectory) -> [String] {
        let root = directory.url.appendingPathComponent("captures")
        let kept = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        let scratch = (try? FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent(".scratch").path)) ?? []
        return kept.filter { $0 != ".scratch" } + scratch.map { ".scratch/\($0)" }
    }

    /// A refused guard stops the call before anything: no window lookup, no capture, no event, nothing on disk, and the lock free again.
    @Test
    func aGuardRefusalDoesNothingAndReleasesTheLock() throws {
        let directory = try TemporaryDirectory()
        let script = MirrorStepScript(reads: [], clearError: MirrorFocusRefusal(frontmost: "Terminal", moment: .beforeAction))

        #expect(throws: MirrorFocusRefusal(frontmost: "Terminal", moment: .beforeAction)) {
            _ = try runner(script, directory).run(.tap(point))
        }
        #expect(script.log == ["clear"])
        #expect(pngs(directory).isEmpty)
        #expect(script.lockIsFree(directory.url))
    }

    /// The window is looked up after the guard, and the lock is held from the first step to the last.
    @Test
    func theWindowIsLookedUpAfterTheGuardUnderTheLock() throws {
        let directory = try TemporaryDirectory()
        let script = MirrorStepScript(reads: [MirrorStepScript.screen(["A"]), MirrorStepScript.screen(["B"]), MirrorStepScript.screen(["B"])])

        _ = try runner(script, directory).run(.tap(point))

        #expect(Array(script.log.prefix(2)) == ["clear", "window"])
        #expect(script.lockHeldAtEveryStep)
        #expect(script.lockIsFree(directory.url))
    }

    /// Before-read, event, then reads every 250 ms with the elapsed time since the event: the screen that changed and then held settles on the second agreeing read.
    @Test
    func theSettleLoopReadsEveryQuarterSecond() throws {
        let directory = try TemporaryDirectory()
        let script = MirrorStepScript(reads: [MirrorStepScript.screen(["A"]), MirrorStepScript.screen(["B"]), MirrorStepScript.screen(["C"]), MirrorStepScript.screen(["C"])])

        let observation = try runner(script, directory).run(.tap(point))

        #expect(script.log == ["clear", "window", "capture", "read", "recheck action", "perform tap .50,.50", "pause 0.25", "capture", "read", "pause 0.25", "capture", "read", "pause 0.25", "capture", "read"])
        #expect(observation.reads == 3)
        #expect(observation.millisecondsToRead == 750)
        #expect(observation.reason == nil)
        #expect(observation.read.lines.map(\.text).contains("C"))
        #expect(observation.before?.lines.map(\.text).contains("A") == true)
    }

    /// Focus lost during the before-read refuses at the read just before the event: the guard's clearance is never posted on, and nothing is.
    @Test
    func focusLostAfterTheBeforeReadPostsNothing() throws {
        let directory = try TemporaryDirectory()
        let script = MirrorStepScript(reads: [MirrorStepScript.screen(["A"])], actionRecheckFrontmost: "Safari")

        #expect(throws: MirrorFocusRefusal(frontmost: "Safari", moment: .beforeAction)) {
            _ = try runner(script, directory).run(.tap(point))
        }
        #expect(script.log == ["clear", "window", "capture", "read", "recheck action"])
        #expect(!script.log.contains { $0.hasPrefix("perform") })
        #expect(pngs(directory).isEmpty)
    }

    /// A tap in a rounded corner of the screen is refused once the window is known, before the before-read spends a capture on it.
    @Test
    func aCornerTapIsRefusedBeforeAnyCapture() throws {
        let directory = try TemporaryDirectory()
        let script = MirrorStepScript(reads: [MirrorStepScript.screen(["A"])])
        let corner = try MirrorFraction(x: 0.97, y: 0.98)

        #expect(throws: MirrorWindowFrame.PassThrough(fraction: corner)) {
            _ = try runner(script, directory).run(.tap(corner))
        }
        #expect(script.log == ["clear", "window"])
    }

    /// A scratch file a killed call left behind is gone once the next call has run, and the store's directory holds only what was kept.
    @Test
    func aKilledCallsScratchIsClearedByTheNext() throws {
        let directory = try TemporaryDirectory()
        let scratch = directory.url.appendingPathComponent("captures/.scratch", isDirectory: true)
        try FileManager.default.createDirectory(at: scratch, withIntermediateDirectories: true)
        try Data("x".utf8).write(to: scratch.appendingPathComponent("left-by-a-killed-call.png"))
        let script = MirrorStepScript(reads: [MirrorStepScript.screen(["A"]), MirrorStepScript.screen(["A"])])

        _ = try runner(script, directory).run(nil)

        #expect(pngs(directory).count == 1)
        #expect(pngs(directory).allSatisfy { !$0.hasPrefix(".scratch/") })
    }

    /// A screen that never changes is answered at the bound as no visible change, after exactly the reads that reach it.
    @Test
    func aScreenThatNeverChangesIsQualifiedAtTheBound() throws {
        let directory = try TemporaryDirectory()
        let same = MirrorStepScript.screen(["A"])
        let script = MirrorStepScript(reads: [same, same, same, same])

        let observation = try runner(script, directory).run(.tap(point), settleMilliseconds: 500)

        #expect(observation.reason == .noVisibleChange)
        #expect(observation.reads == 2)
        #expect(script.log.filter { $0.hasPrefix("pause") }.count == 2)
    }

    /// Only the served capture is kept, under its action's name; the before-read and the intermediate ones are gone, and the served read's path is the kept file.
    @Test
    func onlyTheServedCaptureIsKept() throws {
        let directory = try TemporaryDirectory()
        let script = MirrorStepScript(reads: [MirrorStepScript.screen(["A"]), MirrorStepScript.screen(["B"]), MirrorStepScript.screen(["B"])])

        let observation = try runner(script, directory).run(.menu(.homeScreen))
        let left = pngs(directory)

        #expect(left.count == 1)
        #expect(left.first?.hasSuffix("-menu-home-screen.png") == true)
        #expect(observation.read.path.lastPathComponent == left.first)
        #expect(FileManager.default.fileExists(atPath: observation.read.path.path))
    }

    /// An OCR failure mid-loop leaves nothing behind: no scratch capture, no kept one, and the lock free.
    @Test
    func aReadFailureLeavesNothingOnDisk() throws {
        let directory = try TemporaryDirectory()
        let script = MirrorStepScript(reads: [MirrorStepScript.screen(["A"]), MirrorStepScript.screen(["B"])], failingReadNumber: 3)

        #expect(throws: MirrorStepScript.ReadFailure()) {
            _ = try runner(script, directory).run(.tap(point))
        }
        #expect(pngs(directory).isEmpty)
        #expect(script.lockIsFree(directory.url))
    }

    /// A plain `read` has no before-read and no event: it settles on two agreeing reads.
    @Test
    func aReadHasNoBeforeRead() throws {
        let directory = try TemporaryDirectory()
        let script = MirrorStepScript(reads: [MirrorStepScript.screen(["A"]), MirrorStepScript.screen(["A"])])

        let observation = try runner(script, directory).run(nil)

        #expect(script.log == ["clear", "window", "pause 0.25", "capture", "read", "pause 0.25", "capture", "read"])
        #expect(observation.before == nil)
        #expect(observation.label == "read")
        #expect(observation.reads == 2)
    }

    /// A burst whose third focus check fails keeps its two frames, records the refusal, and reads only after the last capture.
    @Test
    func aBurstStopsAtTheFirstFailedFrameCheck() throws {
        let directory = try TemporaryDirectory()
        let refusal = MirrorFocusRefusal(frontmost: "Safari", moment: .beforeFrame(3))
        let script = MirrorStepScript(reads: [MirrorStepScript.screen(["A"]), MirrorStepScript.screen(["B"])], recheckRefusalAt: 3)

        let burst = try runner(script, directory).burst(at: point, frames: 5)

        #expect(burst.stoppedBy == refusal)
        #expect(burst.frames.map(\.index) == [1, 2])
        #expect(script.log == ["clear", "window", "recheck action", "perform tap .50,.50", "recheck 1", "capture", "recheck 2", "capture", "recheck 3", "read", "read"])
        #expect(burst.frames.allSatisfy { FileManager.default.fileExists(atPath: $0.read.path.path) })
        #expect(script.lockIsFree(directory.url))
    }

    /// A burst that fails to read a frame leaves no directory behind.
    @Test
    func aFailedBurstRemovesItsDirectory() throws {
        let directory = try TemporaryDirectory()
        let script = MirrorStepScript(reads: [MirrorStepScript.screen(["A"])], failingReadNumber: 2)

        #expect(throws: MirrorStepScript.ReadFailure()) {
            _ = try runner(script, directory).burst(at: point, frames: 3)
        }
        #expect(pngs(directory).isEmpty)
    }
}
