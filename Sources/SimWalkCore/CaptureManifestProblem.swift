//
// Copyright © Agulhas Labs
//

import Foundation

/// One specific way a manifest fails to describe a walk that could have happened.
///
/// The honest contract is only honest if the manifest cannot state both things at once. `ScreenOutcome.captured` beside an empty `captures` list round-trips perfectly well as JSON and renders as a pass, which is precisely the vacuous verdict the differ exists to end — so the invariant is checked, in the same shape as `WalkbookProblem`, at both ends of the bundle: when it is written and when it is read.
///
/// **Every blankness `WalkbookProblem` reports has a counterpart here**, deliberately. A walkbook and the manifest of the walk it produced describe the same two things — which walk, against which app — and a refusal that reads "does not describe a walk that could have happened" while accepting a nameless walk against no app, with no screens, that finished before it started, is not checking that at all.
public enum CaptureManifestProblem: Equatable, Sendable, CustomStringConvertible {
    /// A field that attributes the bundle — the walk, the app, the build, the walkbook, the device — is blank.
    case blankIdentityField(name: String)
    /// The manifest records no screens, so the walk it attests to visited nothing.
    case noScreens
    /// The walk finished before it started, so its own timestamps cannot both be true.
    case finishedBeforeStarted(startedAt: Date, finishedAt: Date)
    /// A screen record carries no id; the payload is its position, since a problem reported against `''` names nothing.
    case blankScreenID(index: Int)
    /// A screen claims to have been captured but lists no captures.
    case capturedWithoutCaptures(screenID: String)
    /// A screen claims the same state twice, so two captures are backed by one artefact pair.
    case duplicateCaptureState(screenID: String, slug: String, occurrences: Int)
    /// A screen states a refusal yet carries captures, so it is claiming both to have failed and to have produced evidence.
    case refusalWithCaptures(screenID: String, count: Int)
    /// A screen reports a capture failure without naming one, which is a refusal that tells a reader nothing.
    case blankFailureReason(screenID: String)
    /// A screen lists refused states under a verdict that is not `stateNotApplied` — a `captured` screen that also refused a state is a passing outcome over a bundle that does not hold what was asked for.
    case refusedStatesOutsideRefusal(screenID: String)
    /// A screen lists one state as both captured and refused, so it is claiming the state's evidence both could and could not be attributed to it.
    case stateCapturedAndRefused(screenID: String, slug: String)
    /// A screen lists refused states as an empty list, which names nothing — the writer omits the field instead.
    case emptyRefusedStates(screenID: String)
    /// A screen lists one refused state more than once.
    case duplicateRefusedState(screenID: String, slug: String, occurrences: Int)
    /// A screen lists refused states in a bundle format older than the one that introduced them.
    case refusedStatesBeforeTheirFormat(screenID: String, formatVersion: Int)
    /// A screen's completed route is not the leading part of the route it says it attempted, so the record answers "what did the runner do" twice, differently.
    case routeTakenIsNotAPrefixOfRouteTried(screenID: String, taken: [Walkbook.RouteStep], tried: [Walkbook.RouteStep])
    /// A bound-element record names a step that is not an index into the screen's `routeTaken`, so it says an element was bound by a step the screen never completed (SimWalk#96).
    case boundElementStepOutOfRange(screenID: String, step: Int, routeLength: Int)
    /// A bound-element record names a step that binds no element — only a `tap`, `scrollTo` or `type` step does (SimWalk#96).
    case boundElementOnStepThatBindsNothing(screenID: String, step: Int, routeStep: Walkbook.RouteStep)
    /// A capture says it is identical to a state the screen did not capture, or to itself — so the base its render is claimed to match is not in the bundle to be compared with.
    case identicalToUncapturedState(screenID: String, slug: String, names: String)
    /// A capture says it is identical to its base, and the two screenshots on disk differ.
    case identicalToDiffers(screenID: String, slug: String, names: String)
    /// A capture names an artefact that is not in the bundle — the run that wrote it did not finish, or something removed it since.
    case artefactMissing(screenID: String, stateSlug: String, expectedPath: String)
    /// A capture states a path that is not the one the layout derives for it — a dark capture pointing at the light screenshot, or a path climbing out of the bundle entirely.
    case misfiledArtefact(screenID: String, stateSlug: String, stated: String, expected: String)
    /// Two screen records share an id, so a reader cannot tell which one an artefact belongs to.
    case duplicateScreenID(id: String, occurrences: Int)
    /// Screen records with different ids that file under one directory — distinct to a reader, one directory to the filesystem.
    case collidingScreenIDs(slug: String, ids: [String])
    /// An `unexpectedScreen` names no identifier its captures actually held — `ExpectedScreenCheck` never produces that shape, so no walk wrote this record.
    case unexpectedScreenNamesNothingFound(screenID: String)
    /// An `unexpectedScreen` lists the very identifier it expected among what it found — a mismatch that names no mismatch, which `ExpectedScreenCheck` never produces either.
    case unexpectedScreenFoundNamesExpected(screenID: String)
    /// A screen is recorded `unexpectedScreen` in a bundle format older than the one that introduced the verdict.
    case unexpectedScreenBeforeItsFormat(screenID: String, formatVersion: Int)
    /// An `unexpectedScreen` names a blank identifier as the one it expected — `validate` refuses a blank `expect`, so no walk checked against one.
    case unexpectedScreenBlankExpected(screenID: String)
    /// A screen names a state as refused on appearance that its `refusedStates` does not hold — the appearance check's refusals are some of the screen's refusals, never others (SimWalk#26).
    case refusedOnAppearanceNotRefused(screenID: String, slug: String)
    /// An appearance settle records no screen walked again after it — a reboot the walk made for nothing it recorded, which no walk does (SimWalk#26).
    case appearanceSettleRetriedNothing
    /// An appearance settle names a screen walked again that the manifest holds no record of, so the second attempt it claims is nowhere in the bundle.
    case appearanceSettleRetriedUnrecordedScreen(id: String)
    /// An appearance settle names one screen more than once — a screen is walked again once.
    case appearanceSettleRetriedTwice(id: String, occurrences: Int)
    /// An appearance settle names a screen whose first attempt refused no state — the only reason a screen is walked again.
    case appearanceSettleRetryNamesNoRefusal(id: String)
    /// An appearance settle says a screen's second attempt was not folded in, and the screen's record is not the first attempt the settle names — so the bundle holds a record nothing accounts for.
    case appearanceSettleUnfoldedScreenIsNotItsFirstAttempt(id: String)
    /// An appearance settle names a screen whose first attempt refused states, none of them on appearance — the only refusal a settle is made for.
    case appearanceSettleRetryNamesNoRefusalOnAppearance(id: String)
    /// An appearance settle names a state as refused on appearance in a screen's first attempt that the first attempt did not refuse.
    case appearanceSettleRefusedOnAppearanceNotRefused(id: String, slug: String)
    /// An appearance settle says it was not made, and records what only a settle that was made could — a step it stopped at, a second pass, a time, or a screen's second attempt.
    case appearanceSettleDeclinedYetMade

    public var description: String {
        switch self {
        case let .blankIdentityField(name):
            "manifest field '\(name)' is blank — a bundle nothing can be attributed to cannot be compared with another"
        case .noScreens:
            "screens is empty — a walk that visited nothing captured nothing"
        case let .finishedBeforeStarted(startedAt, finishedAt):
            "the walk finished at \(Timestamp.string(from: finishedAt)), before it started at \(Timestamp.string(from: startedAt))"
        case let .blankScreenID(index):
            "screen record at index \(index) has a blank id — captures, diffs and oracle answers are keyed by it, and it is the directory its artefacts file under"
        case let .capturedWithoutCaptures(screenID):
            "screen '\(screenID)' is recorded as captured but lists no captures — a pass with no evidence is not a pass"
        case let .duplicateCaptureState(screenID, slug, occurrences):
            "screen '\(screenID)' claims state '\(slug)' \(occurrences) times — they are one directory, so the bundle is claiming more than it holds"
        case let .refusalWithCaptures(screenID, count):
            "screen '\(screenID)' states a refusal yet carries \(count) capture\(count == 1 ? "" : "s") — a refusal produces none"
        case let .blankFailureReason(screenID):
            "screen '\(screenID)' reports a capture failure with no reason — a refusal that names nothing is the vacuous verdict this format exists to end"
        case let .refusedStatesOutsideRefusal(screenID):
            "screen '\(screenID)' lists refused states under a verdict that cannot refuse a state (only state-not-applied, or an unexpected screen whose reason carries one, can) — a screen that refused a state does not hold what was asked for, and its outcome has to say so"
        case let .stateCapturedAndRefused(screenID, slug):
            "screen '\(screenID)' lists state '\(slug)' as both captured and refused — its evidence either could be attributed to it or could not"
        case let .emptyRefusedStates(screenID):
            "screen '\(screenID)' lists an empty set of refused states — a refusal that names no state names nothing, and the writer leaves the field out instead"
        case let .duplicateRefusedState(screenID, slug, occurrences):
            "screen '\(screenID)' lists refused state '\(slug)' \(occurrences) times — one state is refused once"
        case let .refusedStatesBeforeTheirFormat(screenID, formatVersion):
            "screen '\(screenID)' lists refused states in a format-\(formatVersion) bundle — they arrived in format \(CaptureManifest.refusedStatesFormatVersion), so no walk wrote this"
        case let .routeTakenIsNotAPrefixOfRouteTried(screenID, taken, tried):
            "screen '\(screenID)' completed \(taken.rendered) but reports attempting \(tried.rendered) — what it completed is the leading part of what it attempted, or the record contradicts itself"
        case let .boundElementStepOutOfRange(screenID, step, routeLength):
            "screen '\(screenID)' records an element bound by step \(step), but its route completed \(routeLength) step\(routeLength == 1 ? "" : "s") — the step is not one the screen took"
        case let .boundElementOnStepThatBindsNothing(screenID, step, routeStep):
            "screen '\(screenID)' records an element bound by step \(step), \(routeStep) — only a tap, scrollTo or type step binds an element"
        case let .identicalToUncapturedState(screenID, slug, names):
            "screen '\(screenID)' state '\(slug)' says it is identical to '\(names)', which is not another state this screen captured — a render claimed to match a base the bundle does not hold matches nothing"
        case let .identicalToDiffers(screenID, slug, names):
            "screen '\(screenID)' state '\(slug)' says it is identical to '\(names)', and the two screenshots on disk differ — the claim that licensed filing both is not true of what was filed"
        case let .artefactMissing(screenID, stateSlug, expectedPath):
            "screen '\(screenID)' state '\(stateSlug)' claims \(expectedPath), which is not in the bundle"
        case let .misfiledArtefact(screenID, stateSlug, stated, expected):
            "screen '\(screenID)' state '\(stateSlug)' claims \(stated) where the layout files it at \(expected) — a path is derived, never stated"
        case let .duplicateScreenID(id, occurrences):
            "screen id '\(id)' appears \(occurrences) times — a reader cannot tell which record an artefact belongs to"
        case let .collidingScreenIDs(slug, ids):
            "screen ids \(ids.map { "'\($0)'" }.joined(separator: ", ")) all file under '\(slug)' — they are one directory on disk, so a reader cannot tell whose artefacts these are"
        case let .unexpectedScreenNamesNothingFound(screenID):
            "screen '\(screenID)' is recorded as the wrong screen but names no identifier it found instead — a mismatch names what mismatched"
        case let .unexpectedScreenFoundNamesExpected(screenID):
            "screen '\(screenID)' lists its own expected identifier among what it found — that is not a mismatch, and no walk records one that way"
        case let .unexpectedScreenBeforeItsFormat(screenID, formatVersion):
            "screen '\(screenID)' is recorded as the wrong screen in a format-\(formatVersion) bundle — that verdict arrived in format \(CaptureManifest.unexpectedScreenFormatVersion), so no walk wrote this"
        case let .unexpectedScreenBlankExpected(screenID):
            "screen '\(screenID)' is recorded as the wrong screen against a blank expected identifier — a walkbook's expect is never blank, so no walk checked against one"
        case let .refusedOnAppearanceNotRefused(screenID, slug):
            "screen '\(screenID)' names state '\(slug)' as refused on appearance, and does not list it among its refused states — a refusal on appearance is one of the screen's refusals"
        case .appearanceSettleRetriedNothing:
            "the appearance settle names no screen walked again after it — a walk settles the device only for the screens it then walks again"
        case let .appearanceSettleRetriedUnrecordedScreen(id):
            "the appearance settle names screen '\(id)' as walked again, and the manifest holds no record of it — the second attempt it claims is not in the bundle"
        case let .appearanceSettleRetriedTwice(id, occurrences):
            "the appearance settle names screen '\(id)' \(occurrences) times — a screen is walked again once"
        case let .appearanceSettleUnfoldedScreenIsNotItsFirstAttempt(id):
            "the appearance settle says screen '\(id)' kept its first attempt, and its record is not the first attempt the settle names — a record nothing in the bundle accounts for"
        case let .appearanceSettleRetryNamesNoRefusal(id):
            "the appearance settle names screen '\(id)' with no state its first attempt refused — a refused state is the only reason a screen is walked again"
        case let .appearanceSettleRetryNamesNoRefusalOnAppearance(id):
            "the appearance settle names screen '\(id)' with no state its first attempt refused on appearance — a refusal on appearance is the only one a settle is made for"
        case let .appearanceSettleRefusedOnAppearanceNotRefused(id, slug):
            "the appearance settle names state '\(slug)' as refused on appearance in screen '\(id)''s first attempt, which does not list it among the states it refused — a refusal on appearance is one of the first attempt's refusals"
        case .appearanceSettleDeclinedYetMade:
            "the appearance settle says it was not made, and records a step it stopped at, a second pass, a time or a screen's second attempt — a settle not made did none of those"
        }
    }
}
