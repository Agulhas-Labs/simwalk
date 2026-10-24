//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkDriver
import SimWalkTestSupport
import Testing

/// SimWalk#187: an interruption waits, bounded, for a device handback already under way before it gives the devices back, and refuses a walk that has not yet touched its device.
///
/// Each cancel is raised on a thread of its own, as the signal's queue raises it: the walk's thread is the one that must reach the handback, so a cancel raised on it would wait on itself.
struct HandbackGateTests {
    @Test
    func aGateWithNobodyInsideClosesAndReturnsAtOnce() {
        let gate = HandbackGate()

        #expect(gate.close().isEmpty)
        #expect(gate.wait(upTo: 60).isEmpty)
    }

    @Test
    func leavingTwiceGivesUpOnePlaceOnly() throws {
        let gate = HandbackGate()
        let first = try gate.enter("UDID-1")
        _ = try gate.enter("UDID-2")

        first.leave()
        first.leave()

        #expect(gate.close() == ["UDID-2"])
    }

    @Test
    func aClosedGateRefusesEntryAsTheWalksStop() throws {
        let gate = HandbackGate()
        _ = gate.close()

        let error = #expect(throws: ShellError.self) { _ = try gate.enter("UDID-1") }

        #expect(try WalkCommand.isStop(#require(error)))
    }

    @Test
    func theWaitEndsWhenTheLastWalkInsideLeaves() throws {
        let gate = HandbackGate()
        let entry = try gate.enter("UDID-1")
        #expect(gate.close() == ["UDID-1"])

        DispatchQueue.global().asyncAfter(deadline: .now() + 0.1) { entry.leave() }

        #expect(gate.wait(upTo: 60).isEmpty)
    }

    @Test
    func theWaitEndsAtItsBoundNamingTheWalksStillInside() throws {
        let gate = HandbackGate()
        _ = try gate.enter("UDID-1")
        _ = gate.close()
        let started = Date()

        #expect(gate.wait(upTo: 0.2) == ["UDID-1"])
        #expect(Date().timeIntervalSince(started) >= 0.2)
    }

    /// The cancel returns only once the serial walk has put the appearance and accessibility back, and those calls ran while the lease and the claim were still held.
    ///
    /// The runner waits a moment after the stop before it ends, so a cancel that did not wait returns, and gives the device back, before the handback starts.
    @Test
    func anInterruptionDuringASerialWalksRunnerWaitsForItsHandbackWhileTheDeviceIsHeld() throws {
        let walk = try SerialWalk()
        let returned = DispatchSemaphore(value: 0)
        let shell = Shell { executable, arguments, environment in
            walk.record(arguments)
            if arguments.contains("test-without-building") {
                Thread.detachNewThread { [walk] in
                    walk.interruption.cancel()
                    walk.cancelReturned()
                    returned.signal()
                }
                SerialWalk.waitUntil(60) { walk.childStop.isStopped }
                SerialWalk.waitUntil(1) { walk.hasCancelReturned }
                throw ShellError.stopped
            }
            return try walk.script.run(executable, arguments, environment)
        }

        _ = try? walk.perform(on: shell)

        #expect(returned.wait(timeout: .now() + 60) == .success)
        let handedBack = walk.callsBeforeCancelReturned.filter { call in
            call.arguments == ["simctl", "ui", "UDID-1", "appearance", "light"] || call.arguments.contains("write")
        }
        #expect(handedBack.contains { $0.arguments.contains("appearance") })
        #expect(handedBack.contains { $0.arguments.contains("write") })
        let heldThroughout = handedBack.allSatisfy(\.held)
        #expect(heldThroughout)
    }

    /// A handback that hangs holds the cancel up only as long as the bound: then the device is named as not handed back, and its lease and claim are given back all the same.
    @Test
    func anInterruptionWaitsNoLongerThanItsBoundForAHandbackThatHangs() throws {
        let walk = try SerialWalk()
        let returned = DispatchSemaphore(value: 0)
        let shell = Shell { executable, arguments, environment in
            walk.record(arguments)
            if arguments.contains("test-without-building") {
                Thread.detachNewThread { [walk] in
                    walk.interruption.cancel()
                    walk.cancelReturned()
                    returned.signal()
                }
                SerialWalk.waitUntil(60) { walk.childStop.isStopped }
                throw ShellError.stopped
            }
            if arguments == ["simctl", "ui", "UDID-1", "appearance", "light"] {
                // Hangs until the cancel has returned; the hang guard ends a run in which it never does.
                SerialWalk.waitUntil(60) { walk.hasCancelReturned }
            }
            return try walk.script.run(executable, arguments, environment)
        }

        _ = try? walk.perform(on: shell, handbackBound: 0.2)

        #expect(returned.wait(timeout: .now() + 60) == .success)
        let waited = try #require(walk.cancelDuration)
        #expect(waited >= 0.2 && waited < 30)
        #expect(walk.notes == ["⚠ interrupted — handing the device back before exiting", "⚠ interrupted — handback not finished: UDID-1"])
        #expect(walk.heldWhenCancelReturned == false)
    }

    /// A walk whose device the interruption reached before the walk touched it — here, while `prepare` built the runner — is refused as the walk's stop and runs nothing on the device.
    @Test
    func aWalkStartingAfterTheInterruptionIsRefusedAsTheStopAndTouchesNothing() throws {
        let walk = try SerialWalk()
        let built = Built()
        let shell = Shell { executable, arguments, environment in
            walk.record(arguments)
            let result = try walk.script.run(executable, arguments, environment)
            if arguments.contains("build-for-testing") {
                // Nothing is inside the gate yet, so the cancel waits on nothing, even raised here.
                walk.interruption.cancel()
                built.mark(after: walk.callCount)
            }
            return result
        }

        let error = #expect(throws: (any Error).self) { try walk.perform(on: shell) }

        #expect(try WalkCommand.isStop(#require(error)))
        let after = try #require(built.callCount)
        #expect(walk.calls.dropFirst(after).isEmpty)
        #expect(walk.notes.isEmpty)
    }

    /// SimWalk#201: a first runner that returns, with a state refused on appearance, once the interruption has stopped the walk starts no appearance retry — no set-dark, no reboot, no second runner — while the handler waits on its handback with the lease still held, and the handback runs as before.
    ///
    /// The bound is the default one: a zero bound gives the lease back at once, and the retry's lease renewal would then refuse the settle with or without the fix.
    @Test
    func aWalkStoppedByTheInterruptionStartsNoAppearanceRetry() throws {
        let walk = try SerialWalk(refusingDark: true)
        let returned = DispatchSemaphore(value: 0)
        let shell = Shell { executable, arguments, environment in
            walk.record(arguments)
            if arguments.contains("test-without-building"), walk.calls.count(where: { $0.contains("test-without-building") }) == 1 {
                Thread.detachNewThread { [walk] in
                    walk.interruption.cancel()
                    walk.cancelReturned()
                    returned.signal()
                }
                // Written after both stops, so the walk resumes with the interruption's stop already raised.
                SerialWalk.waitUntil(60) { walk.notes.contains("⚠ interrupted — handing the device back before exiting") }
            }
            return try walk.script.run(executable, arguments, environment)
        }

        _ = try? walk.perform(on: shell)

        #expect(returned.wait(timeout: .now() + 60) == .success)
        let calls = walk.calls
        let runner = try #require(calls.firstIndex { $0.contains("test-without-building") })
        #expect(calls.count { $0.contains("test-without-building") } == 1)
        let afterRunner = calls.dropFirst(runner + 1)
        #expect(!afterRunner.contains(["simctl", "ui", "UDID-1", "appearance", "dark"]))
        #expect(!afterRunner.contains(["simctl", "shutdown", "UDID-1"]))
        #expect(!afterRunner.contains(["simctl", "boot", "UDID-1"]))
        let handedBack = walk.callsBeforeCancelReturned.filter { $0.arguments == ["simctl", "ui", "UDID-1", "appearance", "light"] }
        #expect(!handedBack.isEmpty)
        let heldThroughout = handedBack.allSatisfy(\.held)
        #expect(heldThroughout)
    }
}

extension HandbackGateTests {
    /// A serial walk of one screen on `UDID-1` — or, refusing dark, of `progress` in light and dark and `browse`, whose first pass refuses `progress`'s dark state on appearance — interrupted as each test says, recording each call it makes and whether the device was still leased and claimed then.
    final class SerialWalk: @unchecked Sendable {
        let directory: TemporaryDirectory
        /// Where the appearance retry's second pass is written from, kept alive as long as the walk.
        let retryDirectory: TemporaryDirectory
        let leases: LeaseStore
        let script: WalkCommandTests.WalkScript
        let command: WalkCommand
        let interruption = Cancellation()
        let childStop = ChildStop()
        private let lock = NSLock()
        private var recorded: [(arguments: [String], held: Bool)] = []
        private var returnedAt: Int?
        private var cancelStarted: Date?
        private var cancelEnded: Date?
        private var heldAtReturn: Bool?
        private var written: [String] = []

        init(refusingDark: Bool = false) throws {
            (directory, retryDirectory) = try (TemporaryDirectory(), TemporaryDirectory())
            leases = WalkCommandTests.leases(in: directory)
            guard refusingDark else {
                let writes = try WalkCommandTests.runnerWrites(in: directory)
                script = try WalkCommandTests.WalkScript(appPath: WalkCommandTests.fakeApp(in: directory), runnerStatus: 0, writes: writes)
                command = try WalkCommand.parse([WalkCommandTests.walkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])
                return
            }
            let writes = try (bundle: WalkCommandTests.refusingDark(in: directory).url, to: directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)"))
            script = try WalkCommandTests.WalkScript(
                appPath: WalkCommandTests.fakeApp(in: directory), runnerStatus: 0, writes: writes,
                retryWrites: WalkCommandTests.progressAgain(in: retryDirectory, refusingDark: false).url
            )
            command = try WalkCommand.parse([WalkCommandTests.lightAndDarkWalkbook(in: directory), "--output", writes.to.path, "--device", "UDID-1"])
        }

        func perform(on shell: Shell, handbackBound: TimeInterval = HandbackGate.interruptionBound) throws {
            _ = try command.performWalk(
                shell: shell, pause: { _ in }, now: script.now, runner: { WalkCommandTests.runner }, builds: WalkCommandTests.builds(in: directory), leases: leases,
                interruption: interruption, childStop: childStop, handbackBound: handbackBound, interruptionNote: { [self] line in lock.withLock { written.append(line) } }
            )
        }

        /// Whether `UDID-1` is leased and claimed right now.
        var isHeld: Bool {
            leases.all().map(\.udid).contains("UDID-1") && WalkClaim.walkedDevices(in: leases, isAlive: HolderProcess.isAlive).contains("UDID-1")
        }

        func record(_ arguments: [String]) {
            let held = isHeld
            lock.withLock {
                recorded.append((arguments, held))
                if arguments.contains("test-without-building") {
                    cancelStarted = Date()
                }
            }
        }

        func cancelReturned() {
            let held = isHeld
            lock.withLock {
                returnedAt = recorded.count
                cancelEnded = Date()
                heldAtReturn = held
            }
        }

        var hasCancelReturned: Bool {
            lock.withLock { returnedAt != nil }
        }

        var calls: [[String]] {
            lock.withLock { recorded.map(\.arguments) }
        }

        var callCount: Int {
            lock.withLock { recorded.count }
        }

        var callsBeforeCancelReturned: [(arguments: [String], held: Bool)] {
            lock.withLock { Array(recorded.prefix(returnedAt ?? 0)) }
        }

        var cancelDuration: TimeInterval? {
            lock.withLock { cancelEnded.flatMap { end in cancelStarted.map { end.timeIntervalSince($0) } } }
        }

        var heldWhenCancelReturned: Bool? {
            lock.withLock { heldAtReturn }
        }

        var notes: [String] {
            lock.withLock { written }
        }

        /// Polls `condition` until it holds or `bound` seconds pass: a hang guard where a test expects the condition, a grace where it expects it not to come.
        static func waitUntil(_ bound: TimeInterval, _ condition: () -> Bool) {
            let deadline = Date().addingTimeInterval(bound)
            while !condition(), Date() < deadline {
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
    }

    /// How many calls the walk had made once its runner was built.
    final class Built: @unchecked Sendable {
        private let lock = NSLock()
        private var count: Int?

        func mark(after count: Int) {
            lock.withLock { self.count = count }
        }

        var callCount: Int? {
            lock.withLock { count }
        }
    }
}
