//
// Copyright © Agulhas Labs
//

import Foundation

/// Whether the capture states a screen was walked under actually applied, judged from the evidence they produced.
///
/// **The hole this closes is the tool's one unforgivable failure class.** Every state axis is a claim the bundle cannot check after the fact: a walkbook asks for `dark`, the runner sets it, the device reports it set, and iOS 26.5 changes nothing — so the light render is filed under `screens/<id>/dark/`, outcome `captured`, every format check passing. Nothing downstream can see what a screenshot depicts, so a differ, an oracle and a reader all take the label at its word. That is a passing bundle made of false evidence, and it cost the 2026-08-20 field round its whole dark dimension (SimWalk#1 item 3).
///
/// **The first check is that two distinct states cannot have produced the same picture.** `WalkbookLoader` already refuses two states that slug alike, so every state on a screen differs in at least one axis it asked the device to honour; if two of them come back byte-identical, at least one of those axes was discarded in silence. It needs no knowledge of what any axis *means*, which is what lets one rule reach `theme`, `dynamicTypeSize` and `locale` alike.
///
/// **How far that reaches is smaller than it sounds, and the branch that built it measured the gap.** Byte identity is defeated by a status-bar clock advancing between two shots, so it catches a discarded axis only when both captures landed inside the same minute. `theme` has a second, measured check behind it; `dynamicTypeSize` and `locale` have only this one, so on those two axes a silent discard is caught opportunistically rather than reliably. Recorded as an open item in Brief §8 rather than papered over — the honest summary is that one axis is guarded and two are watched.
///
/// **It is a one-way test, and says so.** Identity proves a state did not apply; difference proves nothing — a status-bar clock ticking between two shots is enough to make two identical renders differ. So this refuses what it can prove and never certifies the rest, which is why its answer is an optional refusal rather than a verdict either way.
///
/// **Identity alone was measured to be insufficient**, on the very run that was meant to demonstrate it: a real app's Browse screen on 2026-08-20 produced a `light` and a `dark` capture differing by 41 bytes in 249 KB — the clock — with the mean colour of the two identical to the byte at `(238, 237, 234)`. Both light, both filed, nothing refused. So the byte comparison keeps its place as the axis-agnostic half and a second, theme-specific check stands beside it: dark mode inverts a screen's ground, which is a *measurable* claim in a way that "the locale applied" is not.
///
/// **A refusal costs the states it names, not the screen (SimWalk#15).** The first version refused the whole screen on any finding, on the grounds that two identical renders cannot say which of them is honest. That holds for an axis nothing can measure, and it is still what happens there. It does not hold for appearance, where the device's own appearance says which side of a failed comparison can be trusted — and refusing the whole screen cost a 2026-09-10 field round six screens whose light states were perfectly capturable, including the two the round existed to look at. So each finding names the states it implicates, and the rest of the screen is filed.
public struct StateApplicationCheck {
    /// The reason to refuse states on this screen, or `nil` when nothing here can be shown to have gone unapplied.
    ///
    /// Reported as one sentence naming everything found, because a screen walked under four states with two problems has made one mistake in one walkbook and reading it four refusals later helps nobody. Fewer than two states can collide with nothing and are answered without comparing anything.
    ///
    /// `fixedAppearance` is the screen's `fixedAppearance` key (SimWalk#19): the walkbook says the app, not the device, picks this screen's appearance, so no appearance comparison is made and two states differing only in `theme` are not a collision.
    ///
    /// `deviceAppearance` is the simulator's own appearance as the host read it before the walk — `nil` when it could not be read, which is the answer that refuses more rather than less. `deviceLocale` is the locale the device was already in, as the host read it — `nil` when it could not be read or named no single locale, which again refuses more.
    public static func refusal(for evidence: [Evidence], deviceAppearance: Walkbook.Theme? = nil, deviceLocale: String? = nil, fixedAppearance: Walkbook.Theme? = nil) -> String? {
        findings(for: evidence, deviceAppearance: deviceAppearance, deviceLocale: deviceLocale, fixedAppearance: fixedAppearance)?.reason
    }

    /// The states whose evidence cannot be attributed to them, in capture order — empty when nothing is refused.
    ///
    /// Every other state on the screen may be filed: no finding implicates it.
    public static func refusedStates(for evidence: [Evidence], deviceAppearance: Walkbook.Theme? = nil, deviceLocale: String? = nil, fixedAppearance: Walkbook.Theme? = nil) -> [Walkbook.CaptureState] {
        findings(for: evidence, deviceAppearance: deviceAppearance, deviceLocale: deviceLocale, fixedAppearance: fixedAppearance)?.refused ?? []
    }

    /// The verdict a screen must be recorded under instead of `intended`, or `nil` when its evidence may be filed as planned.
    ///
    /// **Every path that files a capture goes through here, not just the one that succeeded.** The first version ran the check only where a screen had captured every state it was asked for, so a screen that captured light, then failed reading dark, filed the light capture unchecked under `captureFailed` — and if that light capture was itself a `dark` state's render, the bundle held exactly the false evidence this whole mechanism exists to prevent, with a plausible outcome sitting beside it. A partial walk is where an unapplied state is *most* likely, not least: whatever broke the third state was in the same environment as the first two.
    ///
    /// The intended verdict is not discarded when it carried one — a screen that both failed mid-capture and cannot attribute what it did capture has two things wrong with it, and the refusal names both. The refusal leads, because it is the one that decides what may be filed.
    ///
    /// **`unexpectedScreen` is the one intended outcome this does not fold into `stateNotApplied` (round 2).** Every other case is a finding this check can absorb into one sentence about the device; `unexpectedScreen` is a finding about the route, carrying its own `expected`/`found` that a `stateNotApplied` verdict has nowhere to put — discarding them to report only the state refusal would un-diagnose the wrong screen the walk actually reached. So the shape stays `unexpectedScreen` and the state finding rides in its own `reason` instead, exactly where `unreachable` already carries a second thing to say.
    public static func refusedOutcome(
        for evidence: [Evidence],
        instead intended: ScreenOutcome,
        deviceAppearance: Walkbook.Theme? = nil,
        deviceLocale: String? = nil,
        fixedAppearance: Walkbook.Theme? = nil
    ) -> ScreenOutcome? {
        refusal(for: evidence, deviceAppearance: deviceAppearance, deviceLocale: deviceLocale, fixedAppearance: fixedAppearance).map { outcome(refusing: $0, instead: intended) }
    }

    /// `intended` with a state refusal given `reason` folded in — the one place the shapes above are decided.
    private static func outcome(refusing reason: String, instead intended: ScreenOutcome) -> ScreenOutcome {
        switch intended {
        case let .captureFailed(failure):
            return .stateNotApplied(reason: "\(reason). The screen also failed mid-capture: \(failure)")
        case let .unexpectedScreen(expected, found, existing):
            let combined = existing.map { "\($0). \(reason)" } ?? reason
            return .unexpectedScreen(expected: expected, found: found, reason: combined)
        // Exhaustive rather than `default:`, so an outcome added later has to decide here whether a state
        // refusal replaces it or rides in it, instead of quietly becoming `stateNotApplied`.
        case .captured, .unreachable, .buildMismatch, .stateNotApplied:
            return .stateNotApplied(reason: reason)
        }
    }

    /// What a screen's taken states become: the outcome to record, the states to file, the states refused, and which kept states are honestly identical to another.
    ///
    /// The one decision the runner needs, made here so `swift test` can hold it — the runner only writes what `kept` names.
    public static func filing(
        for evidence: [Evidence],
        instead intended: ScreenOutcome,
        deviceAppearance: Walkbook.Theme? = nil,
        deviceLocale: String? = nil,
        fixedAppearance: Walkbook.Theme? = nil
    ) -> Filing {
        let found = findings(for: evidence, deviceAppearance: deviceAppearance, deviceLocale: deviceLocale, fixedAppearance: fixedAppearance)
        let refused = found?.refused ?? []
        let kept = evidence.map(\.state).filter { !refused.contains($0) }
        let identical = identicalToBase(in: evidence, deviceLocale: deviceLocale, fixedAppearance: fixedAppearance).filter { kept.contains($0.state) && kept.contains($0.base) }
        let unverified = unverified(in: evidence, kept: kept)
        guard let found else {
            return Filing(outcome: intended, kept: kept, refused: [], identicalToBase: identical, unverified: unverified)
        }
        return Filing(
            outcome: outcome(refusing: found.reason, instead: intended),
            kept: kept,
            refused: refused,
            refusedOnAppearance: found.onAppearance,
            identicalToBase: identical,
            unverified: unverified
        )
    }

    /// Every finding on the screen, joined: one sentence, the union of the states they implicate in capture order, and those of them the appearance check implicated.
    private static func findings(
        for evidence: [Evidence],
        deviceAppearance: Walkbook.Theme?,
        deviceLocale: String?,
        fixedAppearance: Walkbook.Theme?
    ) -> Joined? {
        let measured = evidence.compactMap { item in
            ScreenshotBrightness.mean(ofPNG: item.screenshot).map { Measured(item: item, brightness: $0) }
        }
        let collision = identicalScreenshotFinding(for: evidence, deviceLocale: deviceLocale, fixedAppearance: fixedAppearance)
        // A screen whose appearance the walkbook fixes (SimWalk#19) has no appearance comparison to make: nothing is refused on it.
        let comparison = fixedAppearance == nil ? unappliedAppearanceFinding(for: measured, deviceAppearance: deviceAppearance) : nil
        let found = [
            collision,
            comparison,
            fixedAppearance == nil ? brightDarkFinding(for: measured, besides: comparison?.refused ?? []) : nil,
            fixedAppearance == nil ? unmeasuredDarkFinding(for: evidence, measured: measured, besides: collision?.refused ?? []) : nil,
            layoutDirectionFinding(for: evidence),
            orientationFinding(for: evidence),
        ].compactMap(\.self)
        guard !found.isEmpty else { return nil }
        let implicated = found.flatMap(\.refused)
        let onAppearance = found.filter(\.onAppearance).flatMap(\.refused)
        return Joined(
            reason: found.map(\.reason).joined(separator: "; also "),
            refused: evidence.map(\.state).filter { implicated.contains($0) },
            onAppearance: evidence.map(\.state).filter { onAppearance.contains($0) }
        )
    }

    /// Two states that produced one picture, which no two distinct states can honestly have done.
    ///
    /// **Every state in a colliding group is refused, because nothing here can say which of them is honest** — the app may have been held in one state's conditions throughout, or in the device's ambient ones, and both readings fit the evidence exactly.
    ///
    /// **Except where the group differs in appearance alone and every picture in it measures.** Then the collision is a discarded `theme`, and the appearance finding is guaranteed to fire on it — two identical pictures are identically bright, so the dark one is no darker — and it decides from the device's known appearance which is honest, or refuses both when that is not known. This is not a corner: a light and a dark capture taken inside the same minute share their status-bar clock and are byte-identical whenever the appearance was discarded, so refusing them wholesale here would have undone the whole of SimWalk#15 on every screen fast enough to walk twice in a minute.
    ///
    /// **And except where the states are not distinct at all once the device is taken into account (SimWalk#18).** A state that leaves its locale unset launches in the device's own, so on a device already in `en_GB` the plain `light` state and `light-loc_en_gb` ask for one set of conditions, and one picture is the *right* result — the identity rule used to read it as a discard and refuse both. Comparison is by the conditions each state launched under, so a group is a collision only when those differ. An unset layout direction is resolved the same way, to the direction of the locale the state launched in, so on an `en_US` device the plain `light` state and `light-ltr` ask for one set of conditions too.
    ///
    /// **And except where the group differs in layout direction alone.** A mirror-symmetric screen — centred content, nothing side by side — draws one picture both ways round, so identity cannot say whether the direction took; the frames can, and `layoutDirectionFinding` judges each state that stated a direction by them: refused when every run goes the wrong way, filed unverified when there is no run to judge. Refusing the pair wholesale here also refused the plain state beside it, which certainly applied.
    ///
    /// **And except where the group differs in orientation alone (SimWalk#199).** An unset orientation is resolved to the one the capture's root frame shows, so `[light, light-portrait]` on a portrait device asks for one set of conditions and is filed identical, not refused. What is left differing in orientation alone is a state whose frame contradicts it — `orientationFinding` refuses that one, and only that one, since the plain state beside it asked for nothing it did not get — or one whose frame is square or empty, which is filed unverified.
    ///
    /// **And a stated orientation its frame contradicts is compared as the frame's (SimWalk#217).** `[light, dark-landscape]` on a portrait-only app that also ignores `dark` differs in two axes by what was stated, so neither exception above would apply and `light`, which applied, would be refused with it. The contradicted orientation is already refused by `orientationFinding`, so for this comparison it is read as the one the app kept, the group then differs in appearance alone, and the appearance finding judges the pair.
    private static func identicalScreenshotFinding(for evidence: [Evidence], deviceLocale: String?, fixedAppearance: Walkbook.Theme?) -> Finding? {
        let collisions = identicalGroups(in: evidence).filter { group in
            let conditions = distinctConditions(of: group, deviceLocale: deviceLocale, resolvingContradictedOrientation: true, fixedAppearance: fixedAppearance)
            return conditions.count > 1 && !isLeftToAppearance(conditions, group: group) && !isLeftToLayoutDirection(conditions)
                && !isLeftToOrientation(conditions)
        }
        guard !collisions.isEmpty else { return nil }
        let described = collisions
            .map { group in group.map { "'\($0.stateSlug)'" }.joined(separator: " and ") }
            .joined(separator: "; ")
        return Finding(
            reason: "states \(described) produced byte-identical screenshots — a state the device discarded in silence, so a capture filed under either would be the device's ambient render labelled as something it is not",
            refused: collisions.flatMap { $0.map(\.state) },
            onAppearance: false
        )
    }

    /// Whether a colliding group is one the appearance finding attributes rather than one refused wholesale: its distinct conditions differ in appearance alone, and every picture in it measures.
    private static func isLeftToAppearance(_ conditions: [Walkbook.CaptureState], group: [Evidence]) -> Bool {
        Set(conditions.map(\.theme)).count == conditions.count
            && Set(conditions.map(\.dynamicTypeSize)).count == 1
            && Set(conditions.map(\.locale)).count == 1
            && Set(conditions.map(\.layoutDirection)).count == 1
            && Set(conditions.map(\.orientation)).count == 1
            && group.allSatisfy { ScreenshotBrightness.mean(ofPNG: $0.screenshot) != nil }
    }

    /// Whether a colliding group is one the layout-direction finding judges by its frames rather than one refused wholesale: its distinct conditions differ in layout direction alone.
    private static func isLeftToLayoutDirection(_ conditions: [Walkbook.CaptureState]) -> Bool {
        Set(conditions.map(\.layoutDirection)).count == conditions.count
            && Set(conditions.map(\.theme)).count == 1
            && Set(conditions.map(\.dynamicTypeSize)).count == 1
            && Set(conditions.map(\.locale)).count == 1
            && Set(conditions.map(\.orientation)).count == 1
    }

    /// Whether a colliding group is one the orientation finding judges by its root frames rather than one refused wholesale: its distinct conditions differ in orientation alone.
    private static func isLeftToOrientation(_ conditions: [Walkbook.CaptureState]) -> Bool {
        Set(conditions.map(\.orientation)).count == conditions.count
            && Set(conditions.map(\.theme)).count == 1
            && Set(conditions.map(\.dynamicTypeSize)).count == 1
            && Set(conditions.map(\.locale)).count == 1
            && Set(conditions.map(\.layoutDirection)).count == 1
    }

    /// The distinct conditions a group's states launched under, in capture order — each state with its locale resolved to the device's when it names none.
    private static func distinctConditions(
        of group: [Evidence],
        deviceLocale: String?,
        resolvingContradictedOrientation: Bool,
        fixedAppearance: Walkbook.Theme?
    ) -> [Walkbook.CaptureState] {
        var distinct: [Walkbook.CaptureState] = []
        for item in group {
            let launched = conditions(of: item, deviceLocale: deviceLocale, resolvingContradictedOrientation: resolvingContradictedOrientation, fixedAppearance: fixedAppearance)
            if !distinct.contains(launched) {
                distinct.append(launched)
            }
        }
        return distinct
    }

    /// The conditions a state's app actually launched under, as far as this rule judges them: its own axes, with an unset locale read as the device's, an unset layout direction as that locale's, and an unset orientation as the one its capture's root frame shows.
    ///
    /// **A state's `arguments` and `environment` are left out, deliberately (SimWalk#44).** SimWalk cannot know whether an argument reaches the screen at all, and one picture under different arguments is a legitimate result: an app's own launch argument (a data-seeding flag) raises a sheet the route then answers, and the screen it lands on is the one the plain state lands on. So two states differing only there compare as one set of conditions, and a byte-identical pair is filed with `identicalTo` naming the base rather than refused. What the rule does hold them to is everything else — a state with an argument *and* a locale the device discarded still collides with the plain one on the locale.
    ///
    /// The locale and the layout direction are resolved. An unset direction is left to the language, so it is read as the character direction of the locale the state launched in — right to left for `ar` or `he`, left to right otherwise, and left to right when no locale is known. An unset orientation leaves the device as found, which nothing reads before the launch, so it is read from the evidence itself (`OrientationCheck`) — and left unset when the frame is square or empty or there is no tree, so such a state compares as different from one that set an orientation. Appearance is always stated, and an unset Dynamic Type size is the device's own too — but nothing reads the device's size, so two states that differ only there are still compared as different, which refuses more rather than less.
    ///
    /// **A stated orientation is kept as stated, unless `resolvingContradictedOrientation` (SimWalk#217)** — which the collision comparison alone passes. Then a stated orientation whose frame `OrientationCheck` judges the other way is read as the frame's, and one whose frame judges nothing (square, empty, no tree) keeps the stated one. `identicalToBase` does not pass it: a state that asked for landscape and kept a portrait frame is not the same conditions as the plain one, and must not be named identical to it.
    private static func conditions(
        of item: Evidence,
        deviceLocale: String?,
        resolvingContradictedOrientation: Bool = false,
        fixedAppearance: Walkbook.Theme? = nil
    ) -> Walkbook.CaptureState {
        let state = item.state
        let judged = item.tree.flatMap { OrientationCheck.judged($0.frame) }
        let orientation = resolvingContradictedOrientation ? judged ?? state.orientation : state.orientation ?? judged
        return Walkbook.CaptureState(
            theme: fixedAppearance ?? state.theme,
            dynamicTypeSize: state.dynamicTypeSize,
            locale: state.locale ?? deviceLocale,
            arguments: nil,
            environment: nil,
            layoutDirection: state.layoutDirection ?? direction(of: state.locale ?? deviceLocale),
            orientation: orientation
        )
    }

    /// The direction a locale's language lays out in, which is what a state that sets no direction gets; left to right for a locale not known.
    private static func direction(of locale: String?) -> Walkbook.LayoutDirection {
        guard let locale, Locale.Language(identifier: locale).characterDirection == .rightToLeft else { return .ltr }
        return .rtl
    }

    /// Byte-identical states whose launch conditions are one, each named against its base — the state that left the axis to the device and added no launch arguments or environment of its own, or else the one that left the axis to the device, or else the first captured.
    private static func identicalToBase(in evidence: [Evidence], deviceLocale: String?, fixedAppearance: Walkbook.Theme?) -> [Equivalence] {
        identicalGroups(in: evidence).flatMap { group -> [Equivalence] in
            var equivalences: [Equivalence] = []
            var remaining = group
            while let first = remaining.first {
                let launched = conditions(of: first, deviceLocale: deviceLocale, fixedAppearance: fixedAppearance)
                let same = remaining.filter { conditions(of: $0, deviceLocale: deviceLocale, fixedAppearance: fixedAppearance) == launched }
                remaining.removeAll { conditions(of: $0, deviceLocale: deviceLocale, fixedAppearance: fixedAppearance) == launched }
                guard same.count > 1 else { continue }
                let base = same.first { leavesToDevice($0.state) && $0.state.arguments == nil && $0.state.environment == nil }
                    ?? same.first { leavesToDevice($0.state) }
                    ?? same[0]
                equivalences += same.filter { $0.state != base.state }.map { Equivalence(state: $0.state, base: base.state) }
            }
            return equivalences
        }
    }

    /// Whether a state leaves every axis the device resolves to the device: no locale, no layout direction and no orientation of its own.
    private static func leavesToDevice(_ state: Walkbook.CaptureState) -> Bool {
        state.locale == nil && state.layoutDirection == nil && state.orientation == nil
    }

    /// States asked to lay out one way whose tree says they drew the other: every horizontal run judged goes against the stated direction (`LayoutDirectionCheck`).
    ///
    /// A state whose tree holds no run to judge by is not refused and not passed — `Filing.unverified` names it.
    private static func layoutDirectionFinding(for evidence: [Evidence]) -> Finding? {
        let unapplied = evidence.filter { item in
            guard let stated = item.state.layoutDirection, let tree = item.tree else { return false }
            return LayoutDirectionCheck.judged(tree, stated: stated).map { $0 != stated } ?? false
        }
        guard !unapplied.isEmpty else { return nil }
        let described = unapplied.map { item in
            let stated = item.state.layoutDirection == .rtl ? "right to left" : "left to right"
            return "'\(item.stateSlug)' asked to lay out \(stated) and every horizontal run of siblings in its tree runs the other way"
        }
        return Finding(
            reason: "state \(described.joined(separator: "; ")) — a direction the app never saw, so a capture filed under it would be the device's own layout labelled as a mirror",
            refused: unapplied.map(\.state),
            onAppearance: false
        )
    }

    /// States asked for an orientation whose tree's root frame shows the other one (`OrientationCheck`) — a portrait-only app asked for landscape keeps its portrait frame.
    ///
    /// A state whose root frame is square or empty, or that has no tree, is not refused and not passed — `Filing.unverified` names it.
    private static func orientationFinding(for evidence: [Evidence]) -> Finding? {
        let described = evidence.compactMap { item -> (state: Walkbook.CaptureState, clause: String)? in
            guard let stated = item.state.orientation, let tree = item.tree,
                  let refusal = OrientationCheck.refusal(stated: stated, frame: tree.frame) else { return nil }
            return (item.state, "'\(item.stateSlug)' \(refusal)")
        }
        guard !described.isEmpty else { return nil }
        return Finding(
            reason: "state \(described.map(\.clause).joined(separator: "; ")) — an orientation the app never took, so a capture filed under it would be the other orientation's layout labelled as this one",
            refused: described.map(\.state),
            onAppearance: false
        )
    }

    /// The axes each kept state set whose artefacts show nothing to verify them by, in capture order — only states with at least one.
    private static func unverified(in evidence: [Evidence], kept: [Walkbook.CaptureState]) -> [Unverified] {
        evidence.filter { kept.contains($0.state) }.compactMap { item in
            var axes: [String] = []
            if let stated = item.state.layoutDirection, item.tree.flatMap({ LayoutDirectionCheck.judged($0, stated: stated) }) == nil {
                axes.append("layoutDirection")
            }
            if let location = item.state.location, !(item.tree.map { LocationShownCheck.isShown(location, in: $0) } ?? false) {
                axes.append("location")
            }
            if item.state.orientation != nil, item.tree.flatMap({ OrientationCheck.judged($0.frame) }) == nil {
                axes.append("orientation")
            }
            return axes.isEmpty ? nil : Unverified(state: item.state, axes: axes)
        }
    }

    /// `dark` captures that are not darker than the `light` one they were taken beside — and the light states too, unless two independent things say the light captures are light renders.
    ///
    /// **Compared against each other, not against a threshold**, so nothing here has to know what "dark enough" means for an app it has never seen: the claim is only that turning the appearance over must move the ground, and an app that came back at the same brightness both times did not have it turned over. Each dark capture is compared with the *dimmest* light one, so a screen carrying several of each has to have moved every one of them.
    ///
    /// **Which side is refused takes two agreeing reasons to keep one, and any one reason to refuse both.** A dark capture as bright as its light sibling fits two stories: the dark setting was discarded and both are light renders, or the light one was and both are dark ones. Neither signal settles it alone. The device's appearance, read on the host before the walk, says the runner reset the device to `light` before each state — but the reset uses the very setter that is in doubt, so a dark set that took and a reset back that did not would leave a light state drawing dark. A picture's brightness says what the render looks like — but an image-heavy screen's dark render can be brighter than mid-grey, which is what a brightness-only rule got wrong. So the light states are kept only when **both** say so: the device was found `light`, and every light capture measures brighter than mid-grey (`lightRenderFloor`). Brightness here can only add a refusal, never license a keep on its own.
    ///
    /// **A dark capture *brighter* than its own light sibling refuses both sides whatever the device said.** No light device produces that; it is the signature of a light capture taken on a dark device — the failed reset above — and treating "much brighter" like "no darker" kept a 0.1 render as `light` beside a refused 0.93 `dark`. **Its own sibling, not the dimmest light on the screen** (SimWalk#19): the light state it differs from in appearance alone, because a screen whose light states differ in brightness across Dynamic Type or locale would otherwise set a dark capture against a dimmer light one it was never a pair with, and the reason would then assert a dark device on the strength of a comparison that says nothing about one. A dark state with no such sibling is set against the dimmest light, as before, and the reason says which it was.
    ///
    /// What that leaves, stated rather than hidden: a device reported `light` whose failed reset drew a light-looking dark render — an image-heavy screen, reset not holding — passes both tests. The walk reads the device again after the runner's *last* reset and qualifies the answer when that did not hold — but that read sees only the last one, so a reset in the middle of the walk can fail while the last one holds, and the qualification not firing is evidence the resets held, not proof.
    ///
    /// A capture whose bytes are not a decodable image measures nothing and takes no part — this refuses what it can prove, and an unreadable screenshot is a problem the artefact checks own.
    ///
    /// **A comparison is relative, and passing it is not the same as drawing dark (SimWalk#26).** It needs a light capture on the screen — without one, a screen walked only in `dark` or one whose light capture measured nothing filed its dark captures unjudged — and it asks only that dark be darker by the margin, so a light render beside a slightly brighter light one passes it (0.87 against 0.93, the content differing between two launches). `brightDarkFinding` is the absolute test that stands behind it on every screen.
    private static func unappliedAppearanceFinding(for measured: [Measured], deviceAppearance: Walkbook.Theme?) -> Finding? {
        let lights = measured.filter { $0.item.theme == .light }
        guard let dimmest = lights.min(by: { $0.brightness < $1.brightness }) else { return nil }
        let unapplied = measured
            .filter { $0.item.theme == .dark && $0.brightness > dimmest.brightness - darkeningMargin }
            .sorted { $0.brightness > $1.brightness }
        guard let brightest = unapplied.first else { return nil }
        let touched = unapplied.map(\.item.state) + lights.map(\.item.state)
        let slugs = unapplied.map { "'\($0.item.stateSlug)'" }.joined(separator: " and ")
        let figures = unapplied.map { rounded($0.brightness) }.joined(separator: " and ")
        let against = "(mean brightness \(figures) against \(rounded(dimmest.brightness)))"

        // Each dark capture against its own light sibling — the light state it differs from in appearance
        // alone — and against the dimmest light only when the screen has no such state.
        let inverted = unapplied.compactMap { dark -> String? in
            let sibling = lights.first { isSibling($0.item.state, of: dark.item.state) }
            let partner = sibling ?? dimmest
            guard dark.brightness > partner.brightness + darkeningMargin else { return nil }
            let which = sibling == nil ? "the dimmest light capture, since it has no light sibling of its own" : "its light sibling"
            return "state '\(dark.item.stateSlug)' is brighter than '\(partner.item.stateSlug)', \(which) (mean brightness \(rounded(dark.brightness)) against \(rounded(partner.brightness)))"
        }
        if !inverted.isEmpty {
            return Finding(
                reason: "\(inverted.joined(separator: "; ")) — no light device draws that; it is the signature of a light capture taken on a dark device, so neither label can be trusted and every state the comparison touched is refused",
                refused: touched,
                onAppearance: true
            )
        }
        let comparison = "\(unapplied.count == 1 ? "state \(slugs) is" : "states \(slugs) are") no darker than '\(dimmest.item.stateSlug)' \(against) — the device reported the appearance set and drew the same screen"
        guard deviceAppearance == .light else {
            let known = deviceAppearance.map { "was \($0.rawValue) before the walk" } ?? "could not be read before the walk"
            return Finding(
                reason: "\(comparison), and the device's own appearance \(known) — so a light capture may be the device's own render rather than the light state's, and which state it drew cannot be told; every state the comparison touched is refused",
                refused: touched,
                onAppearance: true
            )
        }
        guard dimmest.brightness > lightRenderFloor else {
            return Finding(
                reason: "\(comparison), and although the device was found light, '\(dimmest.item.stateSlug)' measures no brighter than mid-grey — which is what a dark render looks like, and either a reset to light that did not hold would produce one, or a screen dark by design (a dark-branded app, a full-bleed photo, a map, a video); which of the two cannot be told from here, so every state the comparison touched is refused",
                refused: touched,
                onAppearance: true
            )
        }
        let filed = unapplied.count == 1 ? "a capture filed under '\(brightest.item.stateSlug)'" : "a capture filed under any of them"
        return Finding(
            reason: "\(comparison), so \(filed) would be a light render labelled dark; the device was found light and the light captures measure as light renders, so the doubt falls on the dark state",
            refused: unapplied.map(\.item.state),
            onAppearance: true
        )
    }

    /// `dark` captures that measure as light renders, on any screen and any device, that the comparison did not already refuse (SimWalk#26).
    ///
    /// **The comparison above is relative, and it has two holes a light render labelled dark went through.** Relative to nothing it says nothing: a walkbook may walk a screen only in `dark`, and a light capture can fail to decode, and either way the dark captures used to be filed with no check at all. And relative to something it asks only for the margin: a device that reported `dark` and drew light, beside a light capture whose content came out a little brighter — 0.87 against 0.93 — passes it, and the light render was filed labelled dark, outcome `captured`. So an absolute test stands behind it on every screen: a dark capture brighter than mid-grey (`darkRenderCeiling`) is refused, whatever the device was found in — a device found dark draws its dark states light under this trap exactly as one found light does.
    ///
    /// **It can only refuse, never keep** — the guideline for every picture measurement here — **and it costs only the dark states it names.** A screen bright by design in dark mode (a full-bleed photo, a white-branded app) lands above the ceiling with nothing wrong with it, so the reason names both explanations, as the light floor's does: a false refusal in the arguable direction, where the silence it replaces was a false capture. The light captures beside it are not implicated: they either already failed the comparison, and are that finding's to refuse, or they passed it.
    private static func brightDarkFinding(for measured: [Measured], besides refused: [Walkbook.CaptureState]) -> Finding? {
        let bright = measured.filter { $0.item.theme == .dark && $0.brightness > darkRenderCeiling && !refused.contains($0.item.state) }
        guard !bright.isEmpty else { return nil }
        let one = bright.count == 1
        let slugs = bright.map { "'\($0.item.stateSlug)'" }.joined(separator: " and ")
        let figures = bright.map { rounded($0.brightness) }.joined(separator: " and ")
        let verdict = "which is what a light render looks like: either the device reported the appearance set and drew light, or a screen bright by design (a full-bleed photo, a white-branded app); which of the two cannot be told from here, so \(one ? "it is" : "they are") refused"
        guard let dimmest = measured.filter({ $0.item.theme == .light }).min(by: { $0.brightness < $1.brightness }) else {
            return Finding(
                reason: "\(one ? "state \(slugs) has" : "states \(slugs) have") no light capture on this screen to be compared with, and measure\(one ? "s" : "") brighter than mid-grey (mean brightness \(figures)) — \(verdict)",
                refused: bright.map(\.item.state),
                onAppearance: true
            )
        }
        return Finding(
            reason: "\(one ? "state \(slugs) is" : "states \(slugs) are") darker than the light captures beside \(one ? "it" : "them") and still measure\(one ? "s" : "") brighter than mid-grey (mean brightness \(figures), against '\(dimmest.item.stateSlug)' at \(rounded(dimmest.brightness))) — \(verdict)",
            refused: bright.map(\.item.state),
            onAppearance: true
        )
    }

    /// `dark` captures whose screenshot does not decode, so nothing shows them to be dark renders (SimWalk#26, the round-2 review).
    ///
    /// Both appearance tests above measure a picture, and a picture that does not decode takes part in neither — so a dark capture whose bytes did not decode was filed with no check at all, whatever the device drew. **It can only refuse**: nothing about a screenshot that cannot be read shows the state applied. **Not on appearance**: a settle reboots the device, which cannot make a file decode, so this costs no reboot. A state the byte comparison already refused as a collision is not named twice.
    private static func unmeasuredDarkFinding(for evidence: [Evidence], measured: [Measured], besides refused: [Walkbook.CaptureState]) -> Finding? {
        let unmeasured = evidence.filter { item in
            item.theme == .dark && !refused.contains(item.state) && !measured.contains { $0.item == item }
        }
        guard !unmeasured.isEmpty else { return nil }
        let one = unmeasured.count == 1
        let slugs = unmeasured.map { "'\($0.stateSlug)'" }.joined(separator: " and ")
        return Finding(
            reason: "\(one ? "state \(slugs) has a screenshot" : "states \(slugs) have screenshots") that could not be decoded as an image, so nothing shows \(one ? "it is a dark render" : "they are dark renders") — a light render labelled dark cannot be ruled out, so \(one ? "it is" : "they are") refused",
            refused: unmeasured.map(\.state),
            onAppearance: false
        )
    }

    /// How bright a `dark` capture may be before it is refused as a light render: mid-grey.
    ///
    /// The same gap `lightRenderFloor` sits in — light renders measured 0.922–0.965 and dark ones 0.105–0.166 on real screens — read from the other side. Held against every dark capture the relative comparison did not already refuse; alone it can refuse, never keep. An exact 0.5 is not a value the 8-bit measurement returns.
    public static let darkRenderCeiling = 0.5

    /// How much darker a `dark` capture must be than the `light` one beside it, in mean brightness.
    ///
    /// Deliberately far below what a real appearance switch does and far above measurement noise. The measured specimen: a real app's Browse screen reads 0.929 in light, and 0.929 in dark on the build where the appearance is ignored — a difference of zero. A genuine dark render of the same screen puts the ground near black. Nothing between 0 and 0.05 is a plausible honest answer, so the margin is the width of the gap nothing should ever land in rather than a tuned number.
    ///
    /// It is the one place this check could be wrong about an honest walk: a screen that is mostly a photograph or a full-bleed dark chart moves little between appearances. The refusal prints both numbers so a reader can see that is what happened, and this is the trade the honest contract asks for — a false refusal is arguable, a false capture is not.
    public static let darkeningMargin = 0.05

    /// How bright every light capture must be, beside a dark state that did not apply, for the light states to be kept on a device found light: mid-grey.
    ///
    /// **It can only refuse, never keep.** A light device's renders measured 0.922–0.965 and dark ones 0.105–0.166 on real screens, so the floor sits in the middle of that gap. It is consulted only once the comparison has failed and the device was found `light`, as the second of the two agreeing reasons a keep needs; alone it decides nothing. The measurement is 8-bit, so an exact 0.5 is not a value it can return — a capture sits on one side or the other.
    ///
    /// **The gap was measured on two apps, and the core runs on any app** (SimWalk#19). A screen that is dark *by design* in light mode — a dark-branded app, a full-bleed photo, a map, a video — lands under the floor with nothing wrong with it, and is refused alongside the dark state that did not apply. So the refusal names both explanations, a reset that did not hold or a screen dark by design, rather than asserting the first: it is a false refusal in the arguable direction, and a reader who knows the screen can tell which it was.
    public static let lightRenderFloor = 0.5

    /// Whether `light` is the light state `dark` pairs with: the same state in every axis but appearance.
    ///
    /// **Arguments and environment included (SimWalk#44)**, the opposite of `conditions(of:deviceLocale:)`. Used by the inverted comparison only — a dark state judged against being brighter than its own light sibling: whatever an argument does to a screen, it does to both appearances, so that comparison judges a dark state launched under one against the light launched under the same one, never against the plain light, whose picture the argument may have changed. The primary "no darker than the dimmest light" comparison does not call this — it spans every light state on the screen regardless of arguments or environment.
    private static func isSibling(_ light: Walkbook.CaptureState, of dark: Walkbook.CaptureState) -> Bool {
        light.dynamicTypeSize == dark.dynamicTypeSize
            && light.locale == dark.locale
            && light.arguments == dark.arguments
            && light.environment == dark.environment
    }

    /// The captures that share a screenshot, grouped, in the order the states were captured.
    ///
    /// Order is taken from the evidence rather than from a dictionary's, because a refusal that reshuffles itself between identical runs cannot be diffed — the same reason `WalkbookLoader` keeps its distinct values in declaration order.
    private static func identicalGroups(in evidence: [Evidence]) -> [[Evidence]] {
        var groups: [[Evidence]] = []
        for item in evidence {
            if let index = groups.firstIndex(where: { $0[0].screenshot == item.screenshot }) {
                groups[index].append(item)
            } else {
                groups.append([item])
            }
        }
        return groups.filter { $0.count > 1 }
    }

    /// Three decimals, so a refusal a reader is meant to check by eye prints a number and not a float's full expansion.
    private static func rounded(_ luminance: Double) -> String {
        String(format: "%.3f", luminance)
    }
}

public extension StateApplicationCheck {
    /// What one state's capture produced: the state it was taken under, and the screenshot taken under it.
    ///
    /// The screenshot rather than the accessibility tree, and both would work for `theme` — but a tree is blind to any axis that changes only colour, and a screenshot is blind to none of them. Comparing the artefact rather than a projection of it is the rule the locale probe left behind: reading `label` and not `value` made a locale that genuinely applied look like one that had not, and only `cmp` on the raw bytes found the truth.
    ///
    /// The whole state rather than its slug and theme, because whether a collision is one the appearance finding can attribute depends on which axes the colliding states differ in.
    struct Evidence: Equatable, Sendable {
        /// The state the capture was taken under — what a refusal names, and what the runner files or does not.
        public let state: Walkbook.CaptureState
        /// The bytes of the screenshot taken under it.
        public let screenshot: Data
        /// The accessibility tree taken with it — what `layoutDirection` is judged by, and `orientation` by its root frame; `nil` checks no axis that needs one.
        public let tree: AXNode?

        public init(state: Walkbook.CaptureState, screenshot: Data, tree: AXNode? = nil) {
            self.state = state
            self.screenshot = screenshot
            self.tree = tree
        }

        /// The state's on-disk identity, which is what a refusal has to name for an author to find it.
        public var stateSlug: String {
            state.slug
        }

        /// The appearance the state asked for — the one axis whose application is measurable in the picture rather than only comparable between pictures.
        public var theme: Walkbook.Theme {
            state.theme
        }
    }

    /// What a screen's taken states become once the check has had its say.
    struct Filing: Equatable, Sendable {
        /// The verdict to record: `intended` when nothing was refused, `stateNotApplied` naming every finding when something was.
        public let outcome: ScreenOutcome
        /// The states to write and list as captures, in capture order.
        public let kept: [Walkbook.CaptureState]
        /// The states refused, in capture order — recorded on the screen so a reader can tell "refused on this device" from "never reached".
        public let refused: [Walkbook.CaptureState]
        /// The refused states the appearance check refused — a render that did not show the appearance its state asked for — in capture order; the rest of `refused`, if any, went on a collision across another axis.
        ///
        /// **A structured reason, not a reading of the sentence (SimWalk#26).** A walk settles its device — a reboot — for a screen that refused a state on appearance, and for nothing else: a locale or Dynamic Type collision is not cured by a reboot, and a decision keyed on the refusal's wording breaks the first time the sentence is improved.
        public let refusedOnAppearance: [Walkbook.CaptureState]
        /// Kept states whose screenshot is byte-identical to another kept state's because the device was already in the conditions they asked for (SimWalk#18) — applied, and identical to their base, which is recorded on the capture rather than refused.
        public let identicalToBase: [Equivalence]
        /// Kept states that set an axis their artefacts show nothing to verify by — filed, and recorded on the capture as set and unverified rather than passed.
        public let unverified: [Unverified]

        public init(
            outcome: ScreenOutcome,
            kept: [Walkbook.CaptureState],
            refused: [Walkbook.CaptureState],
            refusedOnAppearance: [Walkbook.CaptureState] = [],
            identicalToBase: [Equivalence] = [],
            unverified: [Unverified] = []
        ) {
            self.outcome = outcome
            self.kept = kept
            self.refused = refused
            self.refusedOnAppearance = refusedOnAppearance
            self.identicalToBase = identicalToBase
            self.unverified = unverified
        }

        /// What this filing becomes when states were refused at their launch, before any route (SimWalk#222): each `(state, clause)` is a state whose app drew in the other orientation than it asked for, the clause being `OrientationCheck.refusal`'s.
        ///
        /// **The route is never followed for such a state**, so there is no capture to judge: a portrait-locked app asked for landscape on an iPad would otherwise run the route through a layout it was not written for and fail as `unreachable`. The states join `refused` in walk order and the outcome becomes `stateNotApplied`, folded like any other refusal and leading with what was already found.
        public func refusingAtLaunch(_ launched: [(state: Walkbook.CaptureState, clause: String)]) -> Filing {
            guard !launched.isEmpty else { return self }
            let reason = "state " + launched.map { "'\($0.state.slug)' \($0.clause)" }.joined(separator: "; ") + " — an orientation the app never took, so the route was not followed and nothing was filed under it"
            let combined: ScreenOutcome = if case let .stateNotApplied(existing) = outcome {
                .stateNotApplied(reason: "\(existing). \(reason)")
            } else {
                StateApplicationCheck.outcome(refusing: reason, instead: outcome)
            }
            return Filing(
                outcome: combined,
                kept: kept,
                refused: refused + launched.map(\.state),
                refusedOnAppearance: refusedOnAppearance,
                identicalToBase: identicalToBase,
                unverified: unverified
            )
        }

        /// What this filing becomes when writing what it kept fails: nothing filed, the outcome folded (`ScreenOutcome.foldingWriteFailure(_:)`), and the refused states still named only where the folded outcome is one that refuses states.
        ///
        /// `stateNotApplied` and `unexpectedScreen` are still true of the states they refused — the device discarded them whatever the disk then did — so the list stays beside them. A `captureFailed` names no refusal, and a `refusedStates` list beside one is a record claiming a refusal its outcome does not.
        public func foldingWriteFailure(_ failure: String) -> Filing {
            let outcome = outcome.foldingWriteFailure(failure)
            let stillNamesRefusedStates = switch outcome {
            case .stateNotApplied, .unexpectedScreen: true
            case .captured, .unreachable, .buildMismatch, .captureFailed: false
            }
            return Filing(
                outcome: outcome,
                kept: [],
                refused: stillNamesRefusedStates ? refused : [],
                refusedOnAppearance: stillNamesRefusedStates ? refusedOnAppearance : []
            )
        }
    }

    /// A state whose render is its base's, honestly: the two launched under one set of conditions once the device's own locale is taken into account.
    struct Equivalence: Equatable, Sendable {
        /// The state that asked for what the device already was.
        public let state: Walkbook.CaptureState
        /// The state it is identical to — the one that left that axis to the device.
        public let base: Walkbook.CaptureState

        public init(state: Walkbook.CaptureState, base: Walkbook.CaptureState) {
            self.state = state
            self.base = base
        }
    }

    /// A kept state and the axes it set that its artefacts could not show — named by their walkbook keys.
    struct Unverified: Equatable, Sendable {
        public let state: Walkbook.CaptureState
        public let axes: [String]

        public init(state: Walkbook.CaptureState, axes: [String]) {
            self.state = state
            self.axes = axes
        }
    }

    /// One reason to refuse, and the states it implicates.
    private struct Finding {
        let reason: String
        let refused: [Walkbook.CaptureState]
        /// Whether this is the appearance check's finding — the one kind a settle of the device can cure.
        let onAppearance: Bool
    }

    /// Every finding on a screen, joined: one sentence, the states they implicate, and those the appearance check implicated.
    private struct Joined {
        let reason: String
        let refused: [Walkbook.CaptureState]
        let onAppearance: [Walkbook.CaptureState]
    }

    /// One capture's evidence and the mean brightness its screenshot measured — only for a screenshot that decoded.
    private struct Measured {
        let item: Evidence
        let brightness: Double
    }
}
