//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
import SimWalkCore
import SimWalkDriver

/// `simwalk prune` — reclaims the runner snapshots and builds nothing will walk again (SimWalk#22), and says how much it freed.
///
/// The rule is ``RunnerPrune``'s and it is conservative — the runners paired with this binary and with the installed one, the most recent installs besides this binary's, anything walked or installed in the last day, and a working tree's build while its project is there are all kept — so the verb removes by default, and `--dry-run` shows the same plan without acting on it. `install-hook` runs the same prune after pairing the new runner.
struct PruneCommand: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(
            commandName: "prune",
            abstract: "Remove walk-runner snapshots and builds no kept install or live checkout uses, and report the space freed."
        )
    }

    @Flag(name: .customLong("dry-run"), help: "Say what would be removed and kept, and remove nothing.")
    var dryRun = false

    func run() throws {
        LaunchedBinary.capture()
        try run(log: .standard(), emit: StandardStreams.emit, emitError: StandardStreams.emitError, isStdoutPiped: StandardStreams.isStdoutPiped) { try answer() }
    }

    /// The same run with its three effects and the answer injectable.
    func run(log: UsageLog, emit: (String) -> Void, emitError: (String) -> Void, isStdoutPiped: () -> Bool = { false }, body: () throws -> Answer) throws {
        // An unmapped failure here is this tool's own store — never a caller's argument.
        try TimedCall.run(tool: "prune", target: nil, log: log, emit: emit, emitError: emitError, defaultFailureKind: .toolError, isStdoutPiped: isStdoutPiped, body: body)
    }

    func answer() throws -> Answer {
        guard let hash = LaunchedBinary.hash else {
            throw PruneRefusal.binaryUnreadable
        }
        return Self.answer(
            prune: .standard(),
            binary: (url: LaunchedBinary.url, hash: hash),
            checkout: RunnerProject.compiledCheckout,
            installedHash: RunnerProject.hash(ofExecutableAt: ExecutablePath.installed()),
            dryRun: dryRun,
            now: Date(),
            leases: DeviceLeasing(store: .standard()),
            journal: .beside(.standard())
        )
    }

    /// The same prune against a stated store, binary, checkout, installed binary and moment.
    ///
    /// **A development build does not prune** — a binary under `<checkout>/.build/`, whose pairing is gone at its next build: judging which installs are old by a binary nothing else runs is how the installed binary's runner came to be removed in the SimWalk#22 review. It still shows the plan with `--dry-run`.
    ///
    /// **A `--dry-run` from a development build plans with the installed binary's hash, when there is one** — otherwise the plan it shows is the dev binary's own, which a real run never acts on (it refuses) and which the installed binary's own run may not match, silently (SimWalk#33). With no installed binary found there is no truer plan to substitute, so the dry run keeps its own and says so instead.
    ///
    /// **A released clone's device-setup record goes with it** (`journal`; SimWalk#75): the record on a clone the release deleted has nothing left to hand back, so it is removed — unless the walk that wrote it still runs, or it does not read. **Orphans are swept too** (SimWalk#92): any other record whose walk is not running, whose device holds no lease, live or a clone's, and which no longer exists as a simulator is removed (a dead walk's record on a live device is what the next walk there hands back, so it stays; a simulator list that cannot be read removes nothing); a pid that cannot be judged counts as running, an unreadable record is kept. `nil` leaves the journal alone.
    ///
    /// **Lapsed leases are released too** (`leases`; Brief §2.4): each lease past its expiry, and each whose clone's holder is gone, is removed, and a device it cloned is shut down and deleted — no device a lease did not create. `nil` leaves the lease store alone.
    static func answer(prune: RunnerPrune, binary: (url: URL?, hash: String), checkout: URL?, installedHash: String?, dryRun: Bool, now: Date, leases: DeviceLeasing? = nil, journal: DeviceSetupJournal? = nil) -> Answer {
        let binaryHash = binary.hash
        let header = "binary: sha256 \(ShortHash.of(binaryHash)) · \(prune.store.directory.path.tildedPath), \(prune.builds.directory.path.tildedPath)"
        let isDevelopmentBuild = binary.url.flatMap { url in checkout.map { RunnerProject.isDevelopmentBuild(url, of: $0) } } ?? false
        if !dryRun, isDevelopmentBuild, let url = binary.url {
            return Answer(
                header: header,
                verdict: .reporting(qualifications: ["nothing was pruned — \(url.path.tildedPath) is a development build"], detail: "not pruned"),
                residue: ["run `simwalk prune` from the installed binary, or pass --dry-run to see what it would remove"] + ruleLines(installedFound: installedHash != nil)
            )
        }
        var qualifications: [String] = []
        var residue: [String] = []
        let planningHash: String = if dryRun, isDevelopmentBuild, let installedHash {
            installedHash
        } else {
            binaryHash
        }
        if dryRun, isDevelopmentBuild, installedHash == nil, let url = binary.url {
            residue.append("planned with a development binary — \(url.path.tildedPath) — since no installed binary was found to plan with instead; a real run from it would refuse")
        }
        if planningHash != binaryHash {
            residue.append("planned as the installed binary (sha256 \(ShortHash.of(planningHash))) would plan")
        }
        let plan = prune.plan(keepingBinary: planningHash, installedBinary: installedHash, now: now)
        var detail: String
        if dryRun {
            residue += plan.removals.map { "would remove \($0.url.path.tildedPath) (\(ByteSize.short($0.bytes))) — \($0.reason)" }
            detail = plan.removals.isEmpty ? "nothing to prune" : "would free \(ByteSize.short(plan.bytes)) across \(plan.removals.count) paths"
        } else {
            let outcome = prune.execute(plan)
            residue += outcome.removed.map { "removed \($0.url.path.tildedPath) (\(ByteSize.short($0.bytes))) — \($0.reason)" }
            residue += outcome.spared.map { "kept \($0.url.path.tildedPath) — \($0.reason)" }
            residue += outcome.failed.map { "not removed \($0.entry.url.path.tildedPath) — \($0.reason)" }
            if let failed = AnswerVerdict.qualification(outcome.failed.count, "path", "could not be removed") {
                qualifications.append(failed)
            }
            detail = Self.detail(plan: plan, outcome: outcome)
        }
        residue += plan.kept.map { "kept \($0.url.path.tildedPath) — \($0.reason)" }
        if let leases {
            let released = leases.releaseExpired(now: now, dryRun: dryRun)
            residue += released.map(Self.leaseLine(dryRun: dryRun))
            if let failed = AnswerVerdict.qualification(released.filter { $0.failure != nil }.count, "lapsed lease", "could not be released") {
                qualifications.append(failed)
            }
            if let journal {
                let clones = released.filter { $0.failure == nil && $0.entry.lease.createdDevice }.map(\.entry.udid)
                for udid in clones {
                    switch journal.prune(udid: udid, dryRun: dryRun) {
                    case .none: break
                    case .removed: residue.append("\(dryRun ? "would remove" : "removed") the device-setup record on \(udid) — its clone is deleted")
                    case let .kept(pid): residue.append("kept the device-setup record on \(udid) — its walk (pid \(pid)) still runs")
                    case let .notRemoved(reason): residue.append("could not remove the device-setup record on \(udid): \(reason)")
                    }
                }
                // A record kept because its walk still ran is not revisited once its clone is gone, so the directory is swept too (SimWalk#92): a record with no walk running, no lease or clone on its device, and no device left has nothing to hand back to. A device that still exists keeps its record even when the walk is dead — the next walk on it hands the record back first — so the sweep removes nothing unless the device listing says the device is gone.
                let held = leases.store.held(now: now)
                let candidates = journal.recordedUDIDs().filter { held[$0] == nil && !clones.contains($0) }
                if !candidates.isEmpty {
                    if let existing = try? Simulator.existing(shell: leases.shell).map(\.udid) {
                        for udid in candidates where !existing.contains(udid) {
                            switch journal.prune(udid: udid, dryRun: dryRun) {
                            case .none: break
                            case .removed: residue.append("\(dryRun ? "would remove" : "removed") the orphaned device-setup record on \(udid) — its walk is gone, no lease or clone holds the device, and the device no longer exists")
                            case let .kept(pid): residue.append("kept the device-setup record on \(udid) — its walk (pid \(pid)) still runs")
                            case let .notRemoved(reason): residue.append("could not remove the device-setup record on \(udid): \(reason)")
                            }
                        }
                    } else {
                        residue.append("kept the device-setup records on \(candidates.joined(separator: ", ")) — the simulator list could not be read, so no device can be judged gone")
                    }
                }
            }
            let temporaries = leases.store.sweepTemporaries(now: now, dryRun: dryRun)
            if temporaries > 0 {
                residue.append("\(dryRun ? "would remove" : "removed") \(temporaries) stale temporary file\(temporaries == 1 ? "" : "s") from \(leases.store.directory.path.tildedPath)")
            }
            detail = Self.detail(detail, adding: Self.leaseWork(released: released, temporaries: temporaries, dryRun: dryRun))
        }
        residue += ruleLines(installedFound: installedHash != nil)
        return Answer(
            header: header,
            verdict: .reporting(qualifications: qualifications, detail: detail),
            residue: residue
        )
    }

    /// What the lease store's part of a prune did, as a clause for the detail; `nil` when it did nothing.
    static func leaseWork(released: [DeviceLeasing.Release], temporaries: Int, dryRun: Bool) -> String? {
        let done = released.filter { $0.failure == nil }
        let clones = done.filter(\.entry.lease.createdDevice).count
        var parts: [String] = []
        if !done.isEmpty {
            parts.append("\(dryRun ? "would release" : "released") \(done.count) lapsed lease\(done.count == 1 ? "" : "s")")
        }
        if clones > 0 {
            parts.append("\(dryRun ? "would delete" : "deleted") \(clones) clone\(clones == 1 ? "" : "s")")
        }
        if temporaries > 0 {
            parts.append("\(dryRun ? "would remove" : "removed") \(temporaries) temporary file\(temporaries == 1 ? "" : "s")")
        }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    /// The runner prune's detail with the lease work joined on; a runner "nothing to prune" gives way to it rather than contradicting it.
    static func detail(_ runner: String, adding work: String?) -> String {
        guard let work else { return runner }
        return runner == "nothing to prune" ? work : "\(runner); \(work)"
    }

    /// One lapsed lease — expired, or a clone's whose holder is gone — a prune released, would release, or could not.
    static func leaseLine(dryRun: Bool) -> (DeviceLeasing.Release) -> String {
        { release in
            let device = release.entry.lease.createdDevice ? " and deleted its clone" : ""
            if let failure = release.failure {
                return "lease on \(release.entry.udid) lapsed and not released — \(failure)"
            }
            return dryRun ? "would release the lapsed lease on \(release.entry.udid)\(device.isEmpty ? "" : ", deleting its clone")" : "released the lapsed lease on \(release.entry.udid)\(device)"
        }
    }

    /// A real run's detail: "nothing to prune" only when there was nothing to plan for — a run whose candidates all survived to be spared, or all failed, said as such rather than folded into the same "nothing to prune" a plan with no candidates at all sees (SimWalk#33 review).
    static func detail(plan: RunnerPrune.Plan, outcome: RunnerPrune.Outcome) -> String {
        guard !plan.removals.isEmpty else {
            return "nothing to prune"
        }
        guard !outcome.removed.isEmpty else {
            return "0 of \(plan.removals.count) removed — \(outcome.spared.count) spared, \(outcome.failed.count) failed"
        }
        return "freed \(ByteSize.short(outcome.freed)) across \(outcome.removed.count) paths"
    }

    /// The retention rule, stated on every answer so a reader can check a removal against it — the installed binary's runner only claimed kept where one was found, since otherwise the claim promises a survivor that does not exist (SimWalk#33).
    static func ruleLines(installedFound: Bool) -> [String] {
        let installedClause = installedFound ? " and the installed binary's" : ""
        var lines = ["rule: keeps this binary's runner\(installedClause), the \(RunnerPrune.recentInstalls) most recent installs besides this one's, anything installed or walked in the last \(RunnerPrune.recentUseWording), and a working tree's build while its project exists; a working tree's build whose project is gone is removed however recently it was walked"]
        if !installedFound {
            lines.append("no installed binary was found — nothing was kept for it")
        }
        return lines
    }
}

extension PruneCommand {
    /// Why a prune did not run.
    enum PruneRefusal: Error, CustomStringConvertible {
        case binaryUnreadable

        var description: String {
            "this binary could not be read to tell which runner is paired with it, so nothing was pruned"
        }
    }
}
