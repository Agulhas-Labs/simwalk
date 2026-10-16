//
// Copyright © Agulhas Labs
//

import Foundation

/// Reads a walkbook from disk and answers whether it can be walked (Brief §7.1: the walkbook is a JSON data file, decoded through the format-neutral `Walkbook` model).
///
/// Loading and validating are separate entry points on purpose: a walkbook that arrives already decoded — over the MCP face, or built in a test — must be held to exactly the same rules as one read off disk, and one implementation is the only way that stays true.
public struct WalkbookLoader {
    /// Reads, decodes, and validates a walkbook file, refusing at the first stage that fails.
    public static func load(contentsOf url: URL) throws -> Walkbook {
        let source = url.path
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw WalkbookLoadError.unreadable(source: source, reason: error.localizedDescription)
        }
        return try load(from: data, source: source)
    }

    /// Decodes and validates walkbook bytes that were obtained elsewhere; `source` names them in any refusal.
    ///
    /// **An unknown key no longer aborts before the rest can be listed (round 2).** A `WalkbookProblemSink` rides in the decoder's `userInfo` so `StrictKeyDecoding.checkUnknownKeys` records rather than throws; what it collects is merged with `problems(in:)`'s structural findings into one `.invalid` refusal.
    ///
    /// **Nor does a missing key or a route step naming no step (round 4).** A misspelled *required* key (`{"them":"light"}`) is recorded as unknown, and the key it leaves missing is recorded too (`WalkbookProblem.missingKey`) with a placeholder decoded in its place, so every problem after it is still found — a misspelled case name (`{"tabb":…}`) likewise (`WalkbookProblem.routeStepNotOneStep`). A placeholder is never seen: `problems(in:)` skips only the checks it would otherwise be asked of — one screen's, when the placeholder sits inside `screens[i]`, or the walkbook's own `name`/`appBundleID`/`screens` checks, when it sits at the top level — never the whole walkbook for one placeholder anywhere in it (round 5, finding 1: a single misspelled key in one screen used to hide every other screen's problems, including ones already fully decoded). The refusal names exactly which checks did not run (`WalkbookLoadError`).
    ///
    /// **A decode that still stops (round 3).** A value of the wrong type or one its field does not take (`"settle":"slow"`, `"theme":"purple"`) has no placeholder to stand in, so the decode stops there. When the sink holds anything, the failure joins it as the last problem of the same `.invalid` refusal (`WalkbookProblem.undecodable`); with nothing collected — torn bytes, or one such value alone — it is still `.malformed`. There, nothing runs at all — there is no walkbook to check any part of.
    public static func load(from data: Data, source: String) throws -> Walkbook {
        let sink = WalkbookProblemSink()
        let decoder = JSONDecoder()
        decoder.userInfo[.walkbookProblemSink] = sink
        let walkbook: Walkbook
        do {
            walkbook = try decoder.decode(Walkbook.self, from: data)
        } catch {
            let reason = DecodingReason.sentence(for: error)
            guard sink.problems.isEmpty else {
                throw WalkbookLoadError.invalid(source: source, problems: sink.problems + [.undecodable(reason: reason)])
            }
            throw WalkbookLoadError.malformed(source: source, reason: reason)
        }
        let placeholderScreens = Set(sink.problems.compactMap { $0.placeholderScope?.screenIndex })
        let skippingWalkLevel = sink.problems.contains { $0.placeholderScope == .walkbook }
        let found = sink.problems + problems(in: walkbook, skippingScreensAt: placeholderScreens, skippingWalkLevel: skippingWalkLevel)
        guard found.isEmpty else {
            throw WalkbookLoadError.invalid(source: source, problems: found)
        }
        return walkbook
    }

    /// Throws `WalkbookLoadError.invalid` listing every problem found, or returns having found none.
    public static func validate(_ walkbook: Walkbook, source: String) throws {
        let found = problems(in: walkbook)
        guard found.isEmpty else {
            throw WalkbookLoadError.invalid(source: source, problems: found)
        }
    }

    /// Every reason this walkbook cannot be walked, in reading order — walk-level problems first, then each screen's in the order they are declared.
    public static func problems(in walkbook: Walkbook) -> [WalkbookProblem] {
        problems(in: walkbook, skippingScreensAt: [], skippingWalkLevel: false)
    }

    /// `problems(in:)`, minus the checks a placeholder stands in for (round 5, finding 1): `load` is the only caller that ever passes anything skipped, since a placeholder is a decode-time artefact this type alone knows about — a `Walkbook` built or decoded elsewhere carries no trace of one, so `problems(in:)` and `validate` hold every walkbook to every check, exactly as they always have.
    private static func problems(in walkbook: Walkbook, skippingScreensAt placeholderScreens: Set<Int>, skippingWalkLevel: Bool) -> [WalkbookProblem] {
        var found: [WalkbookProblem] = []
        if !skippingWalkLevel {
            if walkbook.name.trimmed.isEmpty {
                found.append(.blankWalkName)
            }
            if walkbook.appBundleID.trimmed.isEmpty {
                found.append(.blankAppBundleID)
            }
            if walkbook.screens.isEmpty {
                found.append(.noScreens)
            }
            if let oracle = walkbook.oracle, oracle.command.first?.trimmed.isEmpty != false {
                found.append(.emptyOracleCommand)
            }
            found.append(contentsOf: setupProblems(walkbook.setup))
        }
        // A placeholder screen's id is not itself checked as though it were written, but the id it does
        // carry is real whenever the placeholder sits somewhere else in the screen — so collision checking
        // runs over every screen (round 6, finding D): a real duplicate must never hide behind another
        // key's typo, and a placeholder id is blank, which these checks already drop.
        found.append(contentsOf: screenIDCollisionProblems(in: walkbook.screens))
        let realScreens = walkbook.screens.enumerated().filter { !placeholderScreens.contains($0.offset) }
        for (index, screen) in realScreens {
            found.append(contentsOf: problems(in: screen, at: index))
            found.append(contentsOf: grantResetProblems(in: screen, at: index, grants: walkbook.setup?.privacy?.grant ?? []))
            found.append(contentsOf: figureProblems(in: screen, at: index, hasOracle: walkbook.oracle != nil))
        }
        return found
    }

    /// A `setup.privacy` naming a service `simctl privacy` does not know, or both granting and revoking one.
    private static func setupProblems(_ setup: Walkbook.Setup?) -> [WalkbookProblem] {
        let grant = distinct(setup?.privacy?.grant ?? [])
        let revoke = distinct(setup?.privacy?.revoke ?? [])
        let known = PrivacyServiceName.allCases.map(\.rawValue)
        let unknown = distinct(grant + revoke).filter { PrivacyServiceName(rawValue: $0) == nil }.map {
            WalkbookProblem.unknownPrivacyService(value: $0, suggestion: StrictKeyDecoding.nearest(to: $0, among: known))
        }
        return unknown + grant.filter(revoke.contains).map { .privacyGrantedAndRevoked(service: $0) }
    }

    /// A state whose `resetPermissions` names a resource a walk-level `setup.privacy.grant` grants.
    ///
    /// The reset undoes the grant before the state launches. Names that are unknown are left to their own problems.
    private static func grantResetProblems(in screen: Walkbook.Screen, at index: Int, grants: [String]) -> [WalkbookProblem] {
        let granted = distinct(grants).compactMap { service in
            PrivacyServiceName(rawValue: service).flatMap(\.protectedResource).map { (service: service, resource: $0) }
        }
        return screen.states.flatMap { state in
            distinct(state.resetPermissions ?? []).flatMap { name in
                granted.filter { $0.resource.rawValue == name }.map {
                    WalkbookProblem.privacyGrantUndoneByReset(screenID: screen.id, index: index, state: state.slug, resource: name, service: $0.service)
                }
            }
        }
    }

    /// A screen's `figures`, each held to what the oracle and the scraper need of it — and to there being an oracle at all.
    private static func figureProblems(in screen: Walkbook.Screen, at index: Int, hasOracle: Bool) -> [WalkbookProblem] {
        guard let figures = screen.figures else { return [] }
        let id = screen.id.trimmed
        var found: [WalkbookProblem] = []
        if !hasOracle {
            found.append(.figuresWithoutOracle(screenID: id, index: index))
        }
        if figures.isEmpty {
            found.append(.emptyFigures(screenID: id, index: index))
        }
        for (figureIndex, figure) in figures.enumerated() {
            if figure.id.trimmed.isEmpty {
                found.append(.blankFigureField(screenID: id, index: index, figureIndex: figureIndex, key: "id"))
            }
            if figure.element.trimmed.isEmpty {
                found.append(.blankFigureField(screenID: id, index: index, figureIndex: figureIndex, key: "element"))
            }
            if figure.windows.isEmpty || figure.windows.contains(where: \.trimmed.isEmpty) {
                found.append(.emptyFigureWindows(screenID: id, index: index, figureID: figure.id))
            }
            let placeholders = figure.element.components(separatedBy: RouteTarget.placeholder).count - 1
            if placeholders > 1 {
                found.append(.figureElementPlaceholders(screenID: id, index: index, figureID: figure.id, count: placeholders))
            }
        }
        let ids = figures.map(\.id).filter { !$0.trimmed.isEmpty }
        for duplicate in distinct(ids) where ids.count(where: { $0 == duplicate }) > 1 {
            found.append(.duplicateFigureID(screenID: id, index: index, figureID: duplicate))
        }
        return found
    }

    private static func problems(in screen: Walkbook.Screen, at index: Int) -> [WalkbookProblem] {
        var found: [WalkbookProblem] = []
        let id = screen.id.trimmed
        if id.isEmpty {
            found.append(.blankScreenID(index: index))
        }
        if screen.route.isEmpty {
            found.append(.emptyRoute(screenID: id, index: index))
        }
        for (stepIndex, step) in screen.route.enumerated() {
            if step.label?.trimmed.isEmpty == true {
                found.append(.blankRouteStepLabel(screenID: id, index: index, stepIndex: stepIndex))
            }
            // Empty text is not "clear the field" — it is a step that taps, types nothing, and reports
            // having driven the field, which is the silent-discard shape every other axis is refused for.
            if case let .type(_, text) = step, text.isEmpty {
                found.append(.blankTypedText(screenID: id, index: index, stepIndex: stepIndex))
            }
            // A tab is looked up by its exact label as it reads — `tap`, `scrollTo` and `type` fall
            // through to the pattern tier where `{n}` stands for a number, a tab step never does — so a
            // tab step carrying one could never land.
            if case let .tab(label) = step, label.contains(tabStepPlaceholder) {
                found.append(.placeholderInTabStep(screenID: id, index: index, stepIndex: stepIndex, label: label))
            }
            // Neither does a system sheet's control, which is looked up by its label or identifier as it
            // reads; and the owner is the runner's record of where it found one, never an author's to claim.
            if case let .systemTap(label, atLaunch, owner) = step {
                if label.contains(tabStepPlaceholder) {
                    found.append(.placeholderInSystemTapStep(screenID: id, index: index, stepIndex: stepIndex, label: label))
                }
                if owner != nil {
                    found.append(.ownerInSystemTapStep(screenID: id, index: index, stepIndex: stepIndex))
                }
                // The declaration describes the launch, and only the first step is taken on the launch's screen.
                if atLaunch, stepIndex > 0 {
                    found.append(.atLaunchAfterFirstStep(screenID: id, index: index, stepIndex: stepIndex))
                }
            }
            if case let .openURL(url) = step, !Self.isOpenableURL(url) {
                found.append(.unopenableURL(screenID: id, index: index, stepIndex: stepIndex, url: url))
            }
            if case let .tapPoint(label, point) = step {
                found.append(contentsOf: tapPointProblems(label: label, point: point, screenID: id, index: index, stepIndex: stepIndex))
            }
        }
        if screen.states.isEmpty {
            found.append(.noCaptureStates(screenID: id, index: index))
        }
        // Same refusal `--settle 0` gets at the command line, for the same reason: a quiet period the
        // runner would fall back from is an input that is neither honoured nor rejected, and the walk
        // would run at the default with the entry still claiming its own.
        if let settle = screen.settle, settle <= 0 {
            found.append(.nonPositiveSettle(screenID: id, index: index, value: settle))
        }
        if let budgets = screen.budgets {
            if budgets.stated.isEmpty {
                found.append(.emptyBudgets(screenID: id, index: index))
            }
            for (key, value) in budgets.stated where value < 0 {
                found.append(.negativeBudget(screenID: id, index: index, key: key, value: value))
            }
        }
        if let measure = screen.measure, !Walkbook.Measure.allowedIterations.contains(measure.iterations) {
            found.append(.measureIterationsOutOfRange(screenID: id, index: index, value: measure.iterations))
        }
        if let expect = screen.expect {
            if expect.trimmed.isEmpty {
                found.append(.blankExpect(screenID: id, index: index))
            } else if expect != expect.trimmed {
                found.append(.paddedExpect(screenID: id, index: index, value: expect))
            } else if !ScreenIdentifierRule.isUsable(expect) {
                found.append(.mangledExpect(screenID: id, index: index, value: expect))
            }
        }
        if let expectMenu = screen.expectMenu {
            if expectMenu.isEmpty {
                found.append(.emptyExpectMenu(screenID: id, index: index))
            }
            for (position, label) in expectMenu.enumerated() {
                if label.trimmed.isEmpty {
                    found.append(.blankExpectMenuLabel(screenID: id, index: index, position: position))
                } else if label != label.trimmed {
                    found.append(.paddedExpectMenuLabel(screenID: id, index: index, position: position, value: label))
                }
            }
        }
        found.append(contentsOf: duplicateStateProblems(in: screen, screenID: id, index: index))
        found.append(contentsOf: unhonouredStateProblems(in: screen, screenID: id, index: index))
        found.append(contentsOf: launchConditionProblems(in: screen, screenID: id, index: index))
        return found
    }

    /// Whether an `openURL` step's URL can be opened at all: one `URL(string:)` parses and that names a scheme.
    ///
    /// Without a scheme there is no app or system handler to route it to, and the step would report a landing it never attempted.
    private static func isOpenableURL(_ text: String) -> Bool {
        guard let scheme = URL(string: text)?.scheme else { return false }
        return !scheme.isEmpty
    }

    /// A `tapPoint` step whose point could never be tapped as written (SimWalk#29).
    ///
    /// **Two numbers, and within what they are measured against.** A point within an element is two fractions of its frame, so a coordinate outside 0…1 lands on something else — whatever is drawn beside the element — while the step reports having tapped it. A point on the screen is in device points, which are never negative; whether one fits the screen depends on a device `validate` is not told about, so that half is checked when the walk runs, and a point beyond the screen is refused there rather than tapped. Each coordinate must *satisfy* its range rather than merely not break it, so a NaN a walkbook built in code could carry is refused rather than waved through by every comparison failing.
    private static func tapPointProblems(label: String?, point: [Double], screenID: String, index: Int, stepIndex: Int) -> [WalkbookProblem] {
        guard point.count == 2 else {
            return [.malformedTapPoint(screenID: screenID, index: index, stepIndex: stepIndex, count: point.count)]
        }
        if let label {
            return point.allSatisfy { (0 ... 1).contains($0) }
                ? []
                : [.tapPointOutsideElement(screenID: screenID, index: index, stepIndex: stepIndex, label: label, point: point)]
        }
        guard point.allSatisfy({ $0 >= 0 }) else {
            return [.tapPointOffScreen(screenID: screenID, index: index, stepIndex: stepIndex, point: point)]
        }
        // Written without a `label`, `at` is a screen point in device points — but one whose coordinates
        // are both at most 1 is a fraction of an element's frame in every worked example this format has,
        // never a plausible screen point on a real device. `validate` cannot tell "meant to be absolute"
        // from "the label was dropped", so it refuses either way and names the likelier of the two rather
        // than silently tapping the status bar (SimWalk#29 review, item 2).
        return point.allSatisfy { $0 <= 1 }
            ? [.tapPointFractionalWithoutLabel(screenID: screenID, index: index, stepIndex: stepIndex, point: point)]
            : []
    }

    /// State axes naming a value the simulator would discard without saying so.
    ///
    /// Both axes are typed `String` and passed to a launch argument verbatim, so an unrecognised value is not rejected by anything downstream — it is dropped, and the capture is the device default filed under a slug asserting the state. That is the one failure a capture bundle cannot describe after the fact, which is why it is caught here, at the boundary where the value is still attached to the walkbook that wrote it.
    ///
    /// Reported once per distinct offending value, not once per state carrying it: a screen capturing `accessibility3` under three themes has made one mistake in one place, and three identical lines describe it no better than one while burying the screen's other problems.
    private static func unhonouredStateProblems(in screen: Walkbook.Screen, screenID: String, index: Int) -> [WalkbookProblem] {
        var found: [WalkbookProblem] = []
        for size in distinct(screen.states.compactMap(\.dynamicTypeSize)) where !ContentSizeCategoryName.isValid(size) {
            found.append(.unknownDynamicTypeSize(
                screenID: screenID,
                index: index,
                value: size,
                suggestion: ContentSizeCategoryName.suggestion(for: size)
            ))
        }
        for locale in distinct(screen.states.compactMap(\.locale)) where !LocaleIdentifierName.isValid(locale) {
            found.append(.unknownLocale(
                screenID: screenID,
                index: index,
                value: locale,
                suggestion: LocaleIdentifierName.suggestion(for: locale)
            ))
        }
        for name in distinct(screen.states.flatMap { $0.resetPermissions ?? [] }) where ProtectedResourceName(rawValue: name) == nil {
            found.append(.unknownPermission(
                screenID: screenID,
                index: index,
                value: name,
                suggestion: StrictKeyDecoding.nearest(to: name, among: ProtectedResourceName.allCases.map(\.rawValue))
            ))
        }
        for location in screen.states.compactMap(\.location)
            where !(-90 ... 90).contains(location.latitude) || !(-180 ... 180).contains(location.longitude)
        {
            found.append(.locationOutOfRange(screenID: screenID, index: index, latitude: location.latitude, longitude: location.longitude))
        }
        return found
    }

    /// State `arguments`, `environment` and `resetPermissions` that state nothing, or name nothing (SimWalk#44).
    ///
    /// **Non-empty is the whole of the check**, because it is the only thing that can be known here: what an argument means is the app's, and SimWalk cannot say whether one reaches the screen. An empty list or object is refused rather than read as absent, as a blank `expect` is — it slugs differently from the plain state while launching exactly as it does. Reported once per screen and kind, not once per state, for the reason `unhonouredStateProblems` gives.
    private static func launchConditionProblems(in screen: Walkbook.Screen, screenID: String, index: Int) -> [WalkbookProblem] {
        var found: [WalkbookProblem] = []
        if screen.states.contains(where: { $0.arguments?.isEmpty == true }) {
            found.append(.emptyLaunchCondition(screenID: screenID, index: index, key: "arguments"))
        }
        if screen.states.contains(where: { $0.arguments?.contains("") == true }) {
            found.append(.blankLaunchCondition(screenID: screenID, index: index, key: "arguments"))
        }
        if screen.states.contains(where: { $0.environment?.isEmpty == true }) {
            found.append(.emptyLaunchCondition(screenID: screenID, index: index, key: "environment"))
        }
        if screen.states.contains(where: { $0.environment?.keys.contains("") == true }) {
            found.append(.blankLaunchCondition(screenID: screenID, index: index, key: "environment"))
        }
        if screen.states.contains(where: { $0.resetPermissions?.isEmpty == true }) {
            found.append(.emptyLaunchCondition(screenID: screenID, index: index, key: "resetPermissions"))
        }
        return found
    }

    /// The placeholder a route step writes for a number that changes with the data (SimWalk#13).
    ///
    /// Spelled here because `RouteTarget.placeholder`, its one spelling, is not in this tree yet; that constant replaces this literal when it is.
    private static var tabStepPlaceholder: String {
        "{n}"
    }

    /// The values in the order they were declared, each kept once — `Set` would report them in a different order on every run, and a refusal that reshuffles itself between identical runs cannot be diffed.
    private static func distinct(_ values: [String]) -> [String] {
        var seen: Set<String> = []
        return values.filter { seen.insert($0).inserted }
    }

    /// Screens that would share a bundle directory, reported by *slug* rather than by id.
    ///
    /// Grouping on the id alone would let `Today` and `today` both validate and then collide on a case-insensitive filesystem, silently overwriting one screen's captures with another's. Identical ids stay their own problem, since "you wrote this twice" and "these two reduce to one directory" are different mistakes with different fixes. Blank ids are dropped rather than trimmed — they have their own problem, and trimming an id the runner will not trim asks about a different id than the one that reaches disk.
    private static func screenIDCollisionProblems(in screens: [Walkbook.Screen]) -> [WalkbookProblem] {
        ScreenIDCollision.all(among: screens.map(\.id).filter { !$0.trimmed.isEmpty }).map { collision in
            switch collision {
            case let .duplicate(id, occurrences):
                .duplicateScreenID(id: id, occurrences: occurrences)
            case let .colliding(slug, ids):
                .collidingScreenIDs(slug: slug, ids: ids)
            }
        }
    }

    private static func duplicateStateProblems(in screen: Walkbook.Screen, screenID: String, index: Int) -> [WalkbookProblem] {
        SlugGroup.colliding(SlugGroup.grouping(screen.states.map(\.slug))).map { group in
            .duplicateCaptureState(screenID: screenID, index: index, slug: group.slug)
        }
    }
}

private extension Walkbook.RouteStep {
    /// The element label a step targets, or `nil` for steps that name no element.
    var label: String? {
        switch self {
        case let .tab(label), let .tap(label), let .scrollTo(label):
            label
        case let .type(label, _):
            label
        case let .tapPoint(label, _):
            label
        case let .systemTap(label, _, _):
            label
        case .openURL, .back:
            nil
        }
    }
}
