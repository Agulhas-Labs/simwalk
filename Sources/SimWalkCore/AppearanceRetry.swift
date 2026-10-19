//
// Copyright © Agulhas Labs
//

import Foundation

/// What a walk does about screens that refused an appearance the device reported set and did not draw: which to walk again once the device has been settled, and how the second attempt joins the bundle (SimWalk#26).
///
/// **The trap.** A simulator whose appearance was just switched, or never set at all, can report `dark` from `simctl ui` and go on drawing light until it is rebooted. `StateApplicationCheck` refuses what that draws, which is right and cannot be recovered inside one pass: the runner is an XCUITest session on the device, and rebooting the device ends it. So the host settles the device between two passes — set it dark, shut down, boot, put the found appearance back — and walks the refused screens once more.
///
/// **A retry is judged exactly as the first attempt was.** Nothing here relaxes the check: the second attempt's records are whatever the runner's own `StateApplicationCheck` decided on the settled device, and a screen still drawing the wrong appearance is refused again, as before. What this adds is a second chance and the record of it — never a keep.
///
/// **Decisions here, I/O at the faces.** Which screens, what the manifest becomes, and which second attempts it takes are values a test holds; the reboot is the driver's (`DeviceSettle`) and the second pass the CLI's.
public struct AppearanceRetry {
    /// The screens whose first attempt had a state refused by the appearance check, in walkbook order — the refusals a settle can recover.
    ///
    /// Keyed on the record's `refusedOnAppearance`, the structured reason the check carries, and never on `refusedStates` alone or on the refusal's wording: a reason is prose for a reader, and a decision keyed on it breaks the first time the sentence is improved; and a collision over a locale or a Dynamic Type size is refused too, which a reboot cannot cure and must not cost one. Whatever the device was found in: a device found dark whose dark states drew light is refused on appearance exactly as one found light is.
    ///
    /// **What still pays a settle it cannot recover** is a screen whose appearance refusal is by design — a dark render bright by design (a full-bleed photo, a white-branded app), or a light one dark by design beside a dark state that did not darken it. The check cannot tell those from the trap, which is why it refuses them, and neither can this: such a screen costs one settle per walk and is refused on both attempts, never a loop.
    public static func screens(toRetryIn manifest: CaptureManifest) -> [CaptureManifest.ScreenRecord] {
        manifest.screens.filter { !($0.refusedOnAppearance ?? []).isEmpty }
    }

    /// The appearance a settle boots the device in: `dark`, always — the one sequence measured to cure the trap (`appearance dark`, then a reboot), whatever the device was found in or the refused states asked for.
    ///
    /// Not derived from anything, because the cure is not: three sightings, each cured by that sequence, and none by its mirror. Round 1 booted a device found dark in `light` and switched it to dark after the boot — the trap's own trigger rather than its cure.
    public static let bootAppearance = Walkbook.Theme.dark

    /// The settle's record for `screens` on a device found in `found`: what each first attempt found, and how long the settle took.
    public static func settle(found: Walkbook.Theme, milliseconds: Int, retrying screens: [CaptureManifest.ScreenRecord]) -> CaptureManifest.AppearanceSettle {
        CaptureManifest.AppearanceSettle(
            appearance: bootAppearance,
            found: found,
            milliseconds: milliseconds,
            retried: screens.map { screen in
                CaptureManifest.AppearanceSettle.Retry(
                    id: screen.id,
                    firstOutcome: screen.outcome,
                    firstRefusedStates: screen.refusedStates ?? [],
                    firstRefusedOnAppearance: screen.refusedOnAppearance ?? []
                )
            }
        )
    }

    /// The manifest the bundle carries once `retry` is folded into `first`: each retried screen's record replaced by its second attempt where that kept at least what the first did, the walk finishing when the second pass did, and the settle recorded — with the reason on each screen whose second attempt was not taken.
    ///
    /// **A second attempt replaces the first only where it keeps a superset of what the first kept.** The first pass on a device found light typically keeps a screen's `light` capture and refuses its `dark` one; a second pass that then failed the route, or failed mid-capture, would otherwise take the valid light capture and its files out of the bundle to put a worse answer in its place. So such a screen keeps its first attempt, and its `Retry.notFolded` says what the second one came to. A second attempt that keeps the same states, refused again, is taken — it is the evidence from the settled device.
    ///
    /// **Refused before anything is touched** when the two cannot be one walk — another app, build or device — or when the second attempt recorded other screens than it was sent for; and when the result would not pass the validator. The plan's identity stays the first attempt's: the second pass walked a subset of the same plan, and the bundle answers the whole of it.
    public static func foldedManifest(first: CaptureManifest, retry: CaptureManifest, settle: CaptureManifest.AppearanceSettle) throws -> CaptureManifest {
        for (field, mine, theirs) in [
            ("app", first.appBundleID, retry.appBundleID),
            ("build", first.appBuildHash, retry.appBuildHash),
            ("device", first.device.udid, retry.device.udid),
        ] where mine != theirs {
            throw AppearanceRetryError.notTheSameWalk(field: field, first: mine, retry: theirs)
        }
        let expected = settle.retried.map(\.id)
        let recorded = retry.screens.map(\.id)
        guard expected == recorded else {
            throw AppearanceRetryError.retryRecordedOtherScreens(expected: expected, recorded: recorded)
        }
        let second = Dictionary(retry.screens.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var taken = settle
        var screens = first.screens
        for index in taken.retried.indices {
            let id = taken.retried[index].id
            guard let attempt = second[id], let position = screens.firstIndex(where: { $0.id == id }) else { continue }
            if let declined = declined(first: screens[position], second: attempt) {
                taken.retried[index].notFolded = declined
            } else {
                screens[position] = attempt
            }
        }
        let folded = CaptureManifest(
            formatVersion: first.formatVersion,
            walkName: first.walkName,
            appBundleID: first.appBundleID,
            appBuildHash: first.appBuildHash,
            walkbookHash: first.walkbookHash,
            device: first.device,
            startedAt: first.startedAt,
            finishedAt: max(first.finishedAt, retry.finishedAt),
            settleQuietMilliseconds: first.settleQuietMilliseconds,
            runnerCommit: first.runnerCommit,
            appearanceSettle: taken,
            // The first attempt's own — a fold never changes which walk wrote the bundle, so the value a
            // reader checks the bundle back against (`WalkCommand.bundleWrittenBy`) must survive it too
            // (SimWalk#41), the way `runnerCommit` already does.
            nonce: first.nonce,
            animations: first.animations,
            screens: screens
        )
        let problems = CaptureManifestValidator.problems(in: folded)
        guard problems.isEmpty else {
            throw CaptureBundleError.manifestInvalid(path: "the folded manifest", problems: problems)
        }
        return folded
    }

    /// Why `second` does not replace `first`, or `nil` when it keeps every state `first` kept.
    static func declined(first: CaptureManifest.ScreenRecord, second: CaptureManifest.ScreenRecord) -> String? {
        let keptAgain = second.captures.map(\.state)
        guard !first.captures.allSatisfy({ keptAgain.contains($0.state) }) else { return nil }
        return "its second attempt kept \(names(second.captures)) and was \(CaptureBundleSummary.outcomeWords(second.outcome)), where the first kept \(names(first.captures)) — taking it would have dropped what the first attempt filed, so the first attempt stands"
    }

    private static func names(_ captures: [CaptureManifest.StateCapture]) -> String {
        captures.isEmpty ? "nothing" : "[\(captures.map(\.state.slug).joined(separator: ", "))]"
    }

    /// Folds `retry` into `first` on disk: each taken screen's artefacts replaced by the second attempt's, then the folded manifest written — last.
    ///
    /// **The first manifest goes before any artefact moves.** From then until the folded one is written the bundle has no manifest, which `CaptureBundle.read` refuses by name as unfinished; the alternative order leaves a window in which the first attempt's manifest names paths that already hold the second attempt's pictures — a record of one pass over the artefacts of another, which reads as a pass. The ordering is `CaptureBundleWriter`'s guarantee, kept across a rewrite. A screen whose second attempt was declined is not touched: its first attempt's artefacts stay where its record names them.
    ///
    /// **And nothing of the first attempt is deleted — it is set aside, so a fold that fails is undone** (the round-2 review). The manifest and each replaced screen directory move into the scratch bundle (`CaptureBundleLayout.setAsideDirectory`), and every move is recorded. The walk writes that scratch bundle inside `first` (`CaptureBundleLayout.retryScratchDirectory`), so each move is a rename on one volume and cannot stop halfway, a copy made and its source partly deleted (the round-3 review); a move that throws, or a folded manifest `finalise` refuses, puts every one back, last first, so the first attempt reads exactly as the first pass wrote it — every screen's captures included, where one screen's failed swap used to cost them all. The manifest is the first thing set aside and the last put back, so no reader ever sees the first attempt's record over a second attempt's pictures. When putting back fails as well, the error names where the first attempt still is (`AppearanceRetryError.foldNotUndone`), and the caller must keep that directory.
    @discardableResult
    public static func fold(_ retry: CaptureBundle, into first: CaptureBundle, settle: CaptureManifest.AppearanceSettle, fileManager: FileManager = .default) throws -> CaptureBundle {
        let manifest = try foldedManifest(first: first.manifest, retry: retry.manifest, settle: settle)
        let taken = manifest.appearanceSettle?.retried.filter { $0.notFolded == nil } ?? []
        var swap = Swap(first: first.url, retry: retry.url, fileManager: fileManager)
        do {
            try swap.move(CaptureBundle.manifestURL(in: first.url), to: CaptureBundle.manifestURL(in: swap.setAside))
            for record in taken {
                try swap.exchange(CaptureBundleLayout.screenDirectory(screenID: record.id))
            }
            return try CaptureBundleWriter(reopening: first.url, fileManager: fileManager).finalise(manifest)
        } catch {
            do {
                try swap.undo()
            } catch let undoError {
                throw AppearanceRetryError.foldNotUndone(setAside: swap.setAside.path, reason: "\(error)", undoReason: "\(undoError)")
            }
            throw error
        }
    }

    /// Writes `settle` into `first`'s manifest when no second attempt was folded in — the settle was declined, stopped short, or the second pass left nothing that could be — so the bundle says whether a settle was made, for which screens, and why their records are their first attempts.
    ///
    /// **A reboot the manifest does not mention is a side effect nobody can account for**, and so is one it needed and did not get. The walk's answer says it, but the answer is transient and the manifest is the record, read a week later on another machine; so the first attempt's manifest is rewritten with the settle in it, its `declined`, `settleFailure` or `secondPassFailure` saying why nothing changed. No artefact moves.
    ///
    /// **Only over a bundle a fold never touched.** A fold removes the manifest before it moves an artefact, so a bundle with no manifest is one whose artefacts may already be the second attempt's, and the first attempt's record written over them would be the lie that ordering exists to prevent — refused, and the bundle stays refused by name as unfinished.
    @discardableResult
    public static func recordUnfolded(_ settle: CaptureManifest.AppearanceSettle, in first: CaptureBundle, fileManager: FileManager = .default) throws -> CaptureBundle {
        guard fileManager.fileExists(atPath: CaptureBundle.manifestURL(in: first.url).path) else {
            throw CaptureBundleError.notWritable(path: first.url.path, reason: "its manifest is gone — a fold began and did not finish, so no record is written over artefacts it may have moved")
        }
        var manifest = first.manifest
        manifest.appearanceSettle = settle
        return try CaptureBundleWriter(reopening: first.url, fileManager: fileManager).finalise(manifest)
    }
}

extension AppearanceRetry {
    /// A fold's moves on disk, each recorded as it is made so every one can be reversed (the round-2 review).
    ///
    /// Only moves, never a removal, and only between the first bundle and the scratch bundle the second attempt was written into — which the walk puts inside the first, so every move is a rename: the second attempt's screen directories come in, the first attempt's go aside into `setAside`, and `undo` walks the record backwards.
    struct Swap {
        /// Where the first attempt's pieces go — `CaptureBundleLayout.setAsideDirectory` inside the scratch bundle.
        let setAside: URL
        private let first: URL
        private let retry: URL
        private let fileManager: FileManager
        private var moves: [(source: URL, destination: URL)] = []

        init(first: URL, retry: URL, fileManager: FileManager) {
            setAside = CaptureBundleLayout.setAsideDirectory(in: retry)
            self.first = first
            self.retry = retry
            self.fileManager = fileManager
        }

        /// One screen's directory in the first bundle replaced by the second attempt's, the first attempt's set aside rather than removed.
        ///
        /// Either may be absent: a first attempt refused whole filed nothing for the screen, and so did a second one — and then the folded record no longer names the first attempt's directory, which goes aside all the same.
        mutating func exchange(_ relativeDirectory: String) throws {
            let target = CaptureBundleLayout.url(forRelativePath: relativeDirectory, in: first)
            if fileManager.fileExists(atPath: target.path) {
                try move(target, to: CaptureBundleLayout.url(forRelativePath: relativeDirectory, in: setAside))
            }
            let source = CaptureBundleLayout.url(forRelativePath: relativeDirectory, in: retry)
            if fileManager.fileExists(atPath: source.path) {
                try move(source, to: target)
            }
        }

        /// Moves `source` to `destination`, creating the directory it lands in, and records the move for `undo`.
        mutating func move(_ source: URL, to destination: URL) throws {
            do {
                try fileManager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
                try fileManager.moveItem(at: source, to: destination)
            } catch {
                throw CaptureBundleError.notWritable(path: source.path, reason: error.localizedDescription)
            }
            moves.append((source, destination))
        }

        /// Every recorded move reversed, last first — so the first attempt's manifest, the first thing set aside, is the last put back, and only once every artefact it names is back under it.
        func undo() throws {
            for (source, destination) in moves.reversed() {
                do {
                    try fileManager.moveItem(at: destination, to: source)
                } catch {
                    throw CaptureBundleError.notWritable(path: destination.path, reason: error.localizedDescription)
                }
            }
        }
    }
}
