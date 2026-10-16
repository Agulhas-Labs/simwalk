//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Reclaims the runner snapshots, bindings and build directories nothing will walk again (SimWalk#22).
///
/// Every install adds a snapshot and every snapshot walked adds a ~250 MB build, and a working tree's build (~140 MB) lives outside the tree, so removing a worktree never reclaims it. Nothing deleted them: an old one may belong to a session still running an old binary, and deleting the runner a binary was installed with breaks every walk from it.
///
/// **The rule, conservative on purpose** — so a prune needs no dry run to be safe, and `--dry-run` exists to show it, not to guard it. Kept:
///
/// 1. the runner paired with the binary doing the pruning, and the one paired with the installed binary (`~/.local/bin/simwalk`), whatever their ages — the installed one is what every walk from a new session builds, and a prune run by any other binary must not decide it is old;
/// 2. the runners of the ``recentInstalls`` bindings written most recently besides the pruning binary's — the binaries a long-running session is most likely still on;
/// 3. anything installed or walked within ``recentUse`` — a walk rewrites its build's record as soon as it has resolved its runner, and ``execute(_:)`` checks that record again on both sides of setting each removal aside under a name no walk resolves (SimWalk#33), so a build is never pulled out from under a walk, and neither is the snapshot it builds or the binding that names it;
/// 4. a working tree's build whose project is still on disk.
///
/// Everything else under the store and the builds directory is removed, by exact path, one directory level down and never outside them: a binding and its snapshot, a snapshot's build, a working tree's build whose checkout has gone, a build that says nothing about what it builds, and what an unfinished prune set aside, or an unfinished install over a day ago.
public struct RunnerPrune {
    public let store: RunnerStore
    public let builds: RunnerBuilds

    public init(store: RunnerStore, builds: RunnerBuilds) {
        self.store = store
        self.builds = builds
    }

    /// The machine's own store and builds.
    public static func standard() -> RunnerPrune {
        RunnerPrune(store: .standard(), builds: .standard())
    }

    /// How many other bindings are kept besides the pruning binary's, newest first.
    public static let recentInstalls = 3

    /// How recently a runner must have been installed or walked to be kept whatever else holds.
    public static let recentUse: TimeInterval = 24 * 60 * 60

    /// What a prune would remove and keep for the binary whose SHA-256 is `binaryHash`, at `now` — without touching anything.
    ///
    /// `installedHash` is the SHA-256 of the installed binary, whose runner is kept whichever binary prunes; `nil` when there is none to read.
    public func plan(keepingBinary binaryHash: String, installedBinary installedHash: String?, now: Date) -> Plan {
        let recent = now.addingTimeInterval(-Self.recentUse)
        var kept: [Entry] = []
        var removals: [Entry] = []

        let bindings = readBindings()
        let others = bindings.filter { $0.hash != binaryHash }.sorted { $0.modified > $1.modified }
        let recentOthers = Set(others.prefix(Self.recentInstalls).map(\.url))

        let buildEntries = children(of: builds.directory).map { url in
            (url: url, project: builds.builtProject(at: url), used: lastUse(of: RunnerBuilds.useMarkers(in: url)))
        }

        // Which snapshots stay: those a kept binding names, and those installed or walked recently.
        var keptSnapshots: [String: String] = [:]
        var keptBindings: [URL: String] = [:]
        for binding in bindings {
            let reason: String? = if binding.hash == binaryHash {
                "paired with this binary"
            } else if binding.hash == installedHash {
                "paired with the installed binary"
            } else if recentOthers.contains(binding.url) {
                "among the \(Self.recentInstalls) most recent installs"
            } else if binding.modified > recent {
                "installed within the last \(Self.recentUseWording)"
            } else if binding.binding == nil {
                "unreadable, so not attributable to a runner"
            } else {
                nil
            }
            guard let reason else { continue }
            keptBindings[binding.url] = reason
            if let name = binding.snapshotName {
                keptSnapshots[name] = keptSnapshots[name] ?? reason
            }
        }
        let snapshots = children(of: store.snapshotsDirectory)
        for snapshot in snapshots where keptSnapshots[snapshot.lastPathComponent] == nil {
            if lastUse(of: [snapshot]) > recent {
                keptSnapshots[snapshot.lastPathComponent] = "installed within the last \(Self.recentUseWording)"
            }
        }
        for build in buildEntries where build.used > recent {
            if let name = snapshotName(of: build.project), keptSnapshots[name] == nil {
                keptSnapshots[name] = "walked within the last \(Self.recentUseWording)"
            }
        }

        // A binding whose snapshot stays is itself worth keeping: it is a few hundred bytes and still true.
        for binding in bindings {
            if let reason = keptBindings[binding.url] {
                kept.append(Entry(url: binding.url, bytes: 0, reason: reason))
            } else if let name = binding.snapshotName, let reason = keptSnapshots[name] {
                kept.append(Entry(url: binding.url, bytes: 0, reason: "its snapshot is kept — \(reason)"))
            } else {
                removals.append(Entry(url: binding.url, bytes: Self.bytes(at: binding.url), reason: "an older install"))
            }
        }
        for snapshot in snapshots {
            if let reason = keptSnapshots[snapshot.lastPathComponent] {
                kept.append(Entry(url: snapshot, bytes: 0, reason: reason))
            } else {
                removals.append(Entry(url: snapshot, bytes: Self.bytes(at: snapshot), reason: "no kept install is paired with it"))
            }
        }
        for build in buildEntries {
            let decision = decide(build: build.project, used: build.used, since: recent, keptSnapshots: keptSnapshots)
            if decision.keep {
                kept.append(Entry(url: build.url, bytes: 0, reason: decision.reason))
            } else {
                // A build whose checkout is gone is removed however recently it was walked, so only a walk after this plan spares it (SimWalk#97).
                let cutoff = decision.checkoutGone ? now : nil
                removals.append(Entry(url: build.url, bytes: Self.bytes(at: build.url), reason: decision.reason, usedSince: cutoff))
            }
        }
        // What an earlier prune set aside and never deleted (SimWalk#33), judged by the same use check its own removal made.
        for aside in setAsideEntries() {
            if isUsed(aside, since: recent) {
                kept.append(Entry(url: aside, bytes: 0, reason: "set aside by an unfinished prune, but used within the last \(Self.recentUseWording)"))
            } else {
                removals.append(Entry(url: aside, bytes: Self.bytes(at: aside), reason: "set aside by a prune that did not finish removing it"))
            }
        }
        // What an install set aside or half-copied and never finished (SimWalk#34), once it has been aside for longer than a walk's grace: an install deletes its own within seconds, so one that old is an install that stopped, not one in flight.
        for stale in installSetAsideEntries() {
            if lastChange(of: stale) > recent {
                kept.append(Entry(url: stale, bytes: 0, reason: "left by an install within the last \(Self.recentUseWording), which may still be removing it"))
            } else {
                removals.append(Entry(url: stale, bytes: Self.bytes(at: stale), reason: "left by an install that did not finish, over \(Self.recentUseWording) ago"))
            }
        }
        return Plan(removals: removals, kept: kept, usedSince: recent)
    }

    /// Removes what `plan` names — bindings first, so no new walk resolves a snapshot about to go, then snapshots, then builds — answering what went and what could not.
    ///
    /// A removal whose parent is not one of the three directories this prune owns is refused rather than attempted: a plan is only ever made by listing them, and this is where that stops being an assumption.
    ///
    /// **Each removal is checked against its use again immediately before it happens.** Planning sizes every removal, which takes seconds over builds of a few hundred megabytes, and a walk that resolved its runner meanwhile has recorded its use since — so anything used after the removal's cutoff — its ``Entry/usedSince``, or ``Plan/usedSince`` where it names none — is spared, the binding and snapshot a walked build names included.
    ///
    /// **And a removal is set aside before it is deleted, so the check and the removal cannot be raced** (SimWalk#33). Deleting a build takes seconds too, and a walk that resolved the path in that time — a working tree's checkout re-created where it was, say — wrote into a directory that was being emptied under it. So the entry is first renamed, atomically and in place, to a ``setAsidePrefix`` name that no walk resolves and ``children(of:)`` never lists, and checked again under that name: a use recorded before the rename is in the renamed entry, which is put back and spared; a use after it finds nothing at the path and starts afresh where the deletion cannot reach. Only the renamed entry is ever deleted. An entry that cannot be set aside is a failure, never a removal; one used while set aside that cannot be put back, because a walk has already re-created the path, stays set aside and is a failure, never spared; and one set aside and never deleted — a deletion refused, or a prune stopped between the two — is swept by a later plan once nothing has used it in ``recentUse``.
    public func execute(_ plan: Plan) -> Outcome {
        execute(plan, racing: { _ in })
    }

    /// ``execute(_:)``, calling `race` with each removal's path at the moment a walk resolving that path would race the removal — the seam a test uses to be that walk (SimWalk#33).
    func execute(_ plan: Plan, racing race: (URL) -> Void) -> Outcome {
        let owned = [store.bindingsDirectory, store.snapshotsDirectory, builds.directory].map(\.standardizedFileURL.path)
        var removed: [Entry] = []
        var spared: [Entry] = []
        var failed: [Failure] = []
        for entry in plan.removals {
            guard owned.contains(entry.url.deletingLastPathComponent().standardizedFileURL.path) else {
                failed.append(Failure(entry: entry, reason: "not directly under a directory this tool owns"))
                continue
            }
            switch remove(entry, since: entry.usedSince ?? plan.usedSince, racing: race) {
            case .removed:
                removed.append(entry)
            case let .spared(reason):
                spared.append(Entry(url: entry.url, bytes: 0, reason: reason))
            case let .failed(reason):
                failed.append(Failure(entry: entry, reason: reason))
            }
        }
        return Outcome(removed: removed, spared: spared, failed: failed)
    }

    /// What a removal is renamed to begin with before it is deleted, so no walk can resolve it and no plan lists it as a runner (SimWalk#33) — distinct from ``installSetAsidePrefix``, which is an install's to finish.
    static var setAsidePrefix: String {
        ".stale-prune-"
    }

    /// What an install renames a snapshot it is replacing to, followed by a UUID, before deleting it (`RunnerStore`) — left alone while that install may still be deleting it, and swept once it has been aside for ``recentUse`` (SimWalk#34).
    static var installSetAsidePrefix: String {
        ".stale-"
    }

    /// What an install copies a new snapshot into before renaming it into place (`RunnerStore`) — an install that stopped mid-copy leaves one, swept on the same terms as ``installSetAsidePrefix`` (SimWalk#34).
    static var installPartialPrefix: String {
        ".partial-"
    }

    /// ``recentUse`` as a line prints it.
    public static var recentUseWording: String {
        "\(Int(recentUse / 3600)) h"
    }
}

private extension RunnerPrune {
    /// A binding file, what it decodes to, and when it was written.
    struct BindingFile {
        let url: URL
        let hash: String
        let binding: RunnerStore.Binding?
        let modified: Date

        /// The name of the snapshot directory the binding names, matched to one under the store by name alone.
        ///
        /// By name rather than by whole path, because the two can spell one directory differently — through a symlink, or `/private/var` against `/var` — and a mismatch here would let a kept binding's snapshot be removed. Matching by name can only keep more than it needs to, never less.
        var snapshotName: String? {
            binding.map { URL(fileURLWithPath: $0.snapshot).standardizedFileURL.lastPathComponent }
        }
    }

    func readBindings() -> [BindingFile] {
        children(of: store.bindingsDirectory)
            .filter { $0.pathExtension == "json" }
            .map(bindingFile(at:))
    }

    func bindingFile(at url: URL) -> BindingFile {
        BindingFile(
            url: url,
            hash: url.deletingPathExtension().lastPathComponent,
            binding: (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(RunnerStore.Binding.self, from: $0) },
            modified: lastUse(of: [url])
        )
    }

    /// How one removal went.
    enum Removal {
        case removed
        case spared(String)
        case failed(String)
    }

    /// Sets `entry` aside, checks its use on both sides of that, and deletes it only under its set-aside name (SimWalk#33) — see ``execute(_:)``.
    func remove(_ entry: Entry, since date: Date, racing race: (URL) -> Void) -> Removal {
        guard !isUsed(entry.url, since: date) else {
            return .spared("walked or installed since the prune was planned")
        }
        let alreadyAside = entry.url.lastPathComponent.hasPrefix(Self.setAsidePrefix)
        let aside = alreadyAside ? entry.url : entry.url.deletingLastPathComponent()
            .appendingPathComponent("\(Self.setAsidePrefix)\(UUID().uuidString)-\(entry.url.lastPathComponent)")
        if !alreadyAside {
            do {
                try Self.rename(entry.url, to: aside)
            } catch {
                return .failed("could not be set aside for removal, so was left alone — \(error.localizedDescription)")
            }
        }
        race(entry.url)
        if isUsed(entry.url, since: date, at: aside) {
            guard !alreadyAside else { return .spared("walked or installed since the prune was planned") }
            do {
                try Self.rename(aside, to: entry.url)
                return .spared("used as it was set aside for removal, and put back")
            } catch {
                return .failed("used as it was set aside for removal, and could not be put back — \(error.localizedDescription); left as \(aside.lastPathComponent), which a later prune removes once it goes \(Self.recentUseWording) unwalked")
            }
        }
        do {
            try FileManager.default.removeItem(at: aside)
            return .removed
        } catch {
            return .failed("set aside as \(aside.lastPathComponent) but not deleted — \(error.localizedDescription); a later prune removes it")
        }
    }

    /// Renames `source` to `destination` in one step that refuses to replace anything already there — so putting an entry back can never land on a path a walk has re-created meanwhile.
    static func rename(_ source: URL, to destination: URL) throws {
        let status = source.withUnsafeFileSystemRepresentation { from in
            destination.withUnsafeFileSystemRepresentation { to in
                guard let from, let to else { return Int32(-1) }
                return renamex_np(from, to, UInt32(RENAME_EXCL))
            }
        }
        guard status == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EINVAL)
        }
    }

    /// The entries a prune set aside and never deleted, directly under the directories it owns.
    func setAsideEntries() -> [URL] {
        [store.bindingsDirectory, store.snapshotsDirectory, builds.directory].flatMap { directory in
            ((try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? [])
                .filter { $0.hasPrefix(Self.setAsidePrefix) }
                .sorted()
                .map { directory.appendingPathComponent($0) }
        }
    }

    /// What an install left under the snapshots directory, the one place it writes anything aside: `.stale-<UUID>`, a snapshot it was replacing, and `.partial-<UUID>`, a copy it never finished — a prune's own `.stale-prune-` names are not UUIDs, so never counted here.
    func installSetAsideEntries() -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(atPath: store.snapshotsDirectory.path)) ?? [])
            .filter { name in
                [Self.installSetAsidePrefix, Self.installPartialPrefix].contains { name.hasPrefix($0) && UUID(uuidString: String(name.dropFirst($0.count))) != nil }
            }
            .sorted()
            .map { store.snapshotsDirectory.appendingPathComponent($0) }
    }

    /// When the entry at `url` last changed in any way, its renaming included — so a snapshot set aside today reads as today however long ago its contents were written.
    func lastChange(of url: URL) -> Date {
        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .attributeModificationDateKey])
        return [values?.contentModificationDate, values?.attributeModificationDate].compactMap(\.self).max() ?? .distantPast
    }

    /// Whether the binding, snapshot or build at `url` has been installed or walked since `date` — read from disk now, not from the plan, and from `location` where the entry has been set aside under another name.
    func isUsed(_ url: URL, since date: Date, at location: URL? = nil) -> Bool {
        let location = location ?? url
        let parent = url.deletingLastPathComponent().standardizedFileURL.path
        if parent == builds.directory.standardizedFileURL.path {
            return lastUse(of: RunnerBuilds.useMarkers(in: location)) > date
        }
        let snapshot: String? = if parent == store.snapshotsDirectory.standardizedFileURL.path {
            url.lastPathComponent
        } else {
            bindingFile(at: location).snapshotName
        }
        guard lastUse(of: [location]) <= date else { return true }
        guard let snapshot else { return false }
        return lastUse(of: [store.snapshotsDirectory.appendingPathComponent(snapshot)]) > date || walkedSnapshots(since: date).contains(snapshot)
    }

    /// The snapshots whose builds have been walked since `date`.
    func walkedSnapshots(since date: Date) -> Set<String> {
        Set(children(of: builds.directory)
            .filter { lastUse(of: RunnerBuilds.useMarkers(in: $0)) > date }
            .compactMap { snapshotName(of: builds.builtProject(at: $0)) })
    }

    /// What ``decide(build:used:since:keptSnapshots:)`` says of one build directory.
    struct BuildDecision {
        let keep: Bool
        let reason: String
        /// Whether it goes because the working tree it builds is gone, which no walk before the plan can spare (SimWalk#97).
        var checkoutGone = false
    }

    /// Whether a build directory stays, and why — a snapshot's build with its snapshot, a working tree's while its project exists — and whether it goes because its checkout is gone.
    ///
    /// A working tree's build whose project has gone is removed however recently it was walked (SimWalk#97): a development build builds the checkout it lives in, so nothing can walk it again, and `install-hook` prunes right after a merge, the moment worktrees go — the 24 h grace would keep every one of them.
    func decide(build project: String?, used: Date, since recent: Date, keptSnapshots: [String: String]) -> BuildDecision {
        if let project, snapshotName(of: project) == nil, !FileManager.default.fileExists(atPath: project) {
            return BuildDecision(keep: false, reason: "builds \(project.tildedPath), which no longer exists", checkoutGone: true)
        }
        if used > recent {
            return BuildDecision(keep: true, reason: "walked within the last \(Self.recentUseWording)")
        }
        guard let project else {
            return BuildDecision(keep: false, reason: "records no project, and has not been walked in \(Self.recentUseWording)")
        }
        if let name = snapshotName(of: project) {
            if let reason = keptSnapshots[name] {
                return BuildDecision(keep: true, reason: "builds a kept snapshot — \(reason)")
            }
            return BuildDecision(keep: false, reason: "builds a snapshot that is not kept")
        }
        if FileManager.default.fileExists(atPath: project) {
            return BuildDecision(keep: true, reason: "builds \(project.tildedPath), which is still there")
        }
        return BuildDecision(keep: false, reason: "builds \(project.tildedPath), which no longer exists", checkoutGone: true)
    }

    /// The snapshot a project path lies inside, by directory name, or `nil` for a project anywhere else.
    func snapshotName(of project: String?) -> String? {
        guard let project else { return nil }
        let prefix = store.snapshotsDirectory.standardizedFileURL.path + "/"
        let path = URL(fileURLWithPath: project).standardizedFileURL.path
        guard path.hasPrefix(prefix) else { return nil }
        return path.dropFirst(prefix.count).split(separator: "/").first.map(String.init)
    }

    /// The entries directly under `directory`, leaving out dot-names — an install's `.partial-` and `.stale-` directories are in flight, and not a prune's to judge as runners (``installSetAsideEntries()`` lists both to sweep once a day old), and a prune's own set-aside entries are no runner's (``setAsideEntries()`` lists those).
    func children(of directory: URL) -> [URL] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return names
            .filter { !$0.hasPrefix(".") }
            .sorted()
            .map { directory.appendingPathComponent($0) }
    }

    /// The newest modification date among `urls` that exist.
    func lastUse(of urls: [URL]) -> Date {
        urls
            .compactMap { try? $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }
            .max() ?? .distantPast
    }

    /// What removing `url` frees on its volume, a directory's contents included, without following links out of it.
    ///
    /// Not what it occupies (SimWalk#33): a runner snapshot is made by `copyItem`, which on APFS clones the checkout's files, and a clone shares its blocks with the file it was cloned from — removing it frees none of them while the checkout stands, and counting them claimed a snapshot's whole size as freed. So each file counts its private bytes, the ones no clone or volume snapshot shares and a deletion frees at once; and, on a volume that cannot say, which is one that cannot clone, the space allocated to it. A floor, then: bytes two removals share only with each other count for neither.
    static func bytes(at url: URL) -> Int {
        var total = freedBytes(of: url)
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey]) else { return total }
        for case let file as URL in enumerator {
            total += freedBytes(of: file)
        }
        return total
    }

    /// What removing the one file or directory entry at `url` frees — see ``bytes(at:)``.
    static func freedBytes(of url: URL) -> Int {
        privateBytes(of: url) ?? (try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0
    }

    /// The bytes of the file at `url` that no clone or volume snapshot shares (`ATTR_CMNEXT_PRIVATESIZE`), or `nil` where its volume does not say — `getattrlist` reports which attributes it answered, and one it did not answer is never read as zero.
    static func privateBytes(of url: URL) -> Int? {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = attrgroup_t(ATTR_CMN_RETURNED_ATTRS)
        request.forkattr = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE)
        // The reply: its own length, the set of attributes answered, then the private size.
        let returnedOffset = MemoryLayout<UInt32>.size
        let sizeOffset = returnedOffset + MemoryLayout<attribute_set_t>.size
        var reply = [UInt8](repeating: 0, count: sizeOffset + MemoryLayout<off_t>.size)
        let status = url.withUnsafeFileSystemRepresentation { path in
            guard let path else { return Int32(-1) }
            return getattrlist(path, &request, &reply, reply.count, UInt32(FSOPT_ATTR_CMN_EXTENDED | FSOPT_NOFOLLOW))
        }
        guard status == 0 else { return nil }
        return reply.withUnsafeBytes { raw in
            let returned = raw.loadUnaligned(fromByteOffset: returnedOffset, as: attribute_set_t.self)
            guard returned.forkattr & attrgroup_t(ATTR_CMNEXT_PRIVATESIZE) != 0 else { return nil }
            return Int(raw.loadUnaligned(fromByteOffset: sizeOffset, as: off_t.self))
        }
    }
}

public extension RunnerPrune {
    /// One path a prune removes or keeps, and why.
    struct Entry: Equatable, Sendable {
        public let url: URL
        /// What it occupies on disk; counted only for a removal.
        public let bytes: Int
        public let reason: String
        /// For a removal, the moment a use must postdate to spare it at ``RunnerPrune/execute(_:)``, or `nil` for the plan's own ``Plan/usedSince``.
        ///
        /// A working tree's build whose checkout is gone carries the plan's `now`: it is removed however recently it was walked (SimWalk#97), so only a walk after the plan was made spares it.
        public let usedSince: Date?

        public init(url: URL, bytes: Int, reason: String, usedSince: Date? = nil) {
            self.url = url
            self.bytes = bytes
            self.reason = reason
            self.usedSince = usedSince
        }
    }

    /// What a prune would do.
    struct Plan: Equatable, Sendable {
        public let removals: [Entry]
        public let kept: [Entry]
        /// The moment a use must postdate to keep a runner — ``RunnerPrune/recentUse`` before the plan's `now` — which ``RunnerPrune/execute(_:)`` checks each removal against again, unless the removal names its own ``Entry/usedSince``.
        public let usedSince: Date

        /// What the removals occupy.
        public var bytes: Int {
            removals.reduce(0) { $0 + $1.bytes }
        }
    }

    /// A removal that did not happen, and why.
    struct Failure: Equatable, Sendable {
        public let entry: Entry
        public let reason: String
    }

    /// What a prune did.
    struct Outcome: Equatable, Sendable {
        public let removed: [Entry]
        /// Planned removals left in place because they were used after the plan was made.
        public let spared: [Entry]
        public let failed: [Failure]

        /// What the removals freed.
        public var freed: Int {
            removed.reduce(0) { $0 + $1.bytes }
        }
    }
}
