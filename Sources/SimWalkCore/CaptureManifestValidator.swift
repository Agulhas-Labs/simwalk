//
// Copyright © Agulhas Labs
//

import Foundation

/// Checks a manifest's invariants — the structural ones on their own, and the artefact-existence ones against a bundle on disk.
///
/// Split in two because they are answerable at different moments and by different callers: the structural half holds for a manifest anywhere, including one being assembled in memory, while the artefact half is a question about a directory. Both run at write and at read, so a bundle cannot be created in a state that reading it would refuse.
///
/// **A manifest read off disk never went through the layout-deriving initialiser** — decoding assigns the stored properties directly — so the structural half is where the bundle-path rule is actually enforced against anything that arrived as JSON. Checking only that a stated path *exists* is not enough: a path can exist and be the wrong one, or exist outside the bundle entirely.
public struct CaptureManifestValidator {
    /// Every structural problem in the manifest, in reading order — walk-level problems first, then each screen's in the order they are recorded.
    public static func problems(in manifest: CaptureManifest) -> [CaptureManifestProblem] {
        var found = walkProblems(in: manifest)
        found.append(contentsOf: screenIDCollisionProblems(in: manifest.screens))
        for (index, screen) in manifest.screens.enumerated() {
            found.append(contentsOf: problems(in: screen, at: index, formatVersion: manifest.formatVersion))
        }
        return found
    }

    /// The manifest's claims about the walk as a whole: who it attributes the bundle to, that it visited anything, and that its own two timestamps can both be true.
    ///
    /// Deliberately the mirror of `WalkbookLoader`'s walk-level checks. A manifest is what a walkbook became, so a blank in one is a blank in the other — and a bundle that names no walk, no app, no build and no device is exactly the default-filled manifest `CaptureBundle.read` promises never to accept.
    private static func walkProblems(in manifest: CaptureManifest) -> [CaptureManifestProblem] {
        var found: [CaptureManifestProblem] = [
            ("walkName", manifest.walkName),
            ("appBundleID", manifest.appBundleID),
            ("appBuildHash", manifest.appBuildHash),
            ("walkbookHash", manifest.walkbookHash),
            ("device.name", manifest.device.name),
            ("device.udid", manifest.device.udid),
            ("device.osVersion", manifest.device.osVersion),
        ]
        .filter(\.1.trimmed.isEmpty)
        .map { .blankIdentityField(name: $0.0) }
        if manifest.screens.isEmpty {
            found.append(.noScreens)
        }
        if manifest.finishedAt < manifest.startedAt {
            found.append(.finishedBeforeStarted(startedAt: manifest.startedAt, finishedAt: manifest.finishedAt))
        }
        return found + appearanceSettleProblems(in: manifest)
    }

    /// An appearance settle's claims about the screens it walked again (SimWalk#26): that there were some, each once, each one the manifest records, and each for a state its first attempt refused.
    ///
    /// The record is the only trace of a first attempt the bundle replaced, so it is held to what a walk could have written — the same reason `refusedStates` is.
    private static func appearanceSettleProblems(in manifest: CaptureManifest) -> [CaptureManifestProblem] {
        guard let settle = manifest.appearanceSettle else { return [] }
        let ids = settle.retried.map(\.id)
        var found: [CaptureManifestProblem] = settle.retried.isEmpty ? [.appearanceSettleRetriedNothing] : []
        let recorded = Set(manifest.screens.map(\.id))
        found += ids.filter { !recorded.contains($0) }.map { .appearanceSettleRetriedUnrecordedScreen(id: $0) }
        var seen: [String] = []
        for id in ids where !seen.contains(id) {
            seen.append(id)
            let occurrences = ids.count { $0 == id }
            if occurrences > 1 {
                found.append(.appearanceSettleRetriedTwice(id: id, occurrences: occurrences))
            }
        }
        found += settle.retried.filter(\.firstRefusedStates.isEmpty).map { .appearanceSettleRetryNamesNoRefusal(id: $0.id) }
        // The refusals on appearance are what a settle is made for, and they are some of the first attempt's refusals.
        // A first attempt with no refusal at all is already named above, once.
        found += settle.retried
            .filter { !$0.firstRefusedStates.isEmpty && $0.firstRefusedOnAppearance.isEmpty }
            .map { .appearanceSettleRetryNamesNoRefusalOnAppearance(id: $0.id) }
        found += settle.retried.flatMap { retry in
            retry.firstRefusedOnAppearance
                .filter { !retry.firstRefusedStates.contains($0) }
                .map { CaptureManifestProblem.appearanceSettleRefusedOnAppearanceNotRefused(id: retry.id, slug: $0.slug) }
        }
        // A settle not made stopped at no step, walked nothing again, took no time and declined no second attempt.
        if settle.declined != nil,
           settle.settleFailure != nil || settle.secondPassFailure != nil || settle.milliseconds != 0 || settle.retried.contains(where: { $0.notFolded != nil })
        {
            found.append(.appearanceSettleDeclinedYetMade)
        }
        // A screen whose second attempt was not taken still carries its first, and the settle is where that first
        // attempt is written down — so the two must agree, or the record beside the settle is nobody's.
        let records = Dictionary(manifest.screens.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        found += settle.retried.filter { !settle.folded || $0.notFolded != nil }.compactMap { retry in
            guard let record = records[retry.id],
                  record.outcome != retry.firstOutcome
                  || (record.refusedStates ?? []) != retry.firstRefusedStates
                  || (record.refusedOnAppearance ?? []) != retry.firstRefusedOnAppearance
            else { return nil }
            return .appearanceSettleUnfoldedScreenIsNotItsFirstAttempt(id: retry.id)
        }
        return found
    }

    /// One screen record's problems: its identity, its verdict against its evidence, and the paths it states.
    private static func problems(in screen: CaptureManifest.ScreenRecord, at index: Int, formatVersion: Int) -> [CaptureManifestProblem] {
        var found: [CaptureManifestProblem] = []
        if screen.id.trimmed.isEmpty {
            found.append(.blankScreenID(index: index))
        }
        switch screen.outcome {
        case .captured where screen.captures.isEmpty:
            found.append(.capturedWithoutCaptures(screenID: screen.id))
        case let .unreachable(routeTried, _, _, _):
            found.append(contentsOf: refusalProblems(in: screen))
            // `routeTaken` is what the runner completed and `routeTried` what it attempted, so the first
            // is the leading part of the second. Unconstrained they were two unrelated answers to one
            // question, and nothing could say which was the honest record.
            if !routeTried.starts(with: screen.routeTaken) {
                found.append(.routeTakenIsNotAPrefixOfRouteTried(screenID: screen.id, taken: screen.routeTaken, tried: routeTried))
            }
        case .buildMismatch:
            found.append(contentsOf: refusalProblems(in: screen))
        case let .captureFailed(reason):
            // No constraint on the capture count: a screen that recorded light and failed on dark holds
            // exactly one capture, and the bundle must be free to say so. The reason is constrained,
            // because a failure that names nothing is the vacuous verdict in its other clothes.
            if reason.trimmed.isEmpty {
                found.append(.blankFailureReason(screenID: screen.id))
            }
        case let .stateNotApplied(reason):
            // A refusal of the whole screen carries nothing — the evidence produced under its states
            // cannot be attributed to them, and filing any of it would be the lie. One that names the
            // states it refused may carry the rest, which is the point of naming them (SimWalk#15).
            // An empty list names nothing, so it licenses nothing: a decoded `"refusedStates": []` is held to
            // the whole-screen rule exactly as an absent one is.
            if screen.refusedStates?.isEmpty ?? true {
                found.append(contentsOf: refusalProblems(in: screen))
            }
            if reason.trimmed.isEmpty {
                found.append(.blankFailureReason(screenID: screen.id))
            }
        case let .unexpectedScreen(expected, screensFound, _):
            // Captures are expected here, unlike every other refusal above: a screen may hold every
            // state it was asked for and still be the wrong screen, and that evidence is exactly what a
            // reader needs kept rather than discarded.
            if expected.trimmed.isEmpty {
                found.append(.unexpectedScreenBlankExpected(screenID: screen.id))
            }
            if formatVersion < CaptureManifest.unexpectedScreenFormatVersion {
                found.append(.unexpectedScreenBeforeItsFormat(screenID: screen.id, formatVersion: formatVersion))
            }
            // No walk could write either shape (round 2 nit): `ExpectedScreenCheck` only ever produces
            // this outcome when at least one capture's identifier differs from `expected`, and it names
            // exactly the identifiers that differed — never `expected` itself.
            if screensFound.isEmpty {
                found.append(.unexpectedScreenNamesNothingFound(screenID: screen.id))
            }
            if screensFound.contains(expected) {
                found.append(.unexpectedScreenFoundNamesExpected(screenID: screen.id))
            }
        case .captured:
            break
        }
        found.append(contentsOf: refusedStateProblems(in: screen, formatVersion: formatVersion))
        // The appearance check's refusals are some of the screen's (SimWalk#26): a walk settles the device on
        // this list, so one naming a state the screen did not refuse would reboot a device over nothing it holds.
        let refusedSlugs = Set((screen.refusedStates ?? []).map(\.slug))
        found += (screen.refusedOnAppearance ?? []).map(\.slug).filter { !refusedSlugs.contains($0) }.map {
            .refusedOnAppearanceNotRefused(screenID: screen.id, slug: $0)
        }
        found.append(contentsOf: boundElementProblems(in: screen))
        found.append(contentsOf: duplicateStateProblems(in: screen))
        found.append(contentsOf: identicalToProblems(in: screen))
        found.append(contentsOf: misfiledArtefactProblems(in: screen))
        return found
    }

    /// Captures recorded identical to a base the screen does not hold as another capture.
    ///
    /// The claim is only checkable against the base's own capture — both screenshots are in the bundle to be compared — so one naming a state that was refused, never captured, or the capture itself is a claim nothing can check.
    private static func identicalToProblems(in screen: CaptureManifest.ScreenRecord) -> [CaptureManifestProblem] {
        screen.captures.compactMap { capture in
            guard let base = capture.identicalTo else { return nil }
            let others = screen.captures.map(\.state.slug).filter { $0 != capture.state.slug }
            return others.contains(base) ? nil : .identicalToUncapturedState(screenID: screen.id, slug: capture.state.slug, names: base)
        }
    }

    /// Refused states listed where no refusal was recorded, beside a capture of the same state, more than once, as an empty list, or in a format that has no such field.
    ///
    /// The writer omits the field when nothing was refused and never lists a state twice, so each of these is a manifest no walk of this tool wrote — and a reader that accepted one would be taking a claim about refused evidence from something that is not a record of any.
    private static func refusedStateProblems(in screen: CaptureManifest.ScreenRecord, formatVersion: Int) -> [CaptureManifestProblem] {
        guard let refused = screen.refusedStates else { return [] }
        var found: [CaptureManifestProblem] = []
        if formatVersion < CaptureManifest.refusedStatesFormatVersion {
            found.append(.refusedStatesBeforeTheirFormat(screenID: screen.id, formatVersion: formatVersion))
        }
        if refused.isEmpty {
            found.append(.emptyRefusedStates(screenID: screen.id))
        }
        found += SlugGroup.colliding(SlugGroup.grouping(refused.map(\.slug))).map { group in
            .duplicateRefusedState(screenID: screen.id, slug: group.slug, occurrences: group.values.count)
        }
        // Exhaustive, so an outcome added later has to decide here whether it may carry refused states
        // rather than inheriting a passing default. `unexpectedScreen` joined `stateNotApplied` in round
        // 2: a screen can be the wrong one *and* have a state the device discarded at the same time, and
        // `StateApplicationCheck.refusedOutcome` now records both rather than picking one.
        switch screen.outcome {
        case .stateNotApplied, .unexpectedScreen:
            break
        case .captured, .unreachable, .buildMismatch, .captureFailed:
            found.append(.refusedStatesOutsideRefusal(screenID: screen.id))
        }
        let refusedSlugs = Set(refused.map(\.slug))
        found += screen.captures.map(\.state.slug).filter(refusedSlugs.contains).map {
            .stateCapturedAndRefused(screenID: screen.id, slug: $0)
        }
        return found
    }

    /// Bound elements that name a step the screen did not take, or one that binds no element (SimWalk#96).
    private static func boundElementProblems(in screen: CaptureManifest.ScreenRecord) -> [CaptureManifestProblem] {
        (screen.boundElements ?? []).compactMap { bound in
            guard screen.routeTaken.indices.contains(bound.step) else {
                return .boundElementStepOutOfRange(screenID: screen.id, step: bound.step, routeLength: screen.routeTaken.count)
            }
            return switch screen.routeTaken[bound.step] {
            case .tap, .scrollTo, .type:
                nil
            default:
                .boundElementOnStepThatBindsNothing(screenID: screen.id, step: bound.step, routeStep: screen.routeTaken[bound.step])
            }
        }
    }

    private static func refusalProblems(in screen: CaptureManifest.ScreenRecord) -> [CaptureManifestProblem] {
        guard !screen.captures.isEmpty else { return [] }
        return [.refusalWithCaptures(screenID: screen.id, count: screen.captures.count)]
    }

    /// States a screen claims more than once.
    ///
    /// Both captures derive the same two paths, so the misfiled check compares each stated path to the path it is identical to and the existence check finds the one real file — the bundle inspects as "2 captures" over one screenshot. `WalkbookLoader` refuses the walkbook that would ask for it; this refuses the manifest that claims it happened anyway.
    private static func duplicateStateProblems(in screen: CaptureManifest.ScreenRecord) -> [CaptureManifestProblem] {
        SlugGroup.colliding(SlugGroup.grouping(screen.captures.map(\.state.slug))).map { group in
            .duplicateCaptureState(screenID: screen.id, slug: group.slug, occurrences: group.values.count)
        }
    }

    /// Every claimed artefact that is not present in `bundleURL`, in reading order.
    ///
    /// Only meaningful alongside `problems(in:)`, which is what confines the paths to the bundle first — on its own this would happily confirm the existence of a file the manifest reached outside the directory to name.
    public static func missingArtefactProblems(
        for manifest: CaptureManifest,
        in bundleURL: URL,
        fileManager: FileManager = .default
    ) -> [CaptureManifestProblem] {
        manifest.screens.flatMap { screen in
            screen.captures.flatMap { capture in
                ([capture.screenshotPath, capture.axTreePath] + [capture.appleAudit?.path].compactMap(\.self)).compactMap { path -> CaptureManifestProblem? in
                    let url = CaptureBundleLayout.url(forRelativePath: path, in: bundleURL)
                    guard !fileManager.fileExists(atPath: url.path) else { return nil }
                    return .artefactMissing(screenID: screen.id, stateSlug: capture.state.slug, expectedPath: path)
                }
            }
        }
    }

    /// Captures recorded `identicalTo` a base whose screenshot on disk is not byte-identical to theirs.
    ///
    /// The claim is that the two renders are one picture, and both pictures are in the bundle — so it is checked against them, rather than taken from the writer that made it. A capture naming a base the screen did not capture is `problems(in:)`'s to report; this compares only pairs that are both on disk.
    public static func identicalToProblems(
        for manifest: CaptureManifest,
        in bundleURL: URL,
        fileManager: FileManager = .default
    ) -> [CaptureManifestProblem] {
        manifest.screens.flatMap { screen in
            screen.captures.compactMap { capture -> CaptureManifestProblem? in
                guard let baseSlug = capture.identicalTo,
                      let base = screen.captures.first(where: { $0.state.slug == baseSlug && $0.state.slug != capture.state.slug }),
                      let mine = fileManager.contents(atPath: CaptureBundleLayout.url(forRelativePath: capture.screenshotPath, in: bundleURL).path),
                      let theirs = fileManager.contents(atPath: CaptureBundleLayout.url(forRelativePath: base.screenshotPath, in: bundleURL).path)
                else {
                    return nil
                }
                return mine == theirs ? nil : .identicalToDiffers(screenID: screen.id, slug: capture.state.slug, names: baseSlug)
            }
        }
    }

    /// Captures whose stated paths are not the ones the layout derives for their screen and state.
    private static func misfiledArtefactProblems(in screen: CaptureManifest.ScreenRecord) -> [CaptureManifestProblem] {
        screen.captures.flatMap { capture -> [CaptureManifestProblem] in
            let slug = capture.state.slug
            var expected = [
                CaptureBundleLayout.screenshotPath(screenID: screen.id, stateSlug: slug),
                CaptureBundleLayout.axTreePath(screenID: screen.id, stateSlug: slug),
            ]
            var stated = [capture.screenshotPath, capture.axTreePath]
            if let audit = capture.appleAudit {
                expected.append(CaptureBundleLayout.appleAuditPath(screenID: screen.id, stateSlug: slug))
                stated.append(audit.path)
            }
            return zip(stated, expected).compactMap { stated, expected in
                guard stated != expected else { return nil }
                return .misfiledArtefact(screenID: screen.id, stateSlug: slug, stated: stated, expected: expected)
            }
        }
    }

    /// Screen records that would share a bundle directory — the same question `WalkbookLoader` asks of the plan, asked of the record, through the same grouping so the two answers cannot drift.
    private static func screenIDCollisionProblems(in screens: [CaptureManifest.ScreenRecord]) -> [CaptureManifestProblem] {
        ScreenIDCollision.all(among: screens.map(\.id).filter { !$0.trimmed.isEmpty }).map { collision in
            switch collision {
            case let .duplicate(id, occurrences):
                .duplicateScreenID(id: id, occurrences: occurrences)
            case let .colliding(slug, ids):
                .collidingScreenIDs(slug: slug, ids: ids)
            }
        }
    }
}
