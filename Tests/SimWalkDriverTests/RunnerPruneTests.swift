//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// What a prune removes and what it must never touch (SimWalk#22), against a scratch store — never the machine's own `~/.simwalk`.
struct RunnerPruneTests {
    /// G1: the runner paired with the binary doing the pruning survives however old it is, as do the three most recent installs besides it; the older ones go — binding, snapshot and build — and the space is counted.
    @Test
    func theinstalledPairingAndTheRecentInstallsSurviveAndTheRestIsRemoved() throws {
        let scratch = try Scratch()
        let installed = try scratch.install(binary: "aa", commit: "1111", daysAgo: 10)
        let recent = try [2, 3, 4].map { try scratch.install(binary: "b\($0)", commit: "200\($0)", daysAgo: Double($0)) }
        let old = try [5, 6].map { try scratch.install(binary: "c\($0)", commit: "300\($0)", daysAgo: Double($0)) }

        let outcome = scratch.prune.execute(scratch.prune.plan(keepingBinary: "aa", installedBinary: nil, now: Date()))
        let survivors = ([installed] + recent + old).map { $0.all.map { FileManager.default.fileExists(atPath: $0.path) } }

        #expect(survivors == Array(repeating: [true, true, true], count: 4) + Array(repeating: [false, false, false], count: 2))
        #expect(Set(outcome.removed.map(\.url.path)) == Set(old.flatMap(\.all).map(\.path)))
        #expect(outcome.failed.isEmpty)
        #expect(outcome.freed >= 2 * Scratch.payload.count)
    }

    /// A walk in flight rewrites its build's record as it starts, so an old install's build walked within the day — and the snapshot it builds — are not pulled out from under it.
    @Test
    func arunnerWalkedWithinTheDayIsKeptHoweverOldItsInstall() throws {
        let scratch = try Scratch()
        _ = try scratch.install(binary: "aa", commit: "1111", daysAgo: 1.5)
        _ = try [2, 3, 4].map { try scratch.install(binary: "b\($0)", commit: "200\($0)", daysAgo: Double($0)) }
        let walked = try scratch.install(binary: "cc", commit: "3000", daysAgo: 9, buildDaysAgo: 0.01)

        let plan = scratch.prune.plan(keepingBinary: "aa", installedBinary: nil, now: Date())

        #expect(plan.removals.isEmpty)
        #expect(Set(walked.all).isSubset(of: Set(plan.kept.map(\.url))))
    }

    /// A working tree's build whose project has gone is removed, and one whose project is still there is kept.
    ///
    /// G2: a working tree's build lives outside the tree, so removing a worktree never reclaims it. One made before builds carried a record is attributed by Xcode's own `info.plist`.
    @Test
    func atreeBuildWhoseSourceIsGoneIsRemovedAndOneWhoseSourceExistsIsKept() throws {
        let scratch = try Scratch()
        let live = scratch.directory.url.appendingPathComponent("live/Runner/SimWalkRunner.xcodeproj")
        try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
        let gone = scratch.directory.url.appendingPathComponent("removed-worktree/Runner/SimWalkRunner.xcodeproj").path
        let liveBuild = try scratch.build(project: live.path, daysAgo: 30)
        let goneBuild = try scratch.build(project: gone, daysAgo: 30)
        let legacyBuild = try scratch.legacyBuild(project: gone, key: "tree-legacy", daysAgo: 30)

        let outcome = scratch.prune.execute(scratch.prune.plan(keepingBinary: "aa", installedBinary: nil, now: Date()))

        #expect(FileManager.default.fileExists(atPath: liveBuild.path))
        #expect(!FileManager.default.fileExists(atPath: goneBuild.path))
        #expect(!FileManager.default.fileExists(atPath: legacyBuild.path))
        #expect(Set(outcome.removed.map(\.url.path)) == [goneBuild.path, legacyBuild.path])
        #expect(outcome.freed >= 2 * Scratch.payload.count)
    }

    /// SimWalk#97: a working tree's build whose checkout is gone is removed even when walked an hour ago — planned and then executed, not spared by the 24 h re-check — since nothing can walk it again; one whose checkout exists, and a snapshot's build, keep the 24 h grace.
    @Test
    func aTreeBuildWhoseCheckoutIsGoneIsRemovedEvenWhenWalkedAnHourAgo() throws {
        let scratch = try Scratch()
        let live = scratch.directory.url.appendingPathComponent("live/Runner/SimWalkRunner.xcodeproj")
        try FileManager.default.createDirectory(at: live, withIntermediateDirectories: true)
        let gone = scratch.directory.url.appendingPathComponent("removed-worktree/Runner/SimWalkRunner.xcodeproj").path
        let hour = 1.0 / 24
        let goneBuild = try scratch.build(project: gone, daysAgo: hour)
        let liveBuild = try scratch.build(project: live.path, daysAgo: hour)
        let snapshotBuild = try scratch.install(binary: "ss", commit: "5555", daysAgo: 9, buildDaysAgo: hour).build

        let plan = scratch.prune.plan(keepingBinary: "aa", installedBinary: nil, now: Date())

        #expect(plan.removals.first { $0.url == goneBuild }?.reason == "builds \(gone.tildedPath), which no longer exists")
        #expect(plan.kept.first { $0.url == liveBuild }?.reason == "walked within the last 24 h")
        #expect(plan.kept.first { $0.url == snapshotBuild }?.reason == "walked within the last 24 h")

        let outcome = scratch.prune.execute(plan)

        #expect(outcome.removed.map(\.url) == [goneBuild])
        #expect(outcome.spared.isEmpty)
        #expect(outcome.failed.isEmpty)
        #expect(!FileManager.default.fileExists(atPath: goneBuild.path))
        #expect([liveBuild, snapshotBuild].allSatisfy { FileManager.default.fileExists(atPath: $0.appendingPathComponent("payload").path) })
    }

    /// SimWalk#97 with SimWalk#33: a working tree's build whose checkout is gone, walked after the plan was made, is still spared — the removal's own cutoff is the plan's moment, not 24 h before it.
    @Test
    func aTreeBuildWhoseCheckoutIsGoneIsSparedWhenWalkedAfterThePlan() throws {
        let scratch = try Scratch()
        let gone = scratch.directory.url.appendingPathComponent("removed-worktree/Runner/SimWalkRunner.xcodeproj").path
        let goneBuild = try scratch.build(project: gone, daysAgo: 1.0 / 24)
        let plan = scratch.prune.plan(keepingBinary: "aa", installedBinary: nil, now: Date().addingTimeInterval(-60))

        try Scratch.age(RunnerBuilds.useMarkers(in: goneBuild), daysAgo: 0)
        let outcome = scratch.prune.execute(plan)

        #expect(plan.removals.map(\.url) == [goneBuild])
        #expect(outcome.spared.map(\.url) == [goneBuild])
        #expect(outcome.removed.isEmpty)
        #expect(FileManager.default.fileExists(atPath: goneBuild.appendingPathComponent("payload").path))
    }

    /// The SimWalk#22 review's finding 1: the installed binary's runner survives a prune by any other binary, however old its install and however many newer ones there are — a development build's `install-hook` writes a binding every build, and three of them used to push the installed one out of the most recent installs.
    @Test
    func theinstalledBinarysRunnerSurvivesAPruneByAnotherBinary() throws {
        let scratch = try Scratch()
        let installed = try scratch.install(binary: "ii", commit: "1111", daysAgo: 5)
        _ = try [2, 3, 4].map { try scratch.install(binary: "b\($0)", commit: "200\($0)", daysAgo: Double($0)) }

        let outcome = scratch.prune.execute(scratch.prune.plan(keepingBinary: "dd", installedBinary: "ii", now: Date()))

        #expect(installed.all.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(outcome.removed.isEmpty)
    }

    /// The SimWalk#22 review's finding 3: a walk that resolves its runner while a prune is planning records its use after the plan was made, and the removal is re-checked immediately before it happens — so the build, its snapshot and the binding naming it are all spared.
    @Test
    func arunnerWalkedAfterThePlanWasMadeIsSpared() throws {
        let scratch = try Scratch()
        _ = try scratch.install(binary: "aa", commit: "1111", daysAgo: 1.5)
        _ = try [2, 3, 4].map { try scratch.install(binary: "b\($0)", commit: "200\($0)", daysAgo: Double($0)) }
        let walked = try scratch.install(binary: "cc", commit: "3000", daysAgo: 9)
        let plan = scratch.prune.plan(keepingBinary: "aa", installedBinary: nil, now: Date())

        _ = try scratch.build(project: RunnerProject.project(under: walked.snapshot.path), commit: "3000", daysAgo: 0)
        let outcome = scratch.prune.execute(plan)

        #expect(Set(plan.removals.map(\.url)) == Set(walked.all))
        #expect(walked.all.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })
        #expect(Set(outcome.spared.map(\.url)) == Set(walked.all))
        #expect(outcome.removed.isEmpty)
    }

    /// A kept binding that spells its snapshot's path differently from the store — through a symlink here, `/var` against `/private/var` on a real machine — still keeps that snapshot: a mismatch keeps rather than removes.
    @Test
    func akeptBindingKeepsItsSnapshotHoweverItsPathIsSpelled() throws {
        let scratch = try Scratch()
        let runner = try scratch.install(binary: "aa", commit: "1111", daysAgo: 30)
        let alias = scratch.directory.url.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: scratch.prune.store.directory)
        let spelled = alias.appendingPathComponent("snapshots/1111", isDirectory: true).path
        try JSONEncoder()
            .encode(RunnerStore.Binding(commit: "1111", contentHash: "hash", snapshot: spelled, checkout: "/checkout"))
            .write(to: runner.binding)
        try Scratch.age([runner.binding], daysAgo: 30)

        let outcome = scratch.prune.execute(scratch.prune.plan(keepingBinary: "aa", installedBinary: nil, now: Date()))

        #expect(FileManager.default.fileExists(atPath: runner.snapshot.path))
        #expect(outcome.removed.isEmpty)
    }

    /// SimWalk#33: a working tree's checkout re-created where it was and walked while the prune removes its old build keeps the new build — the old one was set aside before the deletion began, so the walk starts afresh at a path the deletion never touches.
    @Test
    func atreeBuildRecreatedAndWalkedDuringItsRemovalSurvives() throws {
        let scratch = try Scratch()
        let checkout = scratch.directory.url.appendingPathComponent("worktree/Runner/SimWalkRunner.xcodeproj")
        let build = try scratch.build(project: checkout.path, daysAgo: 30)
        let plan = scratch.prune.plan(keepingBinary: "aa", installedBinary: nil, now: Date())

        let outcome = scratch.prune.execute(plan) { url in
            guard url == build else { return }
            try? FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)
            try? scratch.prune.builds.recordUse(of: RunnerSource(projectPath: checkout.path, commit: nil, origin: .checkout))
        }

        #expect(plan.removals.map(\.url) == [build])
        #expect(scratch.prune.builds.builtProject(at: build) == checkout.path)
        #expect(!FileManager.default.fileExists(atPath: build.appendingPathComponent("payload").path))
        #expect(outcome.removed.map(\.url) == [build])
        #expect(scratch.setAside.isEmpty)
    }

    /// SimWalk#33: a walk whose record landed just before its build was set aside has the build put back whole and spared — never deleted while the prune says it was kept.
    @Test
    func abuildWalkedAsItWasSetAsideIsPutBackWhole() throws {
        let scratch = try Scratch()
        let project = scratch.directory.url.appendingPathComponent("gone/Runner/SimWalkRunner.xcodeproj").path
        let build = try scratch.build(project: project, daysAgo: 30)
        let plan = scratch.prune.plan(keepingBinary: "aa", installedBinary: nil, now: Date())

        let outcome = scratch.prune.execute(plan) { url in
            guard url == build else { return }
            try? Scratch.age(scratch.builds(of: project).flatMap(RunnerBuilds.useMarkers(in:)), daysAgo: 0)
        }

        #expect(FileManager.default.fileExists(atPath: build.appendingPathComponent("payload").path))
        #expect(outcome.spared.map(\.url) == [build])
        #expect(outcome.removed.isEmpty)
        #expect(scratch.setAside.isEmpty)
    }

    /// SimWalk#33: when the walk that used a build as it was set aside has already re-created its path, the build cannot be put back — it stays set aside and is reported failed, never spared and never deleted, and the next prune keeps it while it is recent.
    @Test
    func abuildThatCannotBePutBackStaysAsideAndIsReportedFailed() throws {
        let scratch = try Scratch()
        let project = scratch.directory.url.appendingPathComponent("gone/Runner/SimWalkRunner.xcodeproj").path
        let build = try scratch.build(project: project, daysAgo: 30)
        let plan = scratch.prune.plan(keepingBinary: "aa", installedBinary: nil, now: Date())

        let outcome = scratch.prune.execute(plan) { url in
            guard url == build else { return }
            try? Scratch.age(scratch.builds(of: project).flatMap(RunnerBuilds.useMarkers(in:)), daysAgo: 0)
            try? scratch.prune.builds.recordUse(of: RunnerSource(projectPath: project, commit: nil, origin: .checkout))
        }
        let next = scratch.prune.plan(keepingBinary: "aa", installedBinary: nil, now: Date())

        #expect(outcome.failed.map(\.entry.url) == [build])
        #expect(outcome.spared.isEmpty)
        #expect(outcome.removed.isEmpty)
        #expect(scratch.setAside.count == 1)
        #expect(scratch.setAside.allSatisfy { FileManager.default.fileExists(atPath: $0.appendingPathComponent("payload").path) })
        #expect(Set(next.kept.map(\.url)).isSuperset(of: scratch.setAside))
        // The build the walk re-created at the gone project's path is itself removable now (SimWalk#97), and it is the only removal.
        #expect(next.removals.map(\.url) == [build])
    }

    /// SimWalk#33: what a prune set aside and never deleted — it stopped between the two — is removed by a later prune once nothing has used it in a day, and kept while something has.
    @Test
    func whatAnUnfinishedPruneSetAsideIsSweptOnceUnused() throws {
        let scratch = try Scratch()
        let unused = scratch.prune.builds.directory.appendingPathComponent("\(Scratch.setAsidePrefix)A-tree-old", isDirectory: true)
        let used = scratch.prune.builds.directory.appendingPathComponent("\(Scratch.setAsidePrefix)B-tree-new", isDirectory: true)
        for (aside, daysAgo) in [(unused, 30.0), (used, 0.0)] {
            try FileManager.default.createDirectory(at: aside, withIntermediateDirectories: true)
            try Scratch.payload.write(to: aside.appendingPathComponent("payload"))
            try Scratch.age(RunnerBuilds.useMarkers(in: aside), daysAgo: daysAgo)
        }

        let outcome = scratch.prune.execute(scratch.prune.plan(keepingBinary: "aa", installedBinary: nil, now: Date()))

        #expect(outcome.removed.map(\.url) == [unused])
        #expect(!FileManager.default.fileExists(atPath: unused.path))
        #expect(FileManager.default.fileExists(atPath: used.path))
        #expect(outcome.freed >= Scratch.payload.count)
    }

    /// SimWalk#33: a snapshot cloned from its checkout, as `copyItem` makes one on APFS, frees only the bytes it does not share — so a prune does not count the checkout's blocks as freed, and does count the bytes that are the snapshot's alone.
    ///
    /// Both kinds sit in the snapshot at once, and the checkout stands throughout (SimWalk#53). The unshared bytes were once the clone's after its checkout was deleted, but when a deletion releases its share is the volume's business: under sibling builds' writes it had not by the time of the read, and the count came up short. A file written straight into the snapshot is unshared from the start, and anything else on the volume can only lower what a file counts — so the upper bound holds under any load, and the lower one needs only that the file is the snapshot's own.
    @Test(.enabled(if: Scratch.clonesFiles))
    func aclonedSnapshotCountsOnlyTheBytesItsRemovalFrees() throws {
        let scratch = try Scratch()
        _ = try scratch.install(binary: "aa", commit: "1111", daysAgo: 1.5)
        _ = try [2, 3, 4].map { try scratch.install(binary: "b\($0)", commit: "200\($0)", daysAgo: Double($0)) }
        let old = try scratch.install(binary: "cc", commit: "3000", daysAgo: 9)
        let checkout = scratch.directory.url.appendingPathComponent("checkout.pbxproj")
        let size = 1 << 20
        try Data(repeating: 7, count: size).write(to: checkout)
        let project = URL(fileURLWithPath: RunnerProject.project(under: old.snapshot.path))
        let clone = project.appendingPathComponent("project.pbxproj")
        try FileManager.default.removeItem(at: clone)
        try FileManager.default.copyItem(at: checkout, to: clone)
        try Data(repeating: 8, count: size).write(to: project.appendingPathComponent("own.bin"))
        try Scratch.age([old.snapshot], daysAgo: 9)

        let counted = try #require(scratch.prune.plan(keepingBinary: "aa", installedBinary: nil, now: Date()).removals.first { $0.url == old.snapshot }?.bytes)

        #expect(counted >= size, "counted \(counted) bytes: the snapshot's own \(size) are missing")
        #expect(counted < 2 * size, "counted \(counted) bytes: the clone's \(size) shared with its standing checkout are among them")
    }

    /// SimWalk#34: a walk whose old build directory a prune sets aside after the walk has created it but before its record lands records its use in a fresh directory at the same path — never a failed walk, and never a record written into what the prune is deleting.
    @Test
    func awalkWhoseBuildIsSetAsideBeforeItsRecordLandsRecordsItAfresh() throws {
        let scratch = try Scratch()
        let checkout = scratch.directory.url.appendingPathComponent("worktree/Runner/SimWalkRunner.xcodeproj")
        let build = try scratch.build(project: checkout.path, daysAgo: 30)
        let plan = scratch.prune.plan(keepingBinary: "aa", installedBinary: nil, now: Date())
        try FileManager.default.createDirectory(at: checkout, withIntermediateDirectories: true)

        var outcome: RunnerPrune.Outcome?
        try scratch.prune.builds.recordUse(of: RunnerSource(projectPath: checkout.path, commit: nil, origin: .checkout)) {
            outcome = scratch.prune.execute(plan)
        }

        #expect(outcome?.removed.map(\.url) == [build])
        #expect(scratch.prune.builds.builtProject(at: build) == checkout.path)
        #expect(!FileManager.default.fileExists(atPath: build.appendingPathComponent("payload").path))
        #expect(scratch.setAside.isEmpty)
    }

    /// SimWalk#34: a snapshot an install set aside to replace and never deleted — it stopped between the two — is removed once it has been aside for a day, and left alone before that, while the install may still be deleting it; a `.partial-` copy an install stopped short of finishing is swept the same way, once it too has aged a day.
    @Test
    func whatAnUnfinishedInstallSetAsideIsSweptOnceADayOld() throws {
        let scratch = try Scratch()
        let snapshots = scratch.prune.store.snapshotsDirectory
        let stale = snapshots.appendingPathComponent(".stale-\(UUID().uuidString)", isDirectory: true)
        let partial = snapshots.appendingPathComponent(".partial-\(UUID().uuidString)", isDirectory: true)
        for directory in [stale, partial] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Scratch.payload.write(to: directory.appendingPathComponent("payload"))
            try Scratch.age([directory], daysAgo: 30)
        }

        // Its age is how long ago it was set aside — a rename, which no test can backdate — so the day passes on the plan's clock instead.
        let today = scratch.prune.plan(keepingBinary: "aa", installedBinary: nil, now: Date())
        let outcome = scratch.prune.execute(scratch.prune.plan(keepingBinary: "aa", installedBinary: nil, now: Date().addingTimeInterval(2 * RunnerPrune.recentUse)))

        #expect(today.removals.isEmpty)
        #expect(Set(today.kept.map(\.url)) == [stale, partial])
        #expect(Set(outcome.removed.map(\.url)) == [stale, partial])
        #expect(!FileManager.default.fileExists(atPath: stale.path))
        #expect(!FileManager.default.fileExists(atPath: partial.path))
        #expect(outcome.freed >= 2 * Scratch.payload.count)
    }
}

private extension RunnerPruneTests {
    /// A scratch `~/.simwalk`: the runner store and the builds directory beside it.
    struct Scratch {
        let directory: TemporaryDirectory
        let prune: RunnerPrune

        init() throws {
            directory = try TemporaryDirectory()
            prune = RunnerPrune(
                store: RunnerStore(directory: directory.url.appendingPathComponent("runner", isDirectory: true)),
                builds: RunnerBuilds(directory: directory.url.appendingPathComponent("runner-builds", isDirectory: true))
            )
        }

        /// What every snapshot and build holds, so a removal frees something countable.
        static var payload: Data {
            Data(repeating: 7, count: 8192)
        }

        /// A binding, its snapshot and the snapshot's build, as an install and a walk leave them, last touched the given number of days ago.
        func install(binary: String, commit: String, daysAgo: Double, buildDaysAgo: Double? = nil) throws -> Runner {
            let store = prune.store
            let snapshot = store.snapshotsDirectory.appendingPathComponent(commit, isDirectory: true)
            let project = RunnerProject.project(under: snapshot.path)
            try FileManager.default.createDirectory(atPath: project, withIntermediateDirectories: true)
            try Self.payload.write(to: URL(fileURLWithPath: project).appendingPathComponent("project.pbxproj"))
            try FileManager.default.createDirectory(at: store.bindingsDirectory, withIntermediateDirectories: true)
            let binding = store.bindingsDirectory.appendingPathComponent("\(binary).json")
            try JSONEncoder()
                .encode(RunnerStore.Binding(commit: commit, contentHash: "hash", snapshot: snapshot.path, checkout: "/checkout"))
                .write(to: binding)
            let build = try build(project: project, commit: commit, daysAgo: buildDaysAgo ?? daysAgo)
            try Self.age([binding, snapshot], daysAgo: daysAgo)
            return Runner(binding: binding, snapshot: snapshot, build: build)
        }

        /// A build directory as a walk leaves it, recording the project it builds.
        func build(project: String, commit: String? = nil, daysAgo: Double) throws -> URL {
            let source = RunnerSource(projectPath: project, commit: commit, origin: commit == nil ? .checkout : .installed)
            try prune.builds.recordUse(of: source)
            let build = prune.builds.directory(for: source)
            try Self.payload.write(to: build.appendingPathComponent("payload"))
            try Self.age(RunnerBuilds.useMarkers(in: build), daysAgo: daysAgo)
            return build
        }

        /// A build made before records were kept: only Xcode's `info.plist` says what it builds.
        func legacyBuild(project: String, key: String, daysAgo: Double) throws -> URL {
            let build = prune.builds.directory.appendingPathComponent(key, isDirectory: true)
            try FileManager.default.createDirectory(at: build, withIntermediateDirectories: true)
            try PropertyListSerialization.data(fromPropertyList: ["WorkspacePath": project], format: .xml, options: 0)
                .write(to: build.appendingPathComponent("info.plist"))
            try Self.payload.write(to: build.appendingPathComponent("payload"))
            try Self.age(RunnerBuilds.useMarkers(in: build), daysAgo: daysAgo)
            return build
        }

        /// The name a prune sets a removal aside under, spelled out here rather than read from the source, so a rename of it is a change a test sees.
        static var setAsidePrefix: String {
            ".stale-prune-"
        }

        /// Whether the temporary directory's volume clones a copied file rather than duplicating its blocks, as APFS does.
        static var clonesFiles: Bool {
            (try? FileManager.default.temporaryDirectory.resourceValues(forKeys: [.volumeSupportsFileCloningKey]))?.volumeSupportsFileCloning == true
        }

        /// What a prune has set aside and not yet deleted, under the builds directory — the only place these tests set anything aside.
        var setAside: [URL] {
            entries(in: prune.builds.directory).filter { $0.lastPathComponent.hasPrefix(Scratch.setAsidePrefix) }
        }

        /// Every build directory recording `project`, under whatever name it has now — set aside included.
        func builds(of project: String) -> [URL] {
            entries(in: prune.builds.directory).filter { prune.builds.builtProject(at: $0) == project }
        }

        private func entries(in directory: URL) -> [URL] {
            ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []).map { directory.appendingPathComponent($0) }
        }

        static func age(_ urls: [URL], daysAgo: Double) throws {
            let date = Date().addingTimeInterval(-daysAgo * 24 * 60 * 60)
            for url in urls where FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
            }
        }
    }

    /// The three paths one install and its walk leave behind.
    struct Runner {
        let binding: URL
        let snapshot: URL
        let build: URL

        var all: [URL] {
            [binding, snapshot, build]
        }
    }
}
