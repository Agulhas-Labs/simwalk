//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import SimWalkDriver

/// The second pass a walk makes when screens had a state refused on appearance — the sign of a device that reported one appearance and drew the other (SimWalk#26): settle the device, walk those screens again, and fold the second attempt into the bundle.
///
/// **Why a retry after a refusal, and not a reboot before every walk.** A reboot is tens of seconds, and most walks are small `--screens` iterations on a device that draws what it reports — a settle ahead of each would put that cost on every one of them to cure a condition few of them have, which is the "longer timer" the coding guidelines refuse. The refusal is the detector: it costs nothing on a device that is fine, and fires exactly where the trap is. And the evidence is judged the same way twice — the second attempt goes through the runner's own `StateApplicationCheck` on the settled device, so a screen still drawing the wrong appearance is refused again, exactly as before, and the manifest keeps both attempts' verdicts.
///
/// **Only the screens that refused on appearance, once.** The rest of the bundle was judged on the first pass and stands; the second walks a subset of the same plan, into a scratch bundle of its own, and `AppearanceRetry.fold` replaces just those screens — and only where the second attempt kept at least what the first did. One settle per walk, whatever it finds: a screen whose appearance refusal is by design refuses twice and costs one reboot, never a loop.
///
/// **Recorded whichever way it went.** A settle reboots the device, which is a side effect a reader has to be able to account for — so the manifest carries `appearanceSettle` when the second attempt was folded, and also when the settle was not made, stopped short, or the second pass left nothing to fold, with the reason.
struct AppearanceRetryPass {
    let udid: String
    /// The appearance the walk found the device in — what the settle puts back and the handback promises.
    let found: Walkbook.Theme
    /// The walkbook the walk was handed — the plan the second pass walks a subset of.
    let walkbookPath: String
    /// Whether the settle may reboot the device (`DeviceSettle.mayReboot`) — a device leased to this walk, named by UDID, or booted by this walk.
    ///
    /// When not, nothing is rebooted, and the manifest and the answer carry the settle instead.
    let mayReboot: Bool
    /// The installed build the first pass walked, checked again against the second pass's own bundle the way `WalkCommand.performWalk` checks its first (SimWalk#41) — the settle reboots nothing installed, so it is always the same build.
    let buildHash: String
    /// What the scratch bundle is made and removed through, and the fold moves through — the real one in use; one whose moves fail in a test.
    var fileManager: FileManager = .default
    /// Generates the value the second pass hands its own runner and checks its bundle back against — the walk's own seam, so a test can fix what the canned bundle it stages must carry (SimWalk#41).
    var nonce: () -> String = { UUID().uuidString }
    /// Runs once the settle has rebooted the device and put its appearance back, before the second pass — where the walk makes again what its setup made that a reboot does not keep: the status bar override.
    var afterSettle: () -> Void = {}
    /// Renews the walk's lease on the device as of the time given: `nil` when it holds, else why not (``WalkLease/renew(now:)``) — asked before the settle's reboot and again before the second pass, so a walk that has outlived its lease changes nothing on a device another session may have reclaimed.
    let renew: (Date) -> String?
    /// Runs the runner over the walkbook at the first path into the bundle directory at the second, with every other input the first pass had, and the nonce this pass generated for it.
    let walk: (_ walkbookPath: String, _ outputPath: String, _ nonce: String) throws -> Void
    /// The runner's own account of why the second runner failed, read from the result bundle `walk` named for it — asked only when that runner failed and left nothing to read, as the first pass's is (SimWalk#70).
    var diagnose: () -> [String] = { [] }
    /// What the second runner's failure comes to as XCTest's crash blame (SimWalk#176), asked only of one whose bundle was folded in.
    var blameCrashes: (Error) -> XCTestCrashBlame = { _ in .notApplicable }

    /// Settles and walks again the screens of `first` that refused on appearance, folding the result into `first` on disk; `nil` when no screen needs it, which is every walk on a device that drew what it reported.
    ///
    /// Every child goes through `run` and every time through `now` — the walk's own, so a test drives the whole pass against the script it drives the walk with.
    ///
    /// `run` takes each command's bound as its third argument — the settle's steps are bounded (`DeviceSettle.stepTimeout`), so a boot that wedges ends the pass rather than holding the walk.
    func perform(after first: CaptureBundle, of book: Walkbook, run: (String, [String], TimeInterval) throws -> Shell.Result, now: () -> Date) -> Outcome? {
        let screens = AppearanceRetry.screens(toRetryIn: first.manifest)
        guard !screens.isEmpty else { return nil }
        // A device the walk found booted and was given neither by lease nor by UDID may be another session's, so it is not rebooted: the
        // refusals stand, and the manifest records the settle not made and the command that makes it (the round-3
        // review). Nothing touched the device, so the handback judges the reset alone.
        guard mayReboot else {
            let command = DeviceSettle.command(udid: udid, found: found)
            var settle = AppearanceRetry.settle(found: found, milliseconds: 0, retrying: screens)
            settle.declined = CaptureManifest.AppearanceSettle.Declined(reason: Self.notOwned(udid: udid), command: command)
            _ = try? AppearanceRetry.recordUnfolded(settle, in: first)
            return Outcome(report: .notSettled(screens: screens.map(\.id), command: command), firstReset: nil, secondRunnerRan: false, lastRunnerFinished: true)
        }
        // A lease that can no longer be renewed keeps nobody off the device, so it may by now be another session's: it is
        // declined as a device the walk was never given is, and nothing is rebooted.
        if let reason = renew(now()) {
            let command = DeviceSettle.command(udid: udid, found: found)
            var settle = AppearanceRetry.settle(found: found, milliseconds: 0, retrying: screens)
            settle.declined = CaptureManifest.AppearanceSettle.Declined(reason: Self.leaseNotRenewed(udid: udid, reason: reason), command: command)
            _ = try? AppearanceRetry.recordUnfolded(settle, in: first)
            return Outcome(report: .leaseNotRenewed(screens: screens.map(\.id), reason: reason, command: command), firstReset: nil, secondRunnerRan: false, lastRunnerFinished: true)
        }
        // The first runner's last reset, read before the settle changes the appearance — afterwards the device's
        // appearance is the settle's doing, and says nothing about the resets the first pass's keeps rest on.
        let firstReset = DeviceHandback.resetCheck(udid: udid, found: found, runnerFinished: true) { try run($0, $1, DeviceSettle.stepTimeout) }
        let started = now()
        let settled = DeviceSettle.perform(udid: udid, found: found, run: run)
        var settle = AppearanceRetry.settle(found: found, milliseconds: Int((now().timeIntervalSince(started) * 1000).rounded()), retrying: screens)
        if case let .failed(step, reason) = settled {
            // Recorded all the same: from the shutdown on, the device may have been rebooted or left down, and the
            // manifest is where a reader looks for why the refusals stand.
            settle.settleFailure = "\(step.name) (\(reason))"
            _ = try? AppearanceRetry.recordUnfolded(settle, in: first)
            return Outcome(report: .settleFailed(settled), firstReset: firstReset, secondRunnerRan: false, lastRunnerFinished: true)
        }
        // Asked again after the reboot, which is tens of seconds: the status bar and the second runner change the device too.
        if let reason = renew(now()) {
            let failure = Self.leaseNotRenewed(udid: udid, reason: reason)
            _ = record(settle, secondPassFailure: failure, in: first)
            return Outcome(report: .retryFailed(reason: failure, keptAt: nil), firstReset: firstReset, secondRunnerRan: false, lastRunnerFinished: true)
        }
        afterSettle()
        let second = secondPass(of: book, folding: first, settle: settle, run: run, now: now)
        return Outcome(report: second.report, firstReset: firstReset, secondRunnerRan: true, lastRunnerFinished: second.lastRunnerFinished, retryTimeouts: second.timeouts)
    }

    /// Puts the device back in the appearance the walk found it in, from the host, after a second runner that left nothing to read — a runner that stopped short may have stopped before its own last reset (SimWalk#68).
    private func putBack(run: (String, [String], TimeInterval) throws -> Shell.Result) -> DeviceAppearance.Handback {
        DeviceAppearance.restore(found, udid: udid) { try run($0, $1, DeviceSettle.stepTimeout) }
    }

    /// Why the walk did not settle `udid` — recorded in the manifest, where `inspect` reads it.
    static func notOwned(udid: String) -> String {
        "\(udid) was already booted when the walk resolved it and was neither leased to it nor named by UDID, so it may be another session's, and a reboot would end whatever that session runs on it — walked under a lease (`simwalk lease acquire --device \(udid)`, then `--lease <token>`) or named by UDID (`--device \(udid)`), a walk settles it itself"
    }

    /// Why the walk did not settle `udid`, or did not walk it again after the settle: its lease could not be renewed.
    static func leaseNotRenewed(udid: String, reason: String) -> String {
        "the lease on \(udid) could not be renewed (\(reason)), so it may by now be another session's, and this walk changes nothing more on it"
    }

    /// Walks the settle's screens into a scratch bundle and folds it into `first`, answering what came of it — and whether the last runner to run is known to have finished.
    ///
    /// **A failed runner is not a lost bundle here either** — the first pass's rule: the second runner's bundle is read whatever `xcodebuild` exited with, and a readable one is folded, its failure qualifying the answer.
    ///
    /// **The scratch bundle is written inside `first`** (`CaptureBundleLayout.retryScratchDirectory`, the round-3 review), so every move the fold makes is a rename on one volume. **It is removed whichever way it went but two.** After a fold, or a fold undone, it holds its own manifest, the declined screens' artefacts and whatever of the first attempt the fold set aside. After a fold that could not be undone it holds the only copy of the first attempt, so it is kept and the answer says where; and after a fold undone whose record could not be written over the first attempt afterwards, it is kept too and named — whatever that write found wrong with the bundle, the scratch bundle holds what the fold set aside.
    ///
    /// **A second runner that left nothing to read is followed by a put-back from the host** (SimWalk#68): it may have stopped before its last reset, and nothing of its walk is kept, so the device is put back to `found` here rather than left at whatever the runner last set — and the answer names the pass's failure as the reason, instead of reading the device afterwards as evidence about resets no kept capture rests on.
    ///
    /// **The second runner's timed-out audits are read before the scratch bundle goes** (SimWalk#193), as ``TestManagerRestart/timeouts(in:orRecordedIn:)`` reads the first runner's: a runner that crashed before it finalised its manifest leaves them only there, and the device is still computing them.
    private func secondPass(
        of book: Walkbook,
        folding first: CaptureBundle,
        settle: CaptureManifest.AppearanceSettle,
        run: (String, [String], TimeInterval) throws -> Shell.Result,
        now: () -> Date
    ) -> SecondPass {
        let output = CaptureBundleLayout.retryScratchDirectory(in: first.url, id: UUID())
        var keepsScratch = false
        defer {
            if !keepsScratch {
                try? fileManager.removeItem(at: output)
            }
        }
        let executed: (path: String, temporaryURL: URL?)
        do {
            executed = try WalkCommand.walkbookToExecute(book, at: walkbookPath, screens: settle.retried.map(\.id))
        } catch {
            // No second runner launched: the last runner to run is the first, whose bundle was read.
            let reason = "\(error)"
            _ = record(settle, secondPassFailure: reason, in: first)
            return SecondPass(report: .retryFailed(reason: reason, keptAt: nil), lastRunnerFinished: true, timeouts: [])
        }
        defer { WalkCommand.discardTemporary(executed.temporaryURL) }

        var runnerFailure: Error?
        let launchedAt = now()
        // Generated fresh for this pass, as the first pass's own is (SimWalk#41): two settles of the same
        // walk running overlapped would otherwise be unable to tell their own second-pass bundle from the
        // other's.
        let retryNonce = nonce()
        do {
            try walk(executed.path, output.path, retryNonce)
        } catch {
            runnerFailure = error
        }
        let read = Result { try WalkCommand.bundleWrittenBy(walkLaunchedAt: launchedAt, buildHash: buildHash, nonce: retryNonce, at: output) }
        let timeouts = TestManagerRestart.timeouts(in: read, orRecordedIn: output)
        let second: CaptureBundle
        do {
            second = try read.get()
        } catch {
            // A second runner that left no readable bundle may have stopped before its last reset.
            let reason = "\(runnerFailure ?? error)"
            _ = record(settle, secondPassFailure: reason, in: first)
            return SecondPass(report: .runnerLeftNothing(reason: reason, runnerFailed: runnerFailure != nil, putBack: putBack(run: run), diagnosis: runnerFailure == nil ? [] : diagnose()), lastRunnerFinished: false, timeouts: timeouts)
        }
        // From here the second runner is known to have finished, folded in or not: the runner resets the device and only
        // then finalises its manifest, and a fold is refused for what a bundle says, never for how its runner ended.
        do {
            try AppearanceRetry.fold(second, into: first, settle: settle, fileManager: fileManager)
            let crashes = runnerFailure.map(blameCrashes) ?? .notApplicable
            return SecondPass(report: .folded(runnerFailure: crashes.isExcused ? nil : runnerFailure.map { "\($0)" }, xctestCrashes: crashes.line), lastRunnerFinished: true, timeouts: timeouts)
        } catch {
            if let notUndone = error as? AppearanceRetryError, case .foldNotUndone = notUndone {
                keepsScratch = true
                return SecondPass(report: .foldNotUndone(reason: "\(notUndone)"), lastRunnerFinished: true, timeouts: timeouts)
            }
            // The fold's own refusal is the reason a bundle that was read back left nothing to fold in — a runner
            // exit beside it is worth keeping too, but recording only the exit and losing why the fold refused the
            // bundle it read would hide the truer cause behind a symptom.
            let reason = runnerFailure.map { "\(error) — and the runner also failed: \($0)" } ?? "\(error)"
            // The set-aside exists once the fold began moving, so an undo ran; a record that could not be written after
            // it leaves the bundle other than the fold left it, and the scratch bundle is what can put it right.
            let undone = fileManager.fileExists(atPath: CaptureBundleLayout.setAsideDirectory(in: output).path)
            let recorded = record(settle, secondPassFailure: reason, in: first)
            guard recorded || !undone else {
                keepsScratch = true
                return SecondPass(report: .retryFailed(reason: reason, keptAt: output.path), lastRunnerFinished: true, timeouts: timeouts)
            }
            return SecondPass(report: .retryFailed(reason: reason, keptAt: nil), lastRunnerFinished: true, timeouts: timeouts)
        }
    }

    /// Writes the settle into the first attempt's manifest with why nothing was folded in; whether it could be.
    ///
    /// A fold that failed was undone before this runs, so the manifest is the first attempt's again and the settle record over it is true. The write is still refused — and the answer carries the whole account instead — wherever the manifest is gone, or no longer names what the bundle holds.
    private func record(_ settle: CaptureManifest.AppearanceSettle, secondPassFailure reason: String, in first: CaptureBundle) -> Bool {
        var settle = settle
        settle.secondPassFailure = reason
        return (try? AppearanceRetry.recordUnfolded(settle, in: first)) != nil
    }
}

extension AppearanceRetryPass {
    /// What the second pass came to: its report, whether the last runner to run is known to have finished, and the timed-out audits the second runner recorded.
    private struct SecondPass {
        let report: Report
        let lastRunnerFinished: Bool
        let timeouts: [AppleAuditScan.Failure]
    }

    /// What the pass came to, and the first runner's reset it read on the way.
    struct Outcome {
        let report: Report
        /// Whether the first runner's last reset held, read before the settle — `nil` when no settle was attempted, so the handback's own read, made after nothing touched the device, is the judgement.
        let firstReset: DeviceHandback.ResetCheck?
        /// Whether a second runner ran — the settle completed — so the device's appearance after the walk is the second runner's last reset.
        let secondRunnerRan: Bool
        /// Whether the last runner to run is known to have run its last reset: the second, when its bundle was read back — folded in or not, since it resets the device before it finalises its manifest; the first — whose bundle was read — when no second ran.
        ///
        /// Round 3 read this as "the second attempt was folded", so a readable second bundle the fold refused made the reset read as inconclusive where it was known.
        let lastRunnerFinished: Bool
        /// The timed-out audits the second runner recorded, read from its scratch bundle before the pass removed it (SimWalk#193); none when no second runner ran.
        var retryTimeouts: [AppleAuditScan.Failure] = []

        /// The bound on each call the handback makes: `DeviceSettle.handbackBound` after a settle that stopped short, when the device may be down or wedged; `nil` otherwise, the handback running as in any walk.
        var handbackBound: TimeInterval? {
            guard case .settleFailed = report else { return nil }
            return DeviceSettle.handbackBound
        }

        /// `handback` with its reset judgement made for a walk of two passes: the worse of both runners' last resets when a second ran, and the first's alone when the settle stopped short — the device's appearance after a failed settle is the settle's, not any runner's — or when the second runner left nothing to read: none of its captures is kept, and the host put the device back after it, so the appearance afterwards is the host's doing (SimWalk#68).
        func judging(_ handback: DeviceHandback) -> DeviceHandback {
            guard let firstReset else { return handback }
            if case .runnerLeftNothing = report {
                return handback.replacingReset(firstReset)
            }
            return handback.replacingReset(secondRunnerRan ? firstReset.combined(with: handback.reset) : firstReset)
        }
    }

    /// What became of the refused screens.
    enum Report: Equatable {
        /// Walked again and folded in — recorded in the manifest's `appearanceSettle`; the payload is the second runner's own failure, when its bundle survived one, and what that failure came to as XCTest's crash blame (``XCTestCrashBlame/line``), when it was that: `runnerFailure` is `nil` for one excused.
        case folded(runnerFailure: String?, xctestCrashes: String? = nil)
        /// The settle stopped at a step; nothing was walked again.
        case settleFailed(DeviceSettle.Outcome)
        /// The settle held and the second pass left nothing that could be folded in; the first attempt's refusals stand.
        ///
        /// `keptAt` is the scratch bundle, kept when a fold was undone and the record over the first attempt could not be written after it.
        case retryFailed(reason: String, keptAt: String?)
        /// The settle held and the second runner left no bundle this walk could read — it may have stopped before its last reset — so the host put the device back to the appearance it was found in; the first attempt's refusals stand (SimWalk#68).
        ///
        /// `runnerFailed` is whether the runner itself failed, rather than exiting 0 with a bundle this walk refused; `putBack` is what that put-back came to; the handback puts the device back again after it either way. `diagnosis` is what the failed runner's result bundle says (`RunnerFailureDiagnosis`), empty when it did not fail.
        case runnerLeftNothing(reason: String, runnerFailed: Bool, putBack: DeviceAppearance.Handback, diagnosis: [String])
        /// The device was not this walk's to reboot — already booted, and not named by UDID — so no settle was made; the refusals stand, and the payload is the screens and the settle a person runs.
        case notSettled(screens: [String], command: String)
        /// The walk's lease on the device could not be renewed before the settle — expired, its holder gone, or no longer in the store — so the device may be another session's by now and no settle was made; the refusals stand, and the payload is the screens, why, and the settle a person runs.
        case leaseNotRenewed(screens: [String], reason: String, command: String)
        /// Folding the second attempt in failed on disk and could not be undone: the bundle has no manifest, and the first attempt is set aside in the kept scratch bundle inside it — the payload says where, and how to put it back.
        case foldNotUndone(reason: String)

        /// What this qualifies the walk's answer by — every way the walk meant to recover these screens and did not, and nothing when it did.
        var qualification: String? {
            switch self {
            case .folded(runnerFailure: nil, _):
                nil
            case .folded:
                "a runner failure the appearance retry survived"
            case let .settleFailed(outcome):
                outcome.qualification
            case .retryFailed, .runnerLeftNothing:
                "an appearance retry that could not be folded in"
            case .notSettled:
                "an appearance settle not made on a device this walk did not boot, lease or get by UDID"
            case .leaseNotRenewed:
                "an appearance settle not made on a device whose lease could not be renewed"
            case .foldNotUndone:
                "an appearance retry whose fold could not be undone"
            }
        }

        /// The lines printed under the answer.
        ///
        /// `recorded` is whether the bundle's manifest carries the settle — then its own lines say what happened, and these add only what a file cannot: the second runner's failure, the command that leaves the device usable, and a scratch bundle kept inside the bundle.
        func notes(udid: String, recorded: Bool) -> [String] {
            switch self {
            case let .folded(runnerFailure: nil, crashes):
                [crashes].compactMap(\.self)
            case let .folded(runnerFailure?, crashes):
                ["⚠ the runner reported a failure walking the refused screens again after the appearance settle, and its bundle survived it — those screens above are what it recorded: \(runnerFailure)"] + [crashes].compactMap(\.self)
            case let .settleFailed(outcome):
                [recorded ? outcome.remedyNote(udid: udid) : outcome.note(udid: udid)].compactMap(\.self)
            case let .retryFailed(reason, keptAt):
                (recorded ? [] : ["appearance settle: \(udid) was settled, and walking the refused screens again left nothing this walk could fold in (\(reason)) — their first attempt's refusals stand"])
                    + (keptAt.map { ["appearance settle: the fold was undone, and the settle could not be recorded over the first attempt after it — so the second pass's scratch bundle, with what the fold set aside inside it, is kept at \($0) rather than removed: what the fold set aside of the first attempt is in it, laid out as a bundle, for whatever of it the bundle no longer holds"] } ?? [])
            case let .runnerLeftNothing(reason, runnerFailed, putBack, diagnosis):
                (recorded ? [] : ["appearance settle: \(udid) was settled, and walking the refused screens again left nothing this walk could fold in (\(reason)) — their first attempt's refusals stand"])
                    + [Self.putBackLine(putBack, runnerFailed: runnerFailed, udid: udid)]
                    + (diagnosis.isEmpty ? [] : ["appearance settle: what the second pass's own result bundle says of its failure:"] + diagnosis.map { "  \($0)" })
            case let .foldNotUndone(reason):
                ["appearance settle: \(udid) was settled and the refused screens walked again, and \(reason) — until then the bundle has no manifest"]
            case let .notSettled(screens, command):
                recorded ? [] : ["appearance settle: \(screens.joined(separator: ", ")) had a state refused on appearance on \(udid), which a reboot of the device can cure — and this walk did not reboot it: it was already booted and was not named by UDID, so it may be another session's, and the refusals stand. To settle it, then walk again: \(command) — or name it by UDID (`--device \(udid)`), and the walk settles a device it was given that way itself"]
            case let .leaseNotRenewed(screens, reason, command):
                recorded ? [] : ["appearance settle: \(screens.joined(separator: ", ")) had a state refused on appearance on \(udid), which a reboot of the device can cure — and this walk did not reboot it: its lease could not be renewed (\(reason)), so the device may by now be another session's, and the refusals stand. Once it is yours again (`simwalk lease acquire --device \(udid)`), settle it, then walk again: \(command)"]
            }
        }

        /// The line saying why the second pass left nothing to read and what the host's put-back afterwards came to — only what was verified: a put-back is claimed when it read back, and a failed one is not a command to run, because the handback puts the device back again straight after and prints its own line if that fails too.
        private static func putBackLine(_ putBack: DeviceAppearance.Handback, runnerFailed: Bool, udid: String) -> String {
            let cause = runnerFailed
                ? "appearance settle: the second pass's runner failed and left nothing to read, so it may have stopped before its last reset"
                : "appearance settle: the second pass's runner exited 0 but left no bundle this walk could accept, so it may have stopped before its last reset"
            return switch putBack {
            case let .restored(theme):
                "\(cause); the host then put \(udid) back and it read \(theme.rawValue), and none of that runner's captures is kept, so the resets the kept captures rest on are the first runner's"
            case let .failed(found, reason):
                "\(cause); the host could not put \(udid) back to \(found.rawValue) afterwards (\(reason)), and the walk's own handback tries again next"
            case let .unconfirmed(found, reason):
                "\(cause); the host set \(udid) back to \(found.rawValue) afterwards but nothing confirmed it held (\(reason)), and the walk's own handback checks it next"
            case let .leftToAnotherHolder(found):
                "\(cause); the host left \(udid) as another holder has it rather than putting it back to \(found.rawValue), and the walk's own handback tries again next"
            case .unknown:
                cause
            }
        }
    }
}
