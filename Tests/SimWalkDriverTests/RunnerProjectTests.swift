//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkDriver
import SimWalkTestSupport
import Testing

/// Which runner a walk builds (SimWalk#16): an installed binary builds the snapshot it was installed with, and nothing a checkout does afterwards reaches it.
///
/// Real `git` in scratch checkouts, because the claims are about what a snapshot holds after the checkout it came from has moved on — which a stub could only restate.
///
/// **No longer serialized** (SimWalk#21), on a measurement rather than a diagnosis. Run in parallel on 2026-09-10 these hung three full runs of three, twelve of them parked in `Shell.run`'s pipe drains with no `git` child alive to close anything, and `lsof` on an earlier hang found one pipe with both ends open in the test process itself. That drain was a thread blocked in `readDataToEndOfFile`; it was replaced by the `DispatchSource` `Drain` on 2026-09-14, which can be cancelled and cannot strand a reader, and the hang has not reproduced since — twenty un-serialized full runs on the machine that used to hang three of three, ten of them on the `Shell` that predates SimWalk#21's own changes. So what this suite was avoiding appears to have been fixed four days before those changes, and they are insurance rather than the cure.
///
/// **A green run is evidence, not proof**: the hang was load- and timing-dependent (a review's eighteen parallel runs on another machine never reproduced it either), and its failure shape is a run that never ends rather than a red test. If it returns, serialize this suite again and say so here — do not chase it from `ShellTests`, where `callsMadeAtOnceEachGetTheirOwnOutputAndNoneIsLeftWaiting` is a load gate that passes either way.
struct RunnerProjectTests {
    /// The measured failure: an installed binary built whatever its checkout held at the moment of the walk, so a half-made edit there broke every walk on the machine.
    ///
    /// Installed, then edited in place: the walk builds the snapshot, which still holds what was committed, and names that commit.
    @Test
    func aninstalledBinaryBuildsTheSnapshotItWasPairedWithNotTheLiveCheckout() throws {
        let directory = try TemporaryDirectory()
        let checkout = try GitCheckoutFixture(in: directory)
        let store = RunnerStore(directory: directory.url.appendingPathComponent("runner"))
        _ = try store.install(checkout: checkout.url, binaryHash: Self.installed, run: Self.run)
        try checkout.write("// a half-made edit\n", to: Self.projectFile)

        let source = try Self.resolve(checkout: checkout, store: store)
        let built = try String(contentsOf: URL(fileURLWithPath: source.projectPath).appendingPathComponent("project.pbxproj"), encoding: .utf8)

        #expect(source.origin == .installed)
        #expect(source.projectPath.hasPrefix(store.snapshotsDirectory.path))
        #expect(try source.commit == checkout.head())
        #expect(built == "// the runner, as committed\n")
    }

    /// The fixture's own `git` cannot deadlock on what it prints to stderr (SimWalk#31): a pipe nobody drained filled at a buffer's worth and parked both sides.
    @Test(.timeLimit(.minutes(1)))
    func aGitThatSaysMoreThanABufferOnStderrStillReturns() throws {
        let directory = try TemporaryDirectory()
        let checkout = try GitCheckoutFixture(in: directory)

        let printed = try checkout.git("-c", "alias.noisy=!head -c 262144 /dev/zero >&2", "noisy")

        #expect(printed.isEmpty)
    }

    /// A binary copied in without an install has no runner of its own, and refuses rather than borrowing one — naming its own hash and the commit the latest install paired with some other binary.
    @Test
    func abinaryInstalledWithoutARunnerRefusesNamingBothSides() throws {
        let directory = try TemporaryDirectory()
        let checkout = try GitCheckoutFixture(in: directory)
        let store = RunnerStore(directory: directory.url.appendingPathComponent("runner"))
        let installed = try store.install(checkout: checkout.url, binaryHash: Self.installed, run: Self.run)

        let thrown = try #require(#expect(throws: RunnerProjectError.self) {
            try Self.resolve(checkout: checkout, store: store, binaryHash: Self.copiedIn)
        })

        // The refusal also names the shipped place it looked (`/Users/x/.local/share/simwalk`), which the packaged-runner tests hold.
        guard case let .notInstalled(hash, latest, variable, shipped, _) = thrown else {
            Issue.record("expected notInstalled, got \(thrown)")
            return
        }

        #expect(hash == Self.copiedIn)
        #expect(latest == installed.binding)
        #expect(variable == RunnerProject.overrideVariable)
        #expect(shipped?.contains("/Users/x/.local/share/simwalk") == true)
        #expect(thrown.description.contains("sha256 \(String(Self.copiedIn.prefix(8)))"))
        #expect(thrown.description.contains("runner \(String(installed.binding.commit.prefix(8)))"))
        #expect(thrown.description.contains("simwalk install-hook"))
    }

    /// A process launched from an older binary keeps finding the runner installed with *it*, after a newer install — the long-running MCP server's case.
    @Test
    func anolderBinaryKeepsItsOwnRunnerAfterANewerInstall() throws {
        let directory = try TemporaryDirectory()
        let checkout = try GitCheckoutFixture(in: directory)
        let store = RunnerStore(directory: directory.url.appendingPathComponent("runner"))
        let first = try store.install(checkout: checkout.url, binaryHash: Self.installed, run: Self.run)
        try checkout.write("// the next runner\n", to: Self.projectFile)
        try checkout.commit("the next runner")
        let second = try store.install(checkout: checkout.url, binaryHash: Self.copiedIn, run: Self.run)

        #expect(try Self.resolve(checkout: checkout, store: store, binaryHash: Self.installed).commit == first.binding.commit)
        #expect(try Self.resolve(checkout: checkout, store: store, binaryHash: Self.copiedIn).commit == second.binding.commit)
        #expect(first.binding.snapshot != second.binding.snapshot)
    }

    /// A development build lives inside the checkout it was built from, so the working tree *is* its runner — edits included, and said to be.
    @Test
    func adevelopmentBuildInsideItsCheckoutBuildsThatWorkingTreeAndSaysItIsDirty() throws {
        let directory = try TemporaryDirectory()
        let checkout = try GitCheckoutFixture(in: directory)
        try checkout.write("// an edit in progress\n", to: Self.projectFile)

        let source = try Self.resolve(checkout: checkout, store: RunnerStore(directory: directory.url), executable: checkout.url.appendingPathComponent(".build/debug/simwalk"))

        #expect(source.origin == .checkout)
        #expect(source.projectPath == RunnerProject.project(under: checkout.url.path))
        #expect(try source.commit == "\(checkout.head())-dirty")
    }

    /// The override is built as named, and named by its own commit.
    @Test
    func theoverrideIsBuiltAsNamedAndCarriesItsCommit() throws {
        let directory = try TemporaryDirectory()
        let checkout = try GitCheckoutFixture(in: directory)
        let project = RunnerProject.project(under: checkout.url.path)

        let source = try RunnerProject.resolve(
            environment: [RunnerProject.overrideVariable: project],
            executable: nil,
            binaryHash: { nil },
            checkout: directory.url,
            store: RunnerStore(directory: directory.url),
            run: Self.run
        )

        #expect(try source == RunnerSource(projectPath: project, commit: checkout.head(), origin: .override))
    }

    /// A dirty tree is snapshotted as what is on disk and named as one — never passed off as its commit — and committing it makes a second, clean snapshot rather than overwriting the first.
    @Test
    func adirtyTreesSnapshotIsNamedAsOneAndIsNotTheCleanCommits() throws {
        let directory = try TemporaryDirectory()
        let checkout = try GitCheckoutFixture(in: directory)
        let store = RunnerStore(directory: directory.url.appendingPathComponent("runner"))
        try checkout.write("// uncommitted\n", to: Self.projectFile)
        let base = try checkout.head()

        let dirty = try store.install(checkout: checkout.url, binaryHash: Self.installed, run: Self.run)
        try checkout.commit("committed")
        let clean = try store.install(checkout: checkout.url, binaryHash: Self.copiedIn, run: Self.run)

        #expect(dirty.binding.commit.hasPrefix("\(base)-dirty."))
        #expect(try clean.binding.commit == checkout.head())
        #expect(dirty.binding.snapshot != clean.binding.snapshot)
        #expect(try String(contentsOf: URL(fileURLWithPath: dirty.binding.projectPath).appendingPathComponent("project.pbxproj"), encoding: .utf8) == "// uncommitted\n")
    }

    /// Installing the same commit for another binary pairs the snapshot already on disk rather than copying it again under a walk that may be building it; installing it again for the same binary changes nothing.
    @Test
    func reinstallingACommitReusesItsSnapshot() throws {
        let directory = try TemporaryDirectory()
        let checkout = try GitCheckoutFixture(in: directory)
        let store = RunnerStore(directory: directory.url.appendingPathComponent("runner"))

        let first = try store.install(checkout: checkout.url, binaryHash: Self.installed, run: Self.run)
        let second = try store.install(checkout: checkout.url, binaryHash: Self.copiedIn, run: Self.run)
        let again = try store.install(checkout: checkout.url, binaryHash: Self.installed, run: Self.run)

        #expect(first.outcome == .snapshotted)
        #expect(second.outcome == .reusedSnapshot)
        #expect(again.outcome == .unchanged)
        #expect(first.binding == second.binding)
    }

    /// The review's blocking case: re-running the install from a checkout that has moved on — another commit, or edits on disk — must not re-pair a binary with a runner from somewhere else.
    ///
    /// The binding is written once; the moved checkout is reported; `repoint` is the explicit way through.
    @Test
    func abindingIsWrittenOncePerBinary() throws {
        let directory = try TemporaryDirectory()
        let checkout = try GitCheckoutFixture(in: directory)
        let store = RunnerStore(directory: directory.url.appendingPathComponent("runner"))
        let first = try store.install(checkout: checkout.url, binaryHash: Self.installed, run: Self.run)
        try checkout.write("// the next branch\n", to: Self.projectFile)
        try checkout.commit("the next branch")
        let moved = try checkout.head()

        let kept = try store.install(checkout: checkout.url, binaryHash: Self.installed, run: Self.run)
        try checkout.write("// and an edit\n", to: Self.projectFile)
        let keptOverEdit = try store.install(checkout: checkout.url, binaryHash: Self.installed, run: Self.run)
        let repointed = try store.install(checkout: checkout.url, binaryHash: Self.installed, repoint: true, run: Self.run)

        #expect(kept.outcome == .kept(checkoutCommit: moved))
        #expect(kept.binding == first.binding)
        guard case .kept = keptOverEdit.outcome else {
            Issue.record("an edited checkout re-paired the binary: \(keptOverEdit.outcome)")
            return
        }
        #expect(repointed.outcome == .repointed(from: first.binding))
        #expect(repointed.binding.commit.hasPrefix("\(moved)-dirty."))
        #expect(store.binding(forBinary: Self.installed) == repointed.binding)
    }

    /// A snapshot that has gone is taken again by re-running the install from the checkout that still holds its commit, and the refusal a walk gives in the meantime says so — and names `--repoint-runner` for a checkout that has moved on.
    @Test
    func amissingSnapshotIsTakenAgainByAReinstallFromTheSameCommit() throws {
        let directory = try TemporaryDirectory()
        let checkout = try GitCheckoutFixture(in: directory)
        let store = RunnerStore(directory: directory.url.appendingPathComponent("runner"))
        let first = try store.install(checkout: checkout.url, binaryHash: Self.installed, run: Self.run)
        try FileManager.default.removeItem(atPath: first.binding.snapshot)
        let refusal = try #require(#expect(throws: RunnerProjectError.self) {
            try Self.resolve(checkout: checkout, store: store)
        })

        let again = try store.install(checkout: checkout.url, binaryHash: Self.installed, run: Self.run)

        #expect(refusal.description.contains("--repoint-runner"))
        #expect(again.outcome == .snapshotted)
        #expect(again.binding == first.binding)
        #expect(try Self.resolve(checkout: checkout, store: store).projectPath == first.binding.projectPath)
    }

    /// `status.showUntrackedFiles=no` hides an untracked file from `git status`, and the snapshot copies it all the same — so the tree is dirty, and the snapshot is not named for a commit that does not hold that file.
    @Test
    func anuntrackedFileStatusIsConfiguredToHideStillMakesTheTreeDirty() throws {
        let directory = try TemporaryDirectory()
        let checkout = try GitCheckoutFixture(in: directory)
        let store = RunnerStore(directory: directory.url.appendingPathComponent("runner"))
        try checkout.git("config", "status.showUntrackedFiles", "no")
        try checkout.write("// not committed\n", to: "Runner/SimWalkRunner/Extra.swift")

        let installed = try store.install(checkout: checkout.url, binaryHash: Self.installed, run: Self.run)

        #expect(installed.binding.commit.contains("-dirty."))
        #expect(FileManager.default.fileExists(atPath: URL(fileURLWithPath: installed.binding.snapshot).appendingPathComponent("Runner/SimWalkRunner/Extra.swift").path))
    }

    /// A file `git` was told to stop looking at reads clean with local edits in it, and those edits are what gets copied — so it makes the tree dirty.
    @Test(arguments: ["--skip-worktree", "--assume-unchanged"])
    func afileGitWasToldNotToWatchMakesTheTreeDirty(flag: String) throws {
        let directory = try TemporaryDirectory()
        let checkout = try GitCheckoutFixture(in: directory)
        let store = RunnerStore(directory: directory.url.appendingPathComponent("runner"))
        try checkout.git("update-index", flag, Self.projectFile)
        try checkout.write("// edited behind git's back\n", to: Self.projectFile)

        let installed = try store.install(checkout: checkout.url, binaryHash: Self.installed, run: Self.run)

        #expect(installed.binding.commit.contains("-dirty."))
        #expect(RunnerProject.commit(of: checkout.url, run: Self.run)?.hasSuffix("-dirty") == true)
    }

    /// A snapshot already on disk is reused only while its bytes are what its binding says; one that no longer matches — a poisoned or edited snapshot — is replaced rather than made permanent.
    @Test
    func asnapshotWhoseBytesNoLongerMatchIsReplacedNotReused() throws {
        let directory = try TemporaryDirectory()
        let checkout = try GitCheckoutFixture(in: directory)
        let store = RunnerStore(directory: directory.url.appendingPathComponent("runner"))
        let first = try store.install(checkout: checkout.url, binaryHash: Self.installed, run: Self.run)
        let snapshotted = URL(fileURLWithPath: first.binding.projectPath).appendingPathComponent("project.pbxproj")
        try Data("// not the commit\n".utf8).write(to: snapshotted)

        let second = try store.install(checkout: checkout.url, binaryHash: Self.copiedIn, run: Self.run)

        #expect(second.outcome == .snapshotted)
        #expect(second.binding.contentHash == first.binding.contentHash)
        #expect(try String(contentsOf: snapshotted, encoding: .utf8) == "// the runner, as committed\n")
    }

    /// The one shared build directory let an override walk and a default walk overwrite each other's products (SimWalk#16): a build directory is keyed by the project's path, so no two sources share one — and a working tree keeps its own across commits, where a cold build per commit bought nothing (the review).
    @Test
    func notwoSourcesShareABuildDirectoryAndAWorkingTreeKeepsItsOwn() {
        let snapshot = RunnerSource(projectPath: "/s/abc/Runner/SimWalkRunner.xcodeproj", commit: "abc1234500000000", origin: .installed)
        let override = RunnerSource(projectPath: "/clone/Runner/SimWalkRunner.xcodeproj", commit: "abc1234500000000", origin: .override)
        let otherClone = RunnerSource(projectPath: "/other/Runner/SimWalkRunner.xcodeproj", commit: "abc1234500000000", origin: .override)
        let moved = RunnerSource(projectPath: "/clone/Runner/SimWalkRunner.xcodeproj", commit: "def6789000000000", origin: .override)
        let edited = RunnerSource(projectPath: "/clone/Runner/SimWalkRunner.xcodeproj", commit: "def6789000000000-dirty", origin: .override)
        let distinct = [snapshot, override, otherClone].map(\.buildKey)

        #expect(Set(distinct).count == distinct.count)
        #expect(moved.buildKey == override.buildKey)
        #expect(edited.buildKey == override.buildKey)
        #expect(snapshot.buildKey.hasPrefix("abc12345-"))
        #expect(override.buildKey.hasPrefix("tree-"))
    }

    /// An override naming nothing is refused rather than falling through to a runner nobody asked for.
    @Test
    func anoverrideNamingNothingIsRefused() {
        #expect(throws: RunnerProjectError.overrideMissing(variable: RunnerProject.overrideVariable, path: "/nowhere.xcodeproj")) {
            try RunnerProject.resolve(
                environment: [RunnerProject.overrideVariable: "/nowhere.xcodeproj"],
                executable: nil,
                binaryHash: { nil },
                store: RunnerStore(directory: URL(fileURLWithPath: "/nowhere")),
                run: Self.run
            )
        }
    }

    private static func resolve(
        checkout: GitCheckoutFixture,
        store: RunnerStore,
        binaryHash: String = installed,
        executable: URL = URL(fileURLWithPath: "/Users/x/.local/bin/simwalk")
    ) throws -> RunnerSource {
        try RunnerProject.resolve(environment: [:], executable: executable, binaryHash: { binaryHash }, checkout: checkout.url, store: store, run: run)
    }

    private static var run: (String, [String]) throws -> Shell.Result {
        { try Shell().run($0, $1) }
    }

    private static var projectFile: String {
        "Runner/SimWalkRunner.xcodeproj/project.pbxproj"
    }

    /// The binary an install was run from.
    private static var installed: String {
        String(repeating: "1a", count: 32)
    }

    /// A binary copied into place with no install of its own.
    private static var copiedIn: String {
        String(repeating: "2b", count: 32)
    }
}
