//
// Copyright © Agulhas Labs
//

import Foundation

/// One specific reason a walkbook cannot be executed as written.
///
/// Every case carries the subject it is about — a screen id, a step index, a duplicated slug — because a validator that says "invalid" has told the author nothing they did not already know. Screen-scoped cases carry the screen's *index* alongside its id, so a screen whose id is blank is still identified by where it sits rather than reported against `''`. The descriptions are the whole output of `simwalk validate`, so they read as instructions, not as diagnostics.
public enum WalkbookProblem: Equatable, Sendable, CustomStringConvertible {
    /// The walk has no name, so its capture bundles would be unattributable.
    case blankWalkName
    /// The walk names no app, so the runner has nothing to launch.
    case blankAppBundleID
    /// The walk visits nothing.
    case noScreens
    /// A screen carries no id, so its captures could not be keyed; the payload is its position in the list.
    case blankScreenID(index: Int)
    /// Two or more screens share an id, so their captures would collide inside one bundle.
    case duplicateScreenID(id: String, occurrences: Int)
    /// Screens with different ids that reduce to the same on-disk slug — distinct to a reader, one directory to the filesystem.
    case collidingScreenIDs(slug: String, ids: [String])
    /// A screen states no route, so where it is reached from is whatever the previous screen left behind.
    case emptyRoute(screenID: String, index: Int)
    /// A route step names an element by an empty label, which matches nothing and can never be attempted honestly.
    case blankRouteStepLabel(screenID: String, index: Int, stepIndex: Int)
    /// A `type` step names no text, so it would tap a field, type nothing, and report having driven it.
    case blankTypedText(screenID: String, index: Int, stepIndex: Int)
    /// A `tapPoint` step's `at` is not two numbers — an x and a y — so there is no point to tap (SimWalk#29).
    case malformedTapPoint(screenID: String, index: Int, stepIndex: Int, count: Int)
    /// A `tapPoint` step names an element and a point outside its frame — a coordinate outside 0…1 — so the touch would land on whatever is drawn beside it.
    case tapPointOutsideElement(screenID: String, index: Int, stepIndex: Int, label: String, point: [Double])
    /// A `tapPoint` step names a screen point with a negative coordinate, which no screen has; a point beyond the screen's far edges is refused when the walk runs, where the device is known.
    case tapPointOffScreen(screenID: String, index: Int, stepIndex: Int, point: [Double])
    /// A `tapPoint` step names no label and a screen point with both coordinates at most 1 — every worked example of the fractional form reads that shape, so it is far more likely a `label` was dropped than that the point was ever meant to land a device point from the screen's own corner (SimWalk#29 review, item 2).
    case tapPointFractionalWithoutLabel(screenID: String, index: Int, stepIndex: Int, point: [Double])
    /// A screen requests no capture states, so what the runner would capture is the device's ambient appearance.
    case noCaptureStates(screenID: String, index: Int)
    /// A screen requests the same state twice, so the second capture would overwrite the first.
    case duplicateCaptureState(screenID: String, index: Int, slug: String)
    /// A capture state names a Dynamic Type size the simulator does not honour, which it would discard in silence — capturing the device default and filing it under a slug naming the size.
    case unknownDynamicTypeSize(screenID: String, index: Int, value: String, suggestion: String?)
    /// A capture state names a locale the simulator does not honour, discarded in silence exactly as an unknown Dynamic Type size is.
    case unknownLocale(screenID: String, index: Int, value: String, suggestion: String?)
    /// A capture state writes `arguments` or `resetPermissions` as an empty list, or `environment` as an empty object — `key` names which — which states nothing and reads as though it does (SimWalk#44).
    case emptyLaunchCondition(screenID: String, index: Int, key: String)
    /// A capture state writes an empty string as one of its `arguments` or as an `environment` key — `key` names which — so the app would be launched with something nobody meant (SimWalk#44).
    case blankLaunchCondition(screenID: String, index: Int, key: String)
    /// A capture state's `environment` names `SIMWALK_ANIMATIONS`, which would make the walk's one animation state two (SimWalk#154).
    case animationsInStateEnvironment(screenID: String, index: Int)
    /// A capture state's `resetPermissions` names a resource `ProtectedResourceName` does not, so there is nothing the runner could reset for it.
    case unknownPermission(screenID: String, index: Int, value: String, suggestion: String?)
    /// A capture state's `location` is not a place: a latitude outside -90…90 or a longitude outside -180…180.
    case locationOutOfRange(screenID: String, index: Int, latitude: Double, longitude: Double)
    /// A screen states a quiet period the runner would discard, so it would capture at the walk's default under an entry claiming otherwise.
    case nonPositiveSettle(screenID: String, index: Int, value: Int)
    /// A screen states `budgets` as an empty object, which checks nothing and reads as though it does.
    case emptyBudgets(screenID: String, index: Int)
    /// A screen asks `measure` for an iteration count outside 1–10: none is not a measurement, and each iteration costs a cold launch.
    case measureIterationsOutOfRange(screenID: String, index: Int, value: Int)
    /// A screen states a negative budget, which no measured motion can meet.
    case negativeBudget(screenID: String, index: Int, key: String, value: Int)
    /// A screen states `expect` as an empty string, which checks nothing and reads as though it does.
    case blankExpect(screenID: String, index: Int)
    /// A screen states `expect` padded with whitespace, which an exact identifier match can never satisfy — no captured screen identifier will carry the leading or trailing space.
    case paddedExpect(screenID: String, index: Int, value: String)
    /// A screen states `expectMenu` as an empty list, which checks nothing and reads as though it does (SimWalk#111).
    case emptyExpectMenu(screenID: String, index: Int)
    /// A screen's `expectMenu` holds a blank label, which no menu item can carry.
    case blankExpectMenuLabel(screenID: String, index: Int, position: Int)
    /// A screen's `expectMenu` holds a label padded with whitespace, which an exact match can never satisfy.
    case paddedExpectMenuLabel(screenID: String, index: Int, position: Int, value: String)
    /// A key inside the walkbook, a screen, a state or a route step that none of this format recognises — `path` locates it (`screens[0].states[1]`, empty at the walkbook's own top level) and `key` names what was found there.
    ///
    /// Reported beside every other problem rather than the decode failure it used to be aborting the whole load before they could be listed (SimWalk#10, round 2) — see `WalkbookProblemSink`.
    case unknownKey(path: String, key: String, suggestion: String?)
    /// A key this format does recognise, written in a container that does not take it — `expect` on a route step or a state, where it can only mean the screen's own.
    case misplacedKey(path: String, key: String, belongsOn: String)
    /// A screen states `expect` as a Swift-mangled runtime class name (`_Tt…`), which names a framework type that sits on every screen — `ScreenIdentifierRule` never counts one, so the check could never pass.
    case mangledExpect(screenID: String, index: Int, value: String)
    /// A key a container requires is not there — `path` locates the container, `key` names what it needed (round 4).
    ///
    /// Recorded rather than thrown while `WalkbookLoader` decodes, and the decode carries on with a placeholder so every problem after it is listed too: a misspelled required key (`them` for `theme`) used to stop the listing at the first one. The placeholder never escapes — `load` refuses whenever it has recorded anything — and only the checks it stands in for are skipped: one screen's, or the walkbook's own top-level fields (``placeholderScope``), never the whole walkbook for a placeholder anywhere in it.
    case missingKey(path: String, key: String)
    /// A route step's object names no step, or more than one — `names` are the step names it does carry, in the order the format lists them (round 4).
    ///
    /// Recorded and replaced by a placeholder exactly as ``missingKey(path:key:)`` is, so a misspelled case name (`tabb`) no longer stops the listing.
    case routeStepNotOneStep(path: String, names: [String])
    /// The walkbook stopped decoding here — a value of the wrong type, or one its field does not take — so there is no walkbook for the remaining checks to be asked of.
    ///
    /// Listed last, after every problem collected before the decode stopped, so a refusal that has both says both (round 3). A missing key or a route step naming no step no longer ends up here: those are recorded and decoded past (round 4).
    case undecodable(reason: String)
    /// `validate --device`: the walkbook asks for what a device target cannot do (SimWalk#116).
    ///
    /// Carries the line ``DeviceTargetSupport`` gave, which a device walk's refusal quotes too, so the two are one list.
    case unsupportedOnDevice(String)
    /// `validate` refuses a `tab` step whose label carries the `{n}` placeholder: a tab is looked up by its exact label as it reads, never through the pattern tier `tap`, `scrollTo` and `type` get, so the step could never land.
    case placeholderInTabStep(screenID: String, index: Int, stepIndex: Int, label: String)
    /// `validate` refuses a `systemTap` step whose label carries `{n}`: a system sheet's control is looked up by its label or identifier as it reads, never through the pattern tier, so the step could never land (SimWalk#28 review).
    case placeholderInSystemTapStep(screenID: String, index: Int, stepIndex: Int, label: String)
    /// `validate` refuses a `systemTap` step that writes its `owner`: that is where the runner records which tree it found the control in, so a walkbook writing one would be a claim nothing checked (SimWalk#28 review).
    case ownerInSystemTapStep(screenID: String, index: Int, stepIndex: Int)
    /// `validate` refuses `atLaunch` on a `systemTap` that is not its route's first step: the declaration says the launch raised the sheet, and only the first step is taken on the launch's screen (SimWalk#46).
    case atLaunchAfterFirstStep(screenID: String, index: Int, stepIndex: Int)
    /// `validate` refuses an `openURL` step whose URL does not parse or names no scheme, so no app or system handler could be handed it.
    case unopenableURL(screenID: String, index: Int, stepIndex: Int, url: String)
    /// `validate` refuses an `oracle` whose command names no executable: every figure would be answered "oracle failed" by a walk that could have been refused before it ran.
    case emptyOracleCommand
    /// `validate` refuses a `setup.privacy` service `simctl privacy` does not know.
    case unknownPrivacyService(value: String, suggestion: String?)
    /// `validate` refuses a service `setup.privacy` both grants and revokes.
    case privacyGrantedAndRevoked(service: String)
    /// `validate` refuses a state whose `resetPermissions` names a resource a walk-level `setup.privacy.grant` grants: the reset puts it back to not-yet-asked before the state's launch, undoing the grant.
    case privacyGrantUndoneByReset(screenID: String, index: Int, state: String, resource: String, service: String)
    /// `validate` refuses `figures` on a walkbook with no `oracle`: nothing could compute what the figures are checked against.
    case figuresWithoutOracle(screenID: String, index: Int)
    /// `validate` refuses `figures: []`, which checks nothing exactly as its absence does.
    case emptyFigures(screenID: String, index: Int)
    /// `validate` refuses a figure with a blank `id` or `element`: the oracle could not be told which figure, or nothing on screen could carry it.
    case blankFigureField(screenID: String, index: Int, figureIndex: Int, key: String)
    /// `validate` refuses a figure with no windows, or a blank one: the oracle would be asked for nothing, and every answer would be `matches none` over an empty list.
    case emptyFigureWindows(screenID: String, index: Int, figureID: String)
    /// `validate` refuses two figures with one id on one screen: their answers could not be told apart.
    case duplicateFigureID(screenID: String, index: Int, figureID: String)
    /// `validate` refuses an `element` naming `{n}` more than once: a figure is one number.
    case figureElementPlaceholders(screenID: String, index: Int, figureID: String, count: Int)

    public var description: String {
        switch self {
        case .blankWalkName:
            "walk name is blank — a capture bundle's manifest is attributed by it"
        case .blankAppBundleID:
            "appBundleID is blank — the runner has no app to launch"
        case .noScreens:
            "screens is empty — a walk that visits nothing captures nothing"
        case let .blankScreenID(index):
            "screen at index \(index) has a blank id — captures, diffs and oracle answers are keyed by it"
        case let .duplicateScreenID(id, occurrences):
            "screen id '\(id)' is used \(occurrences) times — captures would collide under one bundle key"
        case let .collidingScreenIDs(slug, ids):
            "screen ids \(ids.map { "'\($0)'" }.joined(separator: ", ")) all file under '\(slug)' — they are one directory on disk, so their captures would overwrite each other"
        case let .emptyRoute(screenID, index):
            "\(Self.subject(screenID, index)) has an empty route — a walk executes a plan, so every screen states how it is reached from launch"
        case let .blankRouteStepLabel(screenID, index, stepIndex):
            "\(Self.subject(screenID, index)) route step \(stepIndex) has a blank label — it matches no element, so UNREACHABLE could not even name what it tried"
        case let .blankTypedText(screenID, index, stepIndex):
            "\(Self.subject(screenID, index)) route step \(stepIndex) types an empty string — it would tap the field, type nothing, and report the step as having landed"
        case let .malformedTapPoint(screenID, index, stepIndex, count):
            "\(Self.subject(screenID, index)) route step \(stepIndex) taps at \(count) number\(count == 1 ? "" : "s") — `at` is a point, written as two: [x, y]"
        case let .tapPointOutsideElement(screenID, index, stepIndex, label, point):
            "\(Self.subject(screenID, index)) route step \(stepIndex) taps '\(label)' at \(Walkbook.RouteStep.rendered(point)), outside its frame — a point within an element is two fractions of it from 0 to 1, and this one would land on whatever is drawn beside it"
        case let .tapPointOffScreen(screenID, index, stepIndex, point):
            "\(Self.subject(screenID, index)) route step \(stepIndex) taps the screen at \(Walkbook.RouteStep.rendered(point)) — a screen point is in device points and never negative; whether it fits the device's screen is checked when the walk runs, since validate is not told the device"
        case let .tapPointFractionalWithoutLabel(screenID, index, stepIndex, point):
            "\(Self.subject(screenID, index)) route step \(stepIndex) taps the screen at \(Walkbook.RouteStep.rendered(point)), with no `label` — both coordinates are at most 1, which reads as a fraction of an element's frame rather than a point on any real device's screen; name the element the fraction is measured against, or give a screen point that is actually one"
        case let .noCaptureStates(screenID, index):
            "\(Self.subject(screenID, index)) requests no states — capturing the device's ambient appearance is not something a manifest can attest to; state at least one theme"
        case let .duplicateCaptureState(screenID, index, slug):
            "\(Self.subject(screenID, index)) requests state '\(slug)' twice — the second capture would overwrite the first"
        case let .unknownDynamicTypeSize(screenID, index, value, suggestion):
            "\(Self.subject(screenID, index)) requests dynamicTypeSize '\(value)', which is not a UIContentSizeCategory name — the simulator discards it silently and captures the device default, so the state would be a lie\(Self.meantInstead(suggestion))"
        case let .unknownLocale(screenID, index, value, suggestion):
            "\(Self.subject(screenID, index)) requests locale '\(value)', which is not an available locale identifier — the simulator discards it silently and captures the device default, so the state would be a lie\(Self.meantInstead(suggestion))"
        case let .emptyLaunchCondition(screenID, index, key):
            "\(Self.subject(screenID, index)) requests \(key) \(key == "environment" ? "{}" : "[]") — an empty \(key == "environment" ? "object" : "list") \(key == "resetPermissions" ? "resets nothing" : "launches the app") exactly as its absence does, so omit the key"
        case let .blankLaunchCondition(screenID, index, key):
            "\(Self.subject(screenID, index)) requests \(key == "arguments" ? "an empty string among its arguments" : "an environment variable with an empty name") — the app would be launched with something that names nothing; remove it"
        case let .animationsInStateEnvironment(screenID, index):
            "\(Self.subject(screenID, index)): \(AnimationsOptIn.stateEnvironmentRefusal)"
        case let .unknownPermission(screenID, index, value, suggestion):
            "\(Self.subject(screenID, index)) requests resetPermissions '\(value)', which is not a protected resource this platform can reset — one of \(ProtectedResourceName.allCases.map(\.rawValue).joined(separator: ", "))\(Self.meantInstead(suggestion))"
        case let .locationOutOfRange(screenID, index, latitude, longitude):
            "\(Self.subject(screenID, index)) requests location \(latitude), \(longitude) — a latitude is -90…90 and a longitude -180…180, so the simulator could not be put there"
        case let .nonPositiveSettle(screenID, index, value):
            "\(Self.subject(screenID, index)) requests settle \(value)ms — a quiet period is milliseconds greater than zero, and this one would be discarded and the screen captured at the walk's default instead"
        case let .emptyBudgets(screenID, index):
            "\(Self.subject(screenID, index)) states budgets with none of settleMs, layoutShifts, launchMs, transitionHitches, cpuMs or memoryPeakMB — an empty budget holds the screen to nothing; remove it or state one"
        case let .measureIterationsOutOfRange(screenID, index, value):
            "\(Self.subject(screenID, index)) asks measure for \(value) iterations — \(Walkbook.Measure.allowedIterations.lowerBound) to \(Walkbook.Measure.allowedIterations.upperBound) (\(Walkbook.Measure.defaultIterations) by default), as a run with none measures nothing and each iteration is a cold launch of the app"
        case let .negativeBudget(screenID, index, key, value):
            "\(Self.subject(screenID, index)) states budgets.\(key) \(value) — a budget is zero or more, and no capture can come in under a negative one"
        case let .blankExpect(screenID, index):
            "\(Self.subject(screenID, index)) states expect as an empty string — a check against nothing passes everything, which is what an absent `expect` already says honestly"
        case let .paddedExpect(screenID, index, value):
            "\(Self.subject(screenID, index)) states expect as '\(value)', padded with whitespace — no captured screen identifier will ever carry it, so an exact match can never pass"
        case let .emptyExpectMenu(screenID, index):
            "\(Self.subject(screenID, index)) states expectMenu as an empty list — a check against no labels passes everything, which is what an absent `expectMenu` already says honestly"
        case let .blankExpectMenuLabel(screenID, index, position):
            "\(Self.subject(screenID, index)) states expectMenu label \(position + 1) as an empty string — no menu item carries it, so the check can never pass"
        case let .paddedExpectMenuLabel(screenID, index, position, value):
            "\(Self.subject(screenID, index)) states expectMenu label \(position + 1) as '\(value)', padded with whitespace — no menu item's label will ever carry it, so an exact match can never pass"
        case let .unknownKey(path, key, suggestion):
            "unknown key '\(key)'\(path.isEmpty ? "" : " at \(path)")\(Self.meantInstead(suggestion))"
        case let .misplacedKey(path, key, belongsOn):
            "key '\(key)'\(path.isEmpty ? " at the top level" : " at \(path)") belongs on \(belongsOn)"
        case let .mangledExpect(screenID, index, value):
            "\(Self.subject(screenID, index)) states expect as '\(value)', a Swift-mangled class name — it names a framework type on every screen, which is never counted as a screen's identifier, so the check could never pass"
        case let .missingKey(path, key):
            "missing key '\(key)'\(path.isEmpty ? " at the top level" : " at \(path)")"
        case let .routeStepNotOneStep(path, names):
            names.isEmpty
                ? "route step at \(path) names no step — a step is exactly one of \(Walkbook.RouteStep.caseNames.joined(separator: ", "))"
                : "route step at \(path) names \(names.map { "'\($0)'" }.joined(separator: " and ")) — a step is exactly one of \(Walkbook.RouteStep.caseNames.joined(separator: ", "))"
        case let .unsupportedOnDevice(line):
            line
        case let .undecodable(reason):
            "the walkbook stops decoding: \(reason). Nothing after that point was read"
        case let .placeholderInTabStep(screenID, index, stepIndex, label):
            "\(Self.subject(screenID, index)) route step \(stepIndex) names tab '\(label)' with {n} — a tab is looked up by its name as it reads, so the placeholder never matches and the step is UNREACHABLE; name the tab as it reads"
        case let .placeholderInSystemTapStep(screenID, index, stepIndex, label):
            "\(Self.subject(screenID, index)) route step \(stepIndex) names systemTap '\(label)' with {n} — a system sheet's control is looked up by its label or identifier as it reads, so the placeholder never matches and the step is UNREACHABLE; name the control as it reads"
        case let .ownerInSystemTapStep(screenID, index, stepIndex):
            "\(Self.subject(screenID, index)) route step \(stepIndex) writes a systemTap's owner — the runner records which tree it found the control in; a walkbook names only the label"
        case let .atLaunchAfterFirstStep(screenID, index, stepIndex):
            "\(Self.subject(screenID, index)) route step \(stepIndex) declares a systemTap atLaunch — the declaration says the launch itself raised the sheet, so it can only be a route's first step (step 0); remove it here"
        case let .unopenableURL(screenID, index, stepIndex, url):
            "\(Self.subject(screenID, index)) route step \(stepIndex) opens '\(url)', which is not a URL with a scheme — there is nothing to hand it to, so the step could never land; write it as `scheme://path`"
        case let .unknownPrivacyService(value, suggestion):
            "setup.privacy names '\(value)', which is not a service `simctl privacy` grants or revokes — one of \(PrivacyServiceName.allCases.map(\.rawValue).joined(separator: ", "))\(Self.meantInstead(suggestion)); HealthKit is not one of them, so a Health sheet stays a route's systemTap"
        case let .privacyGrantedAndRevoked(service):
            "setup.privacy both grants and revokes '\(service)' — the device can end the setup in only one of them, so name it once"
        case let .privacyGrantUndoneByReset(screenID, index, state, resource, service):
            "\(Self.subject(screenID, index)) state '\(state)' requests resetPermissions '\(resource)', which undoes setup.privacy.grant '\(service)' before that state launches — the app would ask again instead of finding it granted; drop one of the two"
        case .emptyOracleCommand:
            "oracle.command names no executable — every figure would be answered 'oracle failed'; write it as [\"path\", \"arg\", …]"
        case let .figuresWithoutOracle(screenID, index):
            "\(Self.subject(screenID, index)) names figures, but the walkbook has no oracle — nothing could compute what they are checked against; add a top-level oracle"
        case let .emptyFigures(screenID, index):
            "\(Self.subject(screenID, index)) requests figures [] — an empty list checks nothing exactly as its absence does, so omit the key"
        case let .blankFigureField(screenID, index, figureIndex, key):
            "\(Self.subject(screenID, index)) figure \(figureIndex) has a blank \(key) — \(key == "id" ? "the oracle could not be told which figure it is" : "nothing on screen could carry it")"
        case let .emptyFigureWindows(screenID, index, figureID):
            "\(Self.subject(screenID, index)) figure '\(figureID)' names no window, or a blank one — the oracle would be asked for nothing to match against"
        case let .duplicateFigureID(screenID, index, figureID):
            "\(Self.subject(screenID, index)) names figure '\(figureID)' twice — their answers could not be told apart"
        case let .figureElementPlaceholders(screenID, index, figureID, count):
            "\(Self.subject(screenID, index)) figure '\(figureID)' writes {n} \(count) times in its element — a figure is one number, so its pattern names exactly one"
        }
    }

    /// Where a placeholder standing in for a missing key or step sits: one screen, or the walkbook's own top-level container — `nil` for a problem that leaves no placeholder at all, and for ``undecodable``, whose decode stopped before any walkbook existed to scope a placeholder within.
    ///
    /// Exhaustive rather than `default:`, so a problem added later that leaves a placeholder has to say where it scopes rather than silently naming nowhere.
    var placeholderScope: PlaceholderScope? {
        switch self {
        case let .missingKey(path, _), let .routeStepNotOneStep(path, _):
            Self.screenIndex(inPath: path).map(PlaceholderScope.screen) ?? .walkbook
        case .undecodable:
            nil
        case .blankWalkName, .blankAppBundleID, .noScreens, .blankScreenID, .duplicateScreenID, .collidingScreenIDs, .emptyRoute,
             .blankRouteStepLabel, .blankTypedText, .malformedTapPoint, .tapPointOutsideElement, .tapPointOffScreen, .tapPointFractionalWithoutLabel, .noCaptureStates, .duplicateCaptureState, .unknownDynamicTypeSize, .unknownLocale,
             .emptyLaunchCondition, .blankLaunchCondition, .animationsInStateEnvironment, .unknownPermission, .locationOutOfRange, .nonPositiveSettle, .emptyBudgets, .negativeBudget, .measureIterationsOutOfRange, .blankExpect, .paddedExpect, .emptyExpectMenu, .blankExpectMenuLabel, .paddedExpectMenuLabel, .unknownKey, .misplacedKey, .mangledExpect, .placeholderInTabStep,
             .placeholderInSystemTapStep, .ownerInSystemTapStep, .atLaunchAfterFirstStep, .unopenableURL, .emptyOracleCommand, .unknownPrivacyService, .privacyGrantedAndRevoked, .privacyGrantUndoneByReset, .figuresWithoutOracle, .emptyFigures,
             .blankFigureField, .emptyFigureWindows, .duplicateFigureID, .figureElementPlaceholders, .unsupportedOnDevice:
            nil
        }
    }

    /// The screen index a rendered path (`StrictKeyDecoding.renderedPath`) begins with — `screens[1]`, `screens[1].states[0]` — or `nil` for a path naming the walkbook's own top-level container (empty) or something else entirely.
    private static func screenIndex(inPath path: String) -> Int? {
        guard path.hasPrefix("screens["), let close = path.firstIndex(of: "]") else { return nil }
        let start = path.index(path.startIndex, offsetBy: "screens[".count)
        return Int(path[start ..< close])
    }

    /// Names a screen by its id, falling back to its position when the id is blank — a problem reported against `''` names nothing.
    private static func subject(_ screenID: String, _ index: Int) -> String {
        screenID.isEmpty ? "screen at index \(index)" : "screen '\(screenID)'"
    }

    /// The trailing clause naming a near miss, or nothing at all when there is no honest guess to offer.
    private static func meantInstead(_ suggestion: String?) -> String {
        suggestion.map { "; did you mean '\($0)'?" } ?? ""
    }
}

extension WalkbookProblem {
    /// Where a placeholder's path locates it: one screen, or the walkbook's own fields.
    enum PlaceholderScope: Equatable, Sendable {
        case screen(Int)
        case walkbook

        /// The screen index this scope names, or `nil` for ``walkbook``.
        var screenIndex: Int? {
            guard case let .screen(index) = self else { return nil }
            return index
        }
    }
}
