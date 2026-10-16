//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import SimWalkDriver

/// A walk of a physical iPhone or iPad (SimWalk#116): what `walk --device <physical udid>` runs, and what the `device walk` alias runs too.
///
/// Wires the pieces that already exist (the lease, prerequisites, appearance read-back, the device build and walk, the container copy and wipe) and shares nothing with the simulator walk but the runner resolution it calls. Its inputs are the command-line values of either face, so neither can come to walk a phone differently.
struct DeviceWalk {
    /// The walkbook JSON file.
    let walkbook: String
    /// The UDID to lease for the walk; nil when `lease` names the device.
    let requestedUDID: String?
    /// The token of a lease on the phone; the lease names the device.
    let lease: String?
    let team: String?
    let runnerBundleID: String?
    /// A built `.app` to install first.
    let app: String?
    let output: String
    /// The walkbook screens to walk; empty is every one.
    let screens: [String]
    let settle: Int?
    let motion: Bool

    /// The answer, with the shell, the runner builds and the runner resolution injectable so the order of commands is checkable without a phone.
    ///
    /// **Every exit after the first appearance read reads the appearance back** and hands it back if it differs, so a walk that dies mid-way (a dark state, a runner failure) does not leave the user's phone in Dark Mode unsaid. A runner failure does not discard a bundle the runner finalised: it is kept if it is this walk's, and the answer is qualified by the failure.
    ///
    /// **The phone's lease comes before any `devicectl` call**, reads included, so a phone leased by someone else is refused naming the holder with nothing run on it. A `--lease` walk renews the lease and leaves it to its holder; a `--udid` walk takes its own (holder: this process, 30 minutes) and releases it on every exit. **Either way the walk also takes a `WalkClaim` on the phone** (SimWalk#128), whatever lease it runs under, so a `session end` under the same lease sees the walk; it is released on every exit.
    func answer(shell: Shell, builds: RunnerBuilds, resolveRunner: (() throws -> RunnerSource)?, leases: LeaseStore, holderPID: Int32, now: Date = Date()) throws -> Answer {
        // Named absolute and standardized in a refusal, not as typed: the reader may not be where the walk was run from.
        let walkbookURL = URL(fileURLWithPath: walkbook).standardizedFileURL
        let data: Data
        do {
            data = try Data(contentsOf: walkbookURL)
        } catch {
            throw WalkbookLoadError.unreadable(source: walkbookURL.path, reason: error.localizedDescription)
        }
        let loaded = try WalkbookLoader.load(from: data, source: walkbookURL.path)
        // A subset is executed as its own walkbook, hashed as itself, as a simulator walk's is: the manifest names the plan that ran. The JSON the runner is handed is then the narrowed walkbook's encoding; with every screen, the file as written.
        let book = screens.isEmpty ? loaded : try WalkbookSubset.narrow(loaded, to: screens)
        let walkbookJSON = try screens.isEmpty ? String(decoding: data, as: UTF8.self) : String(decoding: JSONEncoder().encode(book), as: UTF8.self)

        let unsupported = DeviceTargetSupport.unsupported(in: book)
        guard unsupported.isEmpty else {
            throw DeviceWalkRefusal.unsupported(unsupported)
        }

        let resolution = CaptureBundleLayout.resolvingOutput(URL(fileURLWithPath: output).standardizedFileURL)
        let outputURL = resolution.url
        do {
            try CaptureBundleWriter.requireFresh(outputURL)
        } catch {
            throw DeviceWalkRefusal.failed(Self.naming(output: resolution, in: String(describing: error)), usageFailureKind: UsageFailureKind.of(error) ?? .inputRefused, handback: [])
        }

        // The app is checked before the lease, as is its hash: a wrong or unreadable `.app` refuses with nothing run.
        let installing = try app.map { try Self.installable(appAt: $0, expecting: book.appBundleID) }

        let held: WalkLease
        if let lease {
            held = try WalkLease.presentedPhysical(token: lease, store: leases)
            try held.requireRenewed(now: now)
        } else {
            held = try WalkLease.takePhysical(udid: requestedUDID ?? "", store: leases, holderPID: holderPID, now: now)
        }
        defer { held.release() }
        let udid = held.udid
        let claim = try WalkClaim.take(udid: udid, in: leases)
        defer { claim.release() }

        let device = try PhysicalDevicePrerequisites.check(udid: udid, team: team, shell: shell)
        let before = try PhysicalDeviceAppearance.read(udid: udid, shell: shell)
        // `setup.increaseContrast` is the one setup key a device has a form of (`devicectl`); `false` and absent leave it as found. The appearance read above is the read before the set, so the value found is what is handed back.
        let contrast = book.setup?.increaseContrast == true

        let plan = DeviceWalkPlan(udid: udid, book: book, lease: held, installing: installing, before: before, walkbookJSON: walkbookJSON, outputURL: outputURL)
        let walked: (bundle: CaptureBundle, runnerFailure: String?)
        var trail = DeviceWalkTrail()
        do {
            walked = try walkAndFetch(plan, shell: shell, builds: builds, resolveRunner: resolveRunner, trail: &trail)
        } catch {
            // Once the install succeeded, every refusal says so: the phone's previous copy is gone whatever came after.
            let handback = handBack(found: before, restoringContrast: contrast, udid: udid, trail: trail, shell: shell)
            throw DeviceWalkRefusal.failed(Self.naming(output: resolution, in: String(describing: error)), usageFailureKind: UsageFailureKind.of(error) ?? .runnerFailed, handback: trail.installed + trail.container + handback.lines)
        }

        let handback = handBack(found: before, restoringContrast: contrast, udid: udid, trail: trail, shell: shell)
        let survived = (walked.runnerFailure == nil ? [] : ["a runner failure this bundle survived"]) + (trail.containerEmptied ? [] : ["the runner's container was not emptied"])
            + (trail.measureFailures.isEmpty ? [] : ["\(trail.measureFailures.count) measure run\(trail.measureFailures.count == 1 ? "" : "s") left no record"])
        let buildLines = installing.map { [
            "build: \(AppBuildIdentity.printed($0.hash)) (installed by this walk, not read back)",
            Self.replacedLine(book.appBundleID),
        ] } ?? ["build: not read back on a device (SimWalk#116)"]
        let residue = ["device: \(device.name) · \(device.marketingName) · iOS \(device.osVersion) · \(udid)"] + buildLines + (MeasureOptIn.launchEnvironmentNote(for: book).map { [$0] } ?? []) + trail.measured + trail.measureFailures + (walked.runnerFailure.map { ["runner failure: \($0)"] } ?? []) + trail.container + handback.lines
        // The record is written into the manifest after the handback, as a simulator walk's is; one that cannot be written is printed under the answer instead.
        let record = trail.contrastMade.map { CaptureManifest.SetupRecord(made: [$0], handedBack: handback.contrastHandedBack.map { [$0] } ?? [], notHandedBack: handback.contrastNotHandedBack.map { [$0] } ?? []) }
        let recorded = record.flatMap { try? $0.write(into: walked.bundle) }
        let recordLines = record.map { recorded == nil ? $0.lines : [] } ?? []
        let written = recorded ?? walked.bundle
        let bundle = resolution.suffixAdded ? written.noting("output: \(Self.naming(output: resolution, in: outputURL.path))") : written
        return CaptureBundleSummary(bundle, qualifiedBy: survived + handback.qualifications).answer(appending: residue + recordLines)
    }

    /// The `.app` to install and its hash, taken on the Mac before anything is installed; refused when it is unreadable or is not `bundleID`'s app.
    private static func installable(appAt path: String, expecting bundleID: String) throws -> InstalledApp {
        do {
            let found = try AppBuildIdentity.bundleIdentifier(ofAppAt: path)
            guard found == bundleID else {
                throw DeviceWalkRefusal.unusableApp("\(path) is \(found), not the walkbook's app \(bundleID)")
            }
            return try InstalledApp(path: path, hash: AppBuildIdentity.hash(ofAppAt: path))
        } catch let refusal as DeviceWalkRefusal {
            throw refusal
        } catch {
            throw DeviceWalkRefusal.unusableApp(String(describing: error))
        }
    }

    /// The appearance and contrast handed back, unless the walk's lease lapsed.
    ///
    /// The one renewal before the container wipe gates both, because a phone another holder has taken is theirs to flip, as `session end` leaves it (`LiveSessionDeviceStop`). Said in a line and a qualification, as the other cases are.
    private func handBack(found: PhysicalDeviceAppearance, restoringContrast: Bool, udid: String, trail: DeviceWalkTrail, shell: Shell) -> PhysicalDeviceAppearance.Handback {
        guard let lapsed = trail.leaseLapsed else {
            return PhysicalDeviceAppearance.handBack(found: found, udid: udid, restoringContrast: restoringContrast, shell: shell)
        }
        return PhysicalDeviceAppearance.Handback(
            lines: ["appearance not handed back: the lease on \(udid) is no longer this walk's (\(lapsed))"]
                + (restoringContrast ? ["Increase Contrast not handed back: the lease on \(udid) is no longer this walk's (\(lapsed))"] : []),
            qualifications: ["the device's appearance was not handed back: the lease on \(udid) is no longer this walk's"],
            contrastNotHandedBack: restoringContrast ? "the lease on \(udid) is no longer this walk's (\(lapsed))" : nil
        )
    }

    /// `requireRenewed`, with the lapse written into the trail before it is thrown: the handback is then skipped as it is after the wipe's renewal, not run against a phone another holder has taken.
    private func renewed(_ lease: WalkLease, trail: inout DeviceWalkTrail) throws {
        do {
            try lease.requireRenewed(now: Date())
        } catch {
            trail.leaseLapsed = String(describing: error)
            throw error
        }
    }

    /// `text` with the output path followed by "(suffix added)" where the walk completed `--output` with `.simwalk`, so a refusal names the path as the success answer does and the reader is not sent looking for a path they never typed (SimWalk#122).
    private static func naming(output resolution: CaptureBundleLayout.Resolution, in text: String) -> String {
        resolution.suffixAdded ? text.replacingOccurrences(of: resolution.url.path, with: "\(resolution.url.path) (suffix added)") : text
    }

    private static func replacedLine(_ bundleID: String) -> String {
        "the phone's previous copy of \(bundleID), if any, was replaced and not restored"
    }

    /// Renews, installs, builds, measures (renewing before each run), renews, walks, copies the bundle back and checks it is this walk's.
    ///
    /// A runner failure is held, not thrown, until the copy has been tried: with `continueAfterFailure` the runner may have finalised a complete bundle despite an XCTest issue. With no bundle, the refusal names the runner failure and why the copy failed.
    ///
    /// `trail.installed` is filled the moment the install succeeds, so a refusal thrown afterwards can say the phone's copy of the app was replaced.
    private func walkAndFetch(
        _ plan: DeviceWalkPlan,
        shell: Shell,
        builds: RunnerBuilds,
        resolveRunner: (() throws -> RunnerSource)?,
        trail: inout DeviceWalkTrail
    ) throws -> (bundle: CaptureBundle, runnerFailure: String?) {
        let udid = plan.udid
        // A renewal that fails refuses before the walk changes anything on the phone.
        try renewed(plan.lease, trail: &trail)
        // Set after the appearance read and before anything else is run on the phone, and judged by its read-back as a simulator's setup is (SimWalk#63): a read that disagrees refuses before the runner starts, and the caller's handback puts the value found back.
        if plan.book.setup?.increaseContrast == true {
            try PhysicalDeviceAppearance.setIncreaseContrast(true, udid: udid, shell: shell)
            let read = try PhysicalDeviceAppearance.read(udid: udid, shell: shell)
            guard read.increaseContrast else {
                throw DeviceWalkRefusal.contrastNotSet(found: plan.before.increaseContrast)
            }
            trail.contrastMade = "Increase Contrast enabled by devicectl, found \(plan.before.increaseContrast ? "enabled" : "disabled"), read back enabled (set, unverified: nothing captured reports it)"
        }
        // The install comes after the prerequisites and before the runner build; a failure refuses naming devicectl's error.
        if let installing = plan.installing {
            try PhysicalDevicePrerequisites.install(appAt: installing.path, udid: udid, shell: shell)
            trail.installed = ["build installed by this walk: \(AppBuildIdentity.printed(installing.hash)) (hashed on this Mac before the lease)", Self.replacedLine(plan.book.appBundleID)]
            // The `.app` is hashed again: rebuilt between the check and the install, the phone holds a build that is not the one checked.
            let after = try AppBuildIdentity.hash(ofAppAt: installing.path)
            guard after == installing.hash else {
                trail.installed = ["build installed by this walk: unknown — \(AppBuildIdentity.printed(installing.hash)) was checked, the .app read \(AppBuildIdentity.printed(after)) after the install", Self.replacedLine(plan.book.appBundleID)]
                throw DeviceWalkRefusal.appChangedBeforeInstall(path: installing.path, checked: installing.hash, installed: after)
            }
        }
        // The team is non-empty: the prerequisites refused otherwise.
        let team = team ?? ""
        let run: (String, [String]) throws -> Shell.Result = { try shell.run($0, $1) }
        let source = try resolveRunner?() ?? RunnerProject.resolve(executable: LaunchedBinary.url, binaryHash: { LaunchedBinary.hash }, run: run)
        try builds.recordUse(of: source)
        let runner = RunnerInvocation(projectPath: source.projectPath, derivedDataPath: builds.directory(for: source).path, shell: shell)
        try runner.buildForDevice(udid: udid, team: team, runnerBundleID: runnerBundleID)
        let deviceAppearance = Walkbook.Theme(rawValue: plan.before.userInterfaceStyle)

        // The measure runs go first, each a cold launch of its own; their records reach the manifest through the walk's runner (SimWalk#67, M4).
        let measured: DeviceMeasure.Outcome
        do {
            measured = try DeviceMeasure(runner: runner, shell: shell, udid: udid, walkbookJSON: plan.walkbookJSON, settleMilliseconds: settle, deviceAppearance: deviceAppearance, runnerCommit: source.commit)
                .run(plan.book, renewing: plan.lease)
        } catch {
            // A measure run's own failure is held in the outcome; what `run` throws is its renewal, so the lease is no longer this walk's.
            trail.leaseLapsed = String(describing: error)
            throw error
        }
        trail.measured = measured.measured
        trail.measureFailures = measured.failed

        // An app this walk did not install cannot be read back on a device, so the runner is told a placeholder and the check below rests on the nonce alone; one it installed is hashed on the Mac.
        let buildHash = plan.installing?.hash ?? AppBuildIdentity.unreadOnDevice
        let provenance: CaptureManifest.AppBuildProvenance? = plan.installing == nil ? nil : .installed
        let nonce = UUID().uuidString
        let outputName = plan.outputURL.lastPathComponent
        let resultBundlePath = runner.resultBundlePath(launchedAt: Date(), id: nonce)
        var runnerFailure: Error?
        // A renewal that fails refuses here, before the runner starts.
        try renewed(plan.lease, trail: &trail)
        do {
            try runner.walkOnDevice(
                walkbookJSON: plan.walkbookJSON,
                outputName: outputName,
                buildHash: buildHash,
                buildProvenance: provenance,
                udid: udid,
                nonce: nonce,
                settleMilliseconds: settle,
                motion: motion,
                deviceAppearance: deviceAppearance,
                runnerCommit: source.commit,
                performance: measured.performance,
                resultBundlePath: resultBundlePath
            )
        } catch {
            runnerFailure = error
        }

        let copier = DevicectlContainerCopy(udid: udid, containerBundleID: RunnerInvocation.deviceContainerBundleID(runnerBundleID: runnerBundleID), shell: shell)
        let fetched = Result {
            // `.distantPast` on purpose: the manifest's start time is the phone's clock, not this Mac's, so the start-time slack a simulator walk allows does not apply. The nonce is what proves the bundle is this walk's. It is checked on the staged copy, so another walk's bundle never reaches the output.
            try DeviceBundleTransfer.fetch(source: RunnerInvocation.deviceOutputSource(outputName: outputName), to: plan.outputURL, copier: copier) { staged in
                var problems = CaptureBundleError.problems(staged.manifest, walkLaunchedAt: .distantPast, buildHash: buildHash, nonce: nonce)
                // A runner predating `SIMWALK_BUILD_PROVENANCE` ignores it and would write an installed hash that reads as read back.
                if staged.manifest.appBuildProvenance != provenance {
                    problems.append("build provenance is \(staged.manifest.appBuildProvenance?.rawValue ?? "absent"), not \(provenance?.rawValue ?? "absent") as this walk told the runner")
                }
                guard problems.isEmpty else {
                    throw DeviceWalkRefusal.bundleNotThisWalks(problems: problems)
                }
            }
        }
        // The runner ran, so its container is emptied whether the copy worked or not: the phone keeps no captures (SimWalk#116). Only the runner's own container, derived from its bundle id, can be named.
        // Only while this walk still holds the lease: the wipe empties the runner's whole container, and a walk whose lease lapsed during a long run may share the phone with another holder whose runner is mid-run in it. Renewing is the check — it succeeds only for a lease that is this token's, unexpired and held by a live process.
        if let lapsed = plan.lease.renew(now: Date()) {
            trail.leaseLapsed = lapsed
            trail.container = ["runner container left as it is: the lease on \(udid) is no longer this walk's (\(lapsed)), so another holder's runner may be using it"]
            trail.containerEmptied = false
        } else {
            let wiped = RunnerContainerWipe(udid: udid, runnerBundleID: runnerBundleID, shell: shell).empty()
            trail.container = [wiped.line]
            trail.containerEmptied = wiped.emptied
        }
        do {
            return try (fetched.get(), runnerFailure.map { String(describing: $0) })
        } catch {
            guard let runnerFailure else { throw error }
            // The runner's own error is a build's or a launch's; why it stopped before its test is in its result bundle, read only now that the runner's failure is the refusal (SimWalk#124).
            let diagnosis = RunnerFailureDiagnosis.read(resultBundlePath: resultBundlePath, shell: shell).lines
            throw DeviceWalkRefusal.noBundleAfterRunnerFailure(runner: ([String(describing: runnerFailure)] + diagnosis).joined(separator: "\n  "), fetch: String(describing: error))
        }
    }
}

extension DeviceWalk {
    /// An `.app` `--app` names, and its build hash taken on the Mac.
    struct InstalledApp {
        let path: String
        let hash: String
    }

    /// What `walkAndFetch` did on the phone that the answer or a refusal must say, filled as it goes.
    private struct DeviceWalkTrail {
        /// Said once the install succeeded: the phone's previous copy of the app is gone.
        var installed: [String] = []
        /// The runner's container wipe, once the runner has run.
        var container: [String] = []
        var containerEmptied = true
        /// Why the lease is no longer this walk's, once the renewal before the wipe found it so: the wipe and the appearance handback are both skipped.
        var leaseLapsed: String?
        /// The manifest's line for Increase Contrast, once it was set and read back enabled.
        var contrastMade: String?
        /// One line per measure run's record, for the answer.
        var measured: [String] = []
        /// One line per measure run that left no record, for the answer.
        var measureFailures: [String] = []
    }

    /// What `walkAndFetch` needs from `answer`, bundled to stay under the parameter limit.
    private struct DeviceWalkPlan {
        let udid: String
        /// The walkbook as executed: narrowed to `--screens` when they were given.
        let book: Walkbook
        let lease: WalkLease
        let installing: InstalledApp?
        let before: PhysicalDeviceAppearance
        let walkbookJSON: String
        let outputURL: URL
    }
}
