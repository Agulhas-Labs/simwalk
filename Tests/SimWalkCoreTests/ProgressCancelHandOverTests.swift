//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// A cancel across the hand-over (SimWalk#83): two writers on one file, the host's and the runner's, each read back from disk straight after the runner's write — before any host `reload()`, whose own latch would hide what the runner wrote.
struct ProgressCancelHandOverTests {
    private static let start = Date(timeIntervalSince1970: 1_790_931_600)

    /// The host cancelled before the runner took the file over: the runner's first write, `running` and its screens, keeps the cancelled end.
    @Test
    func aRunCancelledBeforeTheRunnerAdoptsItStaysCancelledThroughTheRunnersWrites() throws {
        let directory = try ProgressWriterTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("s.json")
        let clock = ProgressWriterTests.FakeClock(Self.start)
        let host = ProgressWriter(url: url, clock: clock.read, pid: 1)
        host.begin(tool: "walk")
        host.cancel()
        let runner = ProgressWriter.adopting(url: url, clock: clock.read)
        clock.advance(1)
        runner.commit { $0.beginScreens(["today", "trends"]) }
        let written = try ProgressWriterTests.read(url)

        #expect(written.phase == .failed)
        #expect(written.error == "cancelled")
        #expect(written.matches?.planned == 2)
    }

    /// The host cancelled while the runner held the file: the runner's next screen, written from its copy of the state from before the cancel, keeps the cancelled end rather than putting `running` back.
    @Test
    func aRunCancelledWhileTheRunnerHoldsItStaysCancelledThroughTheRunnersNextScreen() throws {
        let directory = try ProgressWriterTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("s.json")
        let clock = ProgressWriterTests.FakeClock(Self.start)
        let host = ProgressWriter(url: url, clock: clock.read, pid: 1)
        host.begin(tool: "walk")
        host.commit { $0.phase = .launching }
        let runner = ProgressWriter.adopting(url: url, clock: clock.read)
        runner.commit { $0.beginScreens(["today", "trends"]) }
        let running = try ProgressWriterTests.read(url)
        host.cancel()
        clock.advance(1)
        runner.commit { $0.matches?.record(.captured) }
        let written = try ProgressWriterTests.read(url)

        #expect(running.phase == .running)
        #expect(written.phase == .failed)
        #expect(written.error == "cancelled")
        #expect(written.matches?.passed == 1)
    }

    /// A new run over a file whose last run was cancelled is not born cancelled: only the runner reads the file before it writes, and only a cancel written by another writer during its own run counts.
    @Test
    func aNewRunOverACancelledRunsFileStartsAlive() throws {
        let directory = try ProgressWriterTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("s.json")
        let clock = ProgressWriterTests.FakeClock(Self.start)
        let first = ProgressWriter(url: url, clock: clock.read, pid: 1)
        first.begin(tool: "walk")
        first.cancel()
        clock.advance(1)
        let second = ProgressWriter(url: url, clock: clock.read, pid: 1)
        second.begin(tool: "walk")
        second.update { $0.phase = .building }
        let building = try ProgressWriterTests.read(url)
        second.finish(.done)
        let ended = try ProgressWriterTests.read(url)

        #expect(building.phase == .building)
        #expect(building.error == nil)
        #expect(ended.phase == .done)
    }

    /// The host's cancel landed between the runner's look at the file and its rename, so the rename put `running` back over it — played here by putting the runner's bytes back after the cancel.
    ///
    /// The runner's next screen still writes the cancelled end: the marker beside the file is what it looks for, and no rename of the runner's reaches that.
    @Test
    func aCancelTheRunnersRenameOverwroteHoldsFromItsNextWrite() throws {
        let directory = try ProgressWriterTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("s.json")
        let clock = ProgressWriterTests.FakeClock(Self.start)
        let host = ProgressWriter(url: url, clock: clock.read, pid: 1)
        host.begin(tool: "walk")
        host.commit { $0.phase = .launching }
        let runner = ProgressWriter.adopting(url: url, clock: clock.read)
        runner.commit { $0.beginScreens(["today", "trends"]) }
        let runnersRename = try Data(contentsOf: url)
        host.cancel()
        try runnersRename.write(to: url)
        let overwritten = try ProgressWriterTests.read(url)
        clock.advance(1)
        runner.commit { $0.matches?.record(.captured) }
        let written = try ProgressWriterTests.read(url)

        #expect(overwritten.phase == .running)
        #expect(written.phase == .failed)
        #expect(written.error == "cancelled")
        #expect(written.matches?.passed == 1)
    }

    /// The host's cancel landed inside the runner's last write, between its look for the marker and its rename, and the runner never writes again: the rename put `running` over the cancel, and the runner's second look, once the rename has landed, writes the cancel back (SimWalk#89).
    @Test
    func aCancelLandingInTheRunnersLastWriteHolds() throws {
        let directory = try ProgressWriterTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("s.json")
        let clock = ProgressWriterTests.FakeClock(Self.start)
        let host = ProgressWriter(url: url, clock: clock.read, pid: 1)
        host.begin(tool: "walk")
        host.commit { $0.phase = .launching }
        var armed = false
        var landed = false
        let runner = ProgressWriter.adopting(url: url, clock: clock.read, beforeRename: {
            guard armed, !landed else { return }
            landed = true
            host.cancel()
        })
        runner.commit { $0.beginScreens(["today", "trends"]) }
        armed = true
        clock.advance(1)
        runner.commit { $0.matches?.record(.captured) }
        let written = try ProgressWriterTests.read(url)

        #expect(landed)
        #expect(written.phase == .failed)
        #expect(written.error == "cancelled")
        #expect(written.matches?.passed == 1)
    }

    /// The host cancelled after the runner's screens: the cancel is written over the runner's state, not the host's copy from before the hand-over, so the screen counts stay in the file even though the runner never writes again.
    @Test
    func aCancelKeepsTheRunnersScreenCounts() throws {
        let directory = try ProgressWriterTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("s.json")
        let clock = ProgressWriterTests.FakeClock(Self.start)
        let host = ProgressWriter(url: url, clock: clock.read, pid: 1)
        host.begin(tool: "walk")
        host.commit { $0.phase = .launching }
        let runner = ProgressWriter.adopting(url: url, clock: clock.read)
        runner.commit { $0.beginScreens(["today", "trends"]) }
        runner.commit { $0.matches?.record(.captured) }
        clock.advance(1)
        host.cancel()
        let written = try ProgressWriterTests.read(url)

        #expect(written.phase == .failed)
        #expect(written.error == "cancelled")
        #expect(written.matches?.planned == 2)
        #expect(written.matches?.passed == 1)
    }

    /// A cancel before the hand-over writes the host's own copy, a throttled change it has not written yet included: the file is still the host's last write, so there is no newer state in it to take.
    @Test
    func aCancelBeforeTheHandOverKeepsTheHostsUnwrittenChange() throws {
        let directory = try ProgressWriterTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("s.json")
        let clock = ProgressWriterTests.FakeClock(Self.start)
        let host = ProgressWriter(url: url, clock: clock.read, pid: 1)
        host.begin(tool: "walk")
        host.update { $0.app = "com.example.App" }
        let throttled = try ProgressWriterTests.read(url)
        host.cancel()
        let written = try ProgressWriterTests.read(url)

        #expect(throttled.app == nil)
        #expect(written.phase == .failed)
        #expect(written.app == "com.example.App")
    }

    /// A host cancel's marker does not outlive its run: the next run in the slot removes it when it begins, so that run's runner writes `running`, not the last run's cancel.
    @Test
    func theNextRunInTheSlotIsNotCancelledByTheLastRunsMarker() throws {
        let directory = try ProgressWriterTests.scratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("s.json")
        let clock = ProgressWriterTests.FakeClock(Self.start)
        let first = ProgressWriter(url: url, clock: clock.read, pid: 1)
        first.begin(tool: "walk")
        first.cancel()
        clock.advance(1)
        let second = ProgressWriter(url: url, clock: clock.read, pid: 1)
        second.begin(tool: "walk")
        second.commit { $0.phase = .launching }
        let runner = ProgressWriter.adopting(url: url, clock: clock.read)
        runner.commit { $0.beginScreens(["today"]) }
        let written = try ProgressWriterTests.read(url)

        #expect(written.phase == .running)
        #expect(written.error == nil)
    }
}
