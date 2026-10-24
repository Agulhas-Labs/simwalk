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

/// What `simwalk prune` refuses to do, against a scratch store — never the machine's own `~/.simwalk`.
struct PruneCommandTests {
    /// The SimWalk#22 review's finding 1: a development build does not prune — its pairing is gone at its next build, and judging which installs are old by it is how the installed binary's runner came to be removed.
    ///
    /// It says so on the verdict and removes nothing.
    @Test
    func adevelopmentBuildRefusesToPruneAndSaysSo() throws {
        let directory = try TemporaryDirectory()
        let checkout = directory.url.appendingPathComponent("checkout", isDirectory: true)
        let executable = checkout.appendingPathComponent(".build/debug/simwalk")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("binary".utf8).write(to: executable)
        let prune = RunnerPrune(
            store: RunnerStore(directory: directory.url.appendingPathComponent("runner", isDirectory: true)),
            builds: RunnerBuilds(directory: directory.url.appendingPathComponent("runner-builds", isDirectory: true))
        )
        let old = prune.store.snapshotsDirectory.appendingPathComponent("old", isDirectory: true)
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30 * 24 * 60 * 60)], ofItemAtPath: old.path)

        let answer = PruneCommand.answer(prune: prune, binary: (url: executable, hash: "dd"), checkout: checkout, installedHash: nil, dryRun: false, now: Date())

        #expect(answer.verdict.isQualified)
        #expect(answer.text.contains("is a development build"))
        #expect(FileManager.default.fileExists(atPath: old.path))
    }

    /// SimWalk#33 item 1: `--dry-run` from a development build plans with the installed binary's hash, when there is one, rather than the dev binary's own.
    ///
    /// The two disagree on which of 4 other installs fall inside the ``RunnerPrune/recentInstalls`` window: keyed on the dev binary's own (unmatched) hash, the installed binary competes for one of those 3 slots by its own recency and can push an older install out; keyed on the installed binary's hash, its own binding is excluded from that pool (it is kept outright, as "paired with the installed binary") and the older install survives instead — which is what a real run from the installed binary would actually plan.
    @Test
    func adryRunFromADevelopmentBuildPlansWithTheInstalledBinarysHash() throws {
        let directory = try TemporaryDirectory()
        let checkout = directory.url.appendingPathComponent("checkout", isDirectory: true)
        let executable = checkout.appendingPathComponent(".build/debug/simwalk")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("dev binary".utf8).write(to: executable)
        let prune = RunnerPrune(
            store: RunnerStore(directory: directory.url.appendingPathComponent("runner", isDirectory: true)),
            builds: RunnerBuilds(directory: directory.url.appendingPathComponent("runner-builds", isDirectory: true))
        )
        let bindings = prune.store.directory.appendingPathComponent("binaries", isDirectory: true)
        try FileManager.default.createDirectory(at: bindings, withIntermediateDirectories: true)
        let installedHash = "installed"
        // installed (1d) and b1..b3 (2d-4d) are the 3 most recent besides whichever hash plans; b4 (5d)
        // never is. b3's fate is the one that flips between the two plans.
        for (binary, days) in [(installedHash, 1.0), ("b1", 2.0), ("b2", 3.0), ("b3", 4.0), ("b4", 5.0)] {
            let snapshot = prune.store.snapshotsDirectory.appendingPathComponent(binary, isDirectory: true)
            try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
            let binding = bindings.appendingPathComponent("\(binary).json")
            try JSONEncoder().encode(RunnerStore.Binding(commit: binary, contentHash: "", snapshot: snapshot.path, checkout: "/checkout")).write(to: binding)
            let date = Date().addingTimeInterval(-days * 24 * 60 * 60)
            for url in [binding, snapshot] {
                try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
            }
        }
        let b3Snapshot = prune.store.snapshotsDirectory.appendingPathComponent("b3", isDirectory: true)

        let answer = PruneCommand.answer(prune: prune, binary: (url: executable, hash: "dd"), checkout: checkout, installedHash: installedHash, dryRun: true, now: Date())

        // Planned with the installed binary's hash, matching a real run from it: b3 is among the 3 most
        // recent installs besides the installed one's, so it survives — a plan keyed on the dev binary's
        // own hash instead would have the installed binary occupy one of those 3 slots and remove b3.
        #expect(!answer.text.contains("would remove \(b3Snapshot.path.tildedPath)"))
        #expect(answer.text.contains("kept \(b3Snapshot.path.tildedPath)"))
        #expect(FileManager.default.fileExists(atPath: b3Snapshot.path))
    }

    /// The other half of item 1: with no installed binary found, there is no truer plan to substitute, so the dry run keeps planning with the development binary's own hash and says so rather than silently differing from a real run with no honest alternative shown.
    @Test
    func adryRunFromADevelopmentBuildWithNoInstalledBinarySaysSo() throws {
        let directory = try TemporaryDirectory()
        let checkout = directory.url.appendingPathComponent("checkout", isDirectory: true)
        let executable = checkout.appendingPathComponent(".build/debug/simwalk")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("dev binary".utf8).write(to: executable)
        let prune = RunnerPrune(
            store: RunnerStore(directory: directory.url.appendingPathComponent("runner", isDirectory: true)),
            builds: RunnerBuilds(directory: directory.url.appendingPathComponent("runner-builds", isDirectory: true))
        )

        let answer = PruneCommand.answer(prune: prune, binary: (url: executable, hash: "dd"), checkout: checkout, installedHash: nil, dryRun: true, now: Date())

        #expect(answer.text.contains("planned with a development binary"))
        #expect(answer.text.contains(executable.path.tildedPath))
    }

    /// SimWalk#33 item 2: the rule line claims the installed binary's runner is kept only where one was found — with none, a residue line says so instead of the standing claim.
    @Test
    func aruleLineSaysWhenNoInstalledBinaryWasFound() throws {
        let directory = try TemporaryDirectory()
        let prune = RunnerPrune(
            store: RunnerStore(directory: directory.url.appendingPathComponent("runner", isDirectory: true)),
            builds: RunnerBuilds(directory: directory.url.appendingPathComponent("runner-builds", isDirectory: true))
        )

        let found = PruneCommand.answer(prune: prune, binary: (url: nil, hash: "dd"), checkout: directory.url, installedHash: "installed", dryRun: true, now: Date())
        let notFound = PruneCommand.answer(prune: prune, binary: (url: nil, hash: "dd"), checkout: directory.url, installedHash: nil, dryRun: true, now: Date())

        #expect(found.text.contains("keeps this binary's runner and the installed binary's"))
        #expect(!notFound.text.contains("and the installed binary's"))
        #expect(notFound.text.contains("no installed binary was found"))
    }

    /// SimWalk#22's `--dry-run` shows a plan without acting on it — the filesystem is untouched either way.
    @Test
    func adryRunRemovesNothing() throws {
        let directory = try TemporaryDirectory()
        let prune = RunnerPrune(
            store: RunnerStore(directory: directory.url.appendingPathComponent("runner", isDirectory: true)),
            builds: RunnerBuilds(directory: directory.url.appendingPathComponent("runner-builds", isDirectory: true))
        )
        // An orphan snapshot — no binding names it — is removed however old the store is, with nothing
        // else in it to compete for a "most recent installs" slot.
        let snapshot = prune.store.snapshotsDirectory.appendingPathComponent("old", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30 * 24 * 60 * 60)], ofItemAtPath: snapshot.path)

        let answer = PruneCommand.answer(prune: prune, binary: (url: nil, hash: "aa"), checkout: directory.url, installedHash: nil, dryRun: true, now: Date())

        #expect(answer.text.contains("would remove \(snapshot.path.tildedPath)"))
        #expect(FileManager.default.fileExists(atPath: snapshot.path))
    }

    /// SimWalk#33 review, item 4 (`simwalk prune`'s own verdict): every candidate surviving to be spared — a walk resolved it between the plan and the removal — must not read as "nothing to prune" beside lines that list them.
    @Test
    func averdictWhereEveryCandidateIsSparedNamesThemRatherThanSayingNothingToPrune() throws {
        let directory = try TemporaryDirectory()
        let prune = RunnerPrune(
            store: RunnerStore(directory: directory.url.appendingPathComponent("runner", isDirectory: true)),
            builds: RunnerBuilds(directory: directory.url.appendingPathComponent("runner-builds", isDirectory: true))
        )
        let snapshot = prune.store.snapshotsDirectory.appendingPathComponent("old", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30 * 24 * 60 * 60)], ofItemAtPath: snapshot.path)
        let plan = prune.plan(keepingBinary: "aa", installedBinary: nil, now: Date())
        // Walked after the plan was made, before the removal — spared rather than removed, exactly as
        // `RunnerPrune/execute(_:)`'s own re-check makes it (SimWalk#33).
        try FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: snapshot.path)
        let outcome = prune.execute(plan)

        #expect(!plan.removals.isEmpty)
        #expect(outcome.removed.isEmpty)
        #expect(outcome.spared.count == 1)
        #expect(PruneCommand.detail(plan: plan, outcome: outcome) == "0 of 1 removed — 1 spared, 0 failed")
    }

    /// The same review's item 4, for every candidate failing instead — a removal this tool cannot make, never a candidate to fold into "nothing to prune".
    @Test
    func averdictWhereEveryCandidateFailsNamesThemRatherThanSayingNothingToPrune() throws {
        let directory = try TemporaryDirectory()
        let prune = RunnerPrune(
            store: RunnerStore(directory: directory.url.appendingPathComponent("runner", isDirectory: true)),
            builds: RunnerBuilds(directory: directory.url.appendingPathComponent("runner-builds", isDirectory: true))
        )
        let snapshot = prune.store.snapshotsDirectory.appendingPathComponent("old", isDirectory: true)
        try FileManager.default.createDirectory(at: snapshot, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-30 * 24 * 60 * 60)], ofItemAtPath: snapshot.path)
        let plan = prune.plan(keepingBinary: "aa", installedBinary: nil, now: Date())
        // No write permission on the snapshots directory — the removal cannot even be set aside, so it fails
        // rather than being spared or removed.
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: prune.store.snapshotsDirectory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: prune.store.snapshotsDirectory.path) }
        let outcome = prune.execute(plan)

        #expect(!plan.removals.isEmpty)
        #expect(outcome.removed.isEmpty)
        #expect(outcome.spared.isEmpty)
        #expect(outcome.failed.count == 1)
        #expect(PruneCommand.detail(plan: plan, outcome: outcome) == "0 of 1 removed — 0 spared, 1 failed")
    }

    /// SimWalk#33 review, item 3: a `--dry-run` from a development build that plans with the installed binary's hash says which binary it planned as, since the header still names this (dev) binary.
    @Test
    func adryRunPlanningWithTheInstalledBinarysHashSaysSo() throws {
        let directory = try TemporaryDirectory()
        let checkout = directory.url.appendingPathComponent("checkout", isDirectory: true)
        let executable = checkout.appendingPathComponent(".build/debug/simwalk")
        try FileManager.default.createDirectory(at: executable.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("dev binary".utf8).write(to: executable)
        let prune = RunnerPrune(
            store: RunnerStore(directory: directory.url.appendingPathComponent("runner", isDirectory: true)),
            builds: RunnerBuilds(directory: directory.url.appendingPathComponent("runner-builds", isDirectory: true))
        )

        let answer = PruneCommand.answer(prune: prune, binary: (url: executable, hash: "dd"), checkout: checkout, installedHash: "installed", dryRun: true, now: Date())

        #expect(answer.text.contains("planned as the installed binary (sha256 \(ShortHash.of("installed"))) would plan"))
    }

    /// A dry run through the prune's lease wiring deletes no clone and removes no lease, and says what it would do.
    @Test
    func aDryRunLeavesLeasesAndTheirDevicesAlone() throws {
        let fixture = try Self.leaseFixture()

        let answer = PruneCommand.answer(prune: fixture.prune, binary: (url: nil, hash: "aa"), checkout: fixture.directory.url, installedHash: nil, dryRun: true, now: fixture.now, leases: fixture.leasing)

        #expect(answer.text.contains("would release the lapsed lease on CLONE-OLD, deleting its clone"))
        #expect(answer.text.contains("would release 1 lapsed lease, would delete 1 clone, would remove 1 temporary file"))
        #expect(fixture.script.vectors.isEmpty)
        #expect(fixture.store.all().map(\.udid) == ["CLONE-OLD"])
        #expect(FileManager.default.fileExists(atPath: fixture.temporary.path))
    }

    /// A real run that removed no runner path but released a lease, deleted a clone and swept a temporary file does not say "nothing to prune".
    @Test
    func theVerdictCountsReleasedLeasesDeletedClonesAndSweptFiles() throws {
        let fixture = try Self.leaseFixture()

        let answer = PruneCommand.answer(prune: fixture.prune, binary: (url: nil, hash: "aa"), checkout: fixture.directory.url, installedHash: nil, dryRun: false, now: fixture.now, leases: fixture.leasing)

        #expect(answer.text.contains("released the lapsed lease on CLONE-OLD and deleted its clone"))
        #expect(answer.text.contains("released 1 lapsed lease, deleted 1 clone, removed 1 temporary file"))
        #expect(!answer.text.contains("nothing to prune"))
        #expect(fixture.script.vectors == [["simctl", "shutdown", "CLONE-OLD"], ["simctl", "delete", "CLONE-OLD"]])
        #expect(fixture.store.all().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.temporary.path))
    }

    /// A lapsed lease that found its device shut down says the prune shut that device down, and the dry run that it would, as a clone's says it is deleted (SimWalk#249).
    @Test
    func apruneSaysItShutDownADeviceTheLeaseFoundShutDown() throws {
        let dry = try Self.leaseFixture(createdDevice: false, foundShutDown: true)
        let real = try Self.leaseFixture(createdDevice: false, foundShutDown: true)

        let planned = PruneCommand.answer(prune: dry.prune, binary: (url: nil, hash: "aa"), checkout: dry.directory.url, installedHash: nil, dryRun: true, now: dry.now, leases: dry.leasing)
        let done = PruneCommand.answer(prune: real.prune, binary: (url: nil, hash: "aa"), checkout: real.directory.url, installedHash: nil, dryRun: false, now: real.now, leases: real.leasing)

        #expect(planned.text.contains("would release the lapsed lease on CLONE-OLD, shutting its device down, as the lease found it"))
        #expect(planned.text.contains("would release 1 lapsed lease, would shut down 1 device found shut down, would remove 1 temporary file"))
        #expect(dry.script.vectors.isEmpty)
        #expect(done.text.contains("released the lapsed lease on CLONE-OLD and shut its device down, as the lease found it"))
        #expect(done.text.contains("released 1 lapsed lease, shut down 1 device found shut down, removed 1 temporary file"))
        #expect(real.script.vectors == [["simctl", "shutdown", "CLONE-OLD"]])
    }

    /// SimWalk#75 item 6: the record on a clone a prune released, whose walk is gone, is removed with it.
    @Test
    func aReleasedClonesRecordWithNoRunningOwnerIsRemoved() throws {
        let fixture = try Self.leaseFixture()
        let journal = try Self.journal(in: fixture, record: "CLONE-OLD", pid: 500)

        let answer = Self.prune(fixture, journal: journal, dryRun: false)

        #expect(answer.text.contains("removed the device-setup record on CLONE-OLD"))
        #expect(!journal.hasRecord(onDevice: "CLONE-OLD"))
    }

    /// A removal that fails is not reported as made.
    @Test
    func aRecordThatCannotBeRemovedIsNotReportedRemoved() throws {
        let fixture = try Self.leaseFixture()
        let journal = try Self.journal(in: fixture, record: "CLONE-OLD", pid: 500)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: journal.directory.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: journal.directory.path) }

        let answer = Self.prune(fixture, journal: journal, dryRun: false)

        #expect(answer.text.contains("could not remove the device-setup record on CLONE-OLD"))
        #expect(!answer.text.contains("removed the device-setup record"))
        #expect(journal.hasRecord(onDevice: "CLONE-OLD"))
    }

    /// A record whose walk still runs is kept, and the line says so.
    @Test
    func aReleasedClonesRecordWhoseOwnerIsRunningIsKept() throws {
        let fixture = try Self.leaseFixture()
        let journal = try Self.journal(in: fixture, record: "CLONE-OLD", pid: 500, running: true)

        let answer = Self.prune(fixture, journal: journal, dryRun: false)

        #expect(answer.text.contains("kept the device-setup record on CLONE-OLD — its walk (pid 500) still runs"))
        #expect(journal.hasRecord(onDevice: "CLONE-OLD"))
    }

    /// A lease that did not create its device releases without the release path touching its record: the device still exists, so a dead walk's record stays for the next walk on it to hand back.
    @Test
    func aNonCloneReleasesWithItsRecordKept() throws {
        let fixture = try Self.leaseFixture(createdDevice: false)
        fixture.script.devices = ["CLONE-OLD"]
        let journal = try Self.journal(in: fixture, record: "CLONE-OLD", pid: 500)

        let answer = Self.prune(fixture, journal: journal, dryRun: false)

        #expect(answer.text.contains("released the lapsed lease on CLONE-OLD"))
        #expect(journal.hasRecord(onDevice: "CLONE-OLD"))
    }

    /// SimWalk#92: a record a first prune kept because its walk still ran is removed by a later one once the walk is gone and the clone and its device with it.
    @Test
    func anOrphanedRecordIsRemovedOnceItsWalkIsGone() throws {
        let fixture = try Self.leaseFixture()
        let processes = FakeSessionProcesses()
        processes.alive = [500]
        processes.startTimes[500] = Date(timeIntervalSince1970: 0)
        let journal = try Self.journal(in: fixture, record: "CLONE-OLD", pid: 500, processes: processes)

        let first = Self.prune(fixture, journal: journal, dryRun: false)
        #expect(first.text.contains("kept the device-setup record on CLONE-OLD"))
        #expect(journal.hasRecord(onDevice: "CLONE-OLD"))

        processes.alive = []
        let dry = Self.prune(fixture, journal: journal, dryRun: true)
        #expect(dry.text.contains("would remove the orphaned device-setup record on CLONE-OLD"))
        #expect(journal.hasRecord(onDevice: "CLONE-OLD"))

        let second = Self.prune(fixture, journal: journal, dryRun: false)
        #expect(second.text.contains("removed the orphaned device-setup record on CLONE-OLD"))
        #expect(!journal.hasRecord(onDevice: "CLONE-OLD"))
    }

    /// A dead walk's record on a device that still exists is kept: the next walk there hands it back first.
    @Test
    func anOrphanSweepKeepsADeadWalksRecordWhileItsDeviceExists() throws {
        let fixture = try Self.leaseFixture()
        fixture.script.devices = ["STILL-HERE"]
        let journal = try Self.journal(in: fixture, record: "STILL-HERE", pid: 500)

        let answer = Self.prune(fixture, journal: journal, dryRun: false)

        #expect(journal.hasRecord(onDevice: "STILL-HERE"))
        #expect(!answer.text.contains("orphaned"))
    }

    /// A simulator list that fails removes nothing, and the answer says why.
    @Test
    func anOrphanSweepRemovesNothingWhenTheDeviceListFails() throws {
        let fixture = try Self.leaseFixture(createdDevice: false)
        fixture.script.listingStatus = 1
        let journal = try Self.journal(in: fixture, record: "GONE", pid: 500)

        let answer = Self.prune(fixture, journal: journal, dryRun: false)

        #expect(journal.hasRecord(onDevice: "GONE"))
        #expect(answer.text.contains("kept the device-setup records on GONE — the simulator list could not be read"))
    }

    /// A simulator list that does not parse removes nothing either.
    @Test
    func anOrphanSweepRemovesNothingWhenTheDeviceListDoesNotParse() throws {
        let fixture = try Self.leaseFixture(createdDevice: false)
        fixture.script.listingOutput = "not json"
        let journal = try Self.journal(in: fixture, record: "GONE", pid: 500)

        let answer = Self.prune(fixture, journal: journal, dryRun: false)

        #expect(journal.hasRecord(onDevice: "GONE"))
        #expect(answer.text.contains("the simulator list could not be read"))
    }

    /// A dead walk's record on a device that still has a lease, or a clone, is kept; so is one whose walk still runs.
    @Test
    func anOrphanSweepKeepsARecordWhoseDeviceStillHasALeaseOrWhoseWalkRuns() throws {
        let fixture = try Self.leaseFixture()
        _ = try fixture.store.acquire(udid: "LIVE-LEASE", ttl: 3600, holderPID: 41, now: fixture.now)
        _ = try fixture.store.acquire(udid: "LIVE-CLONE", ttl: 60, holderPID: 41, now: fixture.now, createdDevice: true, clonedFrom: "SHUT-1")
        let journal = try Self.journal(in: fixture, record: "LIVE-LEASE", pid: 500)
        try Self.addRecord(to: journal, udid: "LIVE-CLONE", pid: 500)
        try Self.addRecord(to: journal, udid: "NO-LEASE", pid: 501)

        let processes = FakeSessionProcesses()
        processes.alive = [501]
        processes.startTimes[501] = Date(timeIntervalSince1970: 0)
        let judging = DeviceSetupJournal(directory: journal.directory, processes: processes)

        let answer = Self.prune(fixture, journal: judging, dryRun: false)

        #expect(judging.hasRecord(onDevice: "LIVE-LEASE"))
        #expect(judging.hasRecord(onDevice: "LIVE-CLONE"))
        #expect(judging.hasRecord(onDevice: "NO-LEASE"))
        #expect(answer.text.contains("kept the device-setup record on NO-LEASE — its walk (pid 501) still runs"))
        #expect(!answer.text.contains("orphaned"))
    }

    /// `--dry-run` says "would remove" and leaves the record.
    @Test
    func aDryRunSaysItWouldRemoveTheRecordAndLeavesIt() throws {
        let fixture = try Self.leaseFixture()
        let journal = try Self.journal(in: fixture, record: "CLONE-OLD", pid: 500)

        let answer = Self.prune(fixture, journal: journal, dryRun: true)

        #expect(answer.text.contains("would remove the device-setup record on CLONE-OLD"))
        #expect(journal.hasRecord(onDevice: "CLONE-OLD"))
    }

    /// An `.unreadable-*` file kept beside a record, and a record that does not read, are never removed.
    @Test
    func anUnreadableRecordAndItsKeptCopyAreUntouched() throws {
        let fixture = try Self.leaseFixture()
        let journal = DeviceSetupJournal(directory: fixture.directory.url.appendingPathComponent("setup", isDirectory: true), processes: FakeSessionProcesses())
        try FileManager.default.createDirectory(at: journal.directory, withIntermediateDirectories: true)
        let kept = journal.directory.appendingPathComponent("CLONE-OLD.unreadable-walk.json")
        try Data("not json".utf8).write(to: kept)
        try Data("not json".utf8).write(to: journal.directory.appendingPathComponent("CLONE-OLD.json"))

        let answer = Self.prune(fixture, journal: journal, dryRun: false)

        #expect(!answer.text.contains("device-setup record"))
        #expect(FileManager.default.fileExists(atPath: kept.path))
        #expect(journal.hasRecord(onDevice: "CLONE-OLD"))
    }

    private static func prune(_ fixture: LeaseFixture, journal: DeviceSetupJournal, dryRun: Bool) -> Answer {
        PruneCommand.answer(prune: fixture.prune, binary: (url: nil, hash: "aa"), checkout: fixture.directory.url, installedHash: nil, dryRun: dryRun, now: fixture.now, leases: fixture.leasing, journal: journal)
    }

    /// A journal in the fixture's scratch directory holding a record of the walk `pid` on `udid`.
    private static func journal(in fixture: LeaseFixture, record udid: String, pid: Int32, running: Bool = false, processes: FakeSessionProcesses = FakeSessionProcesses()) throws -> DeviceSetupJournal {
        if running {
            processes.alive = [pid]
            processes.startTimes[pid] = Date(timeIntervalSince1970: 0)
        }
        let journal = DeviceSetupJournal(directory: fixture.directory.url.appendingPathComponent("setup", isDirectory: true), processes: processes)
        try FileManager.default.createDirectory(at: journal.directory, withIntermediateDirectories: true)
        try addRecord(to: journal, udid: udid, pid: pid)
        return journal
    }

    /// A record of the walk `pid` on `udid`, written beside the journal's others.
    private static func addRecord(to journal: DeviceSetupJournal, udid: String, pid: Int32) throws {
        let entry = #"{"udid":"\#(udid)","bundleID":"app.id","pid":\#(pid),"token":"walk","applied":{"privacy":[],"statusBar":true,"statusBarFound":[]},"recordedAt":0}"#
        try Data(entry.utf8).write(to: journal.directory.appendingPathComponent("\(udid).json"))
    }

    /// A scratch runner store, and a lease store holding one lapsed clone lease and one stale temporary file.
    private static func leaseFixture(createdDevice: Bool = true, foundShutDown: Bool = false) throws -> LeaseFixture {
        let directory = try TemporaryDirectory()
        let prune = RunnerPrune(
            store: RunnerStore(directory: directory.url.appendingPathComponent("runner", isDirectory: true)),
            builds: RunnerBuilds(directory: directory.url.appendingPathComponent("runner-builds", isDirectory: true))
        )
        let now = Date(timeIntervalSince1970: 1_000_000)
        let store = LeaseStore(directory: directory.url.appendingPathComponent("leases", isDirectory: true), isAlive: { _ in true })
        _ = try store.acquire(udid: "CLONE-OLD", ttl: 60, holderPID: 41, now: now.addingTimeInterval(-3600), createdDevice: createdDevice, clonedFrom: createdDevice ? "SHUT-1" : nil, foundShutDown: foundShutDown)
        let temporary = store.directory.appendingPathComponent(".CLONE-OLD.json.AAAA.tmp")
        try Data("x".utf8).write(to: temporary)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-600)], ofItemAtPath: temporary.path)
        let script = ShellScript()
        return LeaseFixture(directory: directory, prune: prune, now: now, store: store, temporary: temporary, script: script, leasing: DeviceLeasing(store: store, shell: Shell(script: script.run)))
    }
}

private extension PruneCommandTests {
    /// Every `simctl` call a prune made, answered with success.
    final class ShellScript {
        private(set) var vectors: [[String]] = []
        /// The UDIDs `simctl list` reports as existing; none by default, so a record's device is gone.
        var devices: [String] = []
        var listingStatus: Int32 = 0
        var listingOutput: String?

        var run: (String, [String], [String: String]) throws -> Shell.Result {
            { [self] _, arguments, _ in
                vectors.append(arguments)
                guard arguments.starts(with: ["simctl", "list"]) else {
                    return Shell.Result(status: 0, standardOutput: "", standardError: "")
                }
                let entries = devices.map { #"{"udid":"\#($0)","name":"iPhone","state":"Shutdown"}"# }.joined(separator: ",")
                return Shell.Result(status: listingStatus, standardOutput: listingOutput ?? #"{"devices":{"com.apple.CoreSimulator.SimRuntime.iOS-26-0":[\#(entries)]}}"#, standardError: "")
            }
        }
    }

    struct LeaseFixture {
        let directory: TemporaryDirectory
        let prune: RunnerPrune
        let now: Date
        let store: LeaseStore
        let temporary: URL
        let script: ShellScript
        let leasing: DeviceLeasing
    }
}
