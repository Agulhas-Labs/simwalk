//
// Copyright © Agulhas Labs
//

import CryptoKit
import Foundation

/// A declarative description of a UI walk: the screens to visit, the route to each, and the states to capture there (Brief §2.1).
///
/// The model is deliberately format-neutral (`Codable`). A walkbook is authored as a JSON data file (Brief §7.1, answered), but the format is a decoder in front of this shape rather than the shape itself — a YAML front end would be a second decoder producing the same `Walkbook`, and the runner executes only this shape either way.
public struct Walkbook: Codable, Equatable, Sendable {
    /// A human-readable name for the walk, echoed into every capture bundle's manifest.
    public var name: String
    /// The bundle identifier of the app under validation.
    public var appBundleID: String
    /// The screens to visit, in order.
    public var screens: [Screen]
    /// The external command that computes each figure's expected value (Brief §2.3); `nil` when the walk checks no figures.
    public var oracle: Oracle?
    /// Device preparation the host makes before the runner starts and hands back after it; `nil` makes none.
    public var setup: Setup?

    public init(name: String, appBundleID: String, screens: [Screen], oracle: Oracle? = nil, setup: Setup? = nil) {
        self.name = name
        self.appBundleID = appBundleID
        self.screens = screens
        self.oracle = oracle
        self.setup = setup
    }
}

extension Walkbook {
    /// A `CodingKey` naming each field by its case rather than a string literal — `DerivedBundlePathRule` flags any literal spelling "screens" outside `CaptureBundleLayout`, and this field name collides with the bundle's own path component of the same word by coincidence, not by relation.
    private enum FieldName: String, CodingKey, CaseIterable {
        case name, appBundleID, screens, oracle, setup
    }

    /// Decodes strictly rather than relying on synthesis (round 2, finding 2): the top-level object gets the same treatment `Screen`, `CaptureState` and `RouteStep` already do, so `{"nam": "…"}` or a stray top-level key is a decode failure instead of a silently ignored field.
    public init(from decoder: Decoder) throws {
        let anyKeyed = try decoder.container(keyedBy: AnyCodingKey.self)
        try StrictKeyDecoding.checkUnknownKeys(in: anyKeyed, allowing: FieldName.allCases.map(\.stringValue), decoder: decoder)
        let container = try decoder.container(keyedBy: FieldName.self)
        name = try StrictKeyDecoding.required(String.self, forKey: .name, in: container, decoder: decoder, placeholder: "")
        appBundleID = try StrictKeyDecoding.required(String.self, forKey: .appBundleID, in: container, decoder: decoder, placeholder: "")
        screens = try StrictKeyDecoding.required([Screen].self, forKey: .screens, in: container, decoder: decoder, placeholder: [])
        oracle = try container.decodeIfPresent(Oracle.self, forKey: .oracle)
        setup = try container.decodeIfPresent(Setup.self, forKey: .setup)
    }
}

public extension Walkbook {
    /// One screen the walk must reach, with the route to it and the states to capture once there.
    struct Screen: Codable, Equatable, Sendable {
        /// A stable identifier for the screen, used to key captures, diffs, and oracle answers.
        public var id: String
        /// The steps that reach the screen from the app's launch state.
        public var route: [RouteStep]
        /// The variants to capture on arrival, of which at least one is required — see `WalkbookProblem.noCaptureStates` for why "whatever the device is currently in" is not a state a manifest can attest to.
        public var states: [CaptureState]
        /// How long *this* screen's hierarchy must hold still before a capture, in milliseconds; `nil` uses the walk's own quiet period.
        ///
        /// For content that arrives after the screen does. A tab whose content streams in over a second or two captures as a spinner at the default, and the only remedy was `--settle` — which is global, so one slow screen tripled the whole walk (SimWalk#7). Stated here, a screen that needs the time pays for itself and nothing else changes. `WalkbookLoader` refuses a non-positive value rather than falling back to the default in silence, which is the same discard `--settle 0` is refused for.
        public var settle: Int?
        /// Whether this screen's captures record `motion` — when its tree last changed before the capture, at the cadence it was read (SimWalk#67); `nil` and `false` record nothing unless the walk is run with `--motion`, which records it for every screen (`MotionOptIn`).
        ///
        /// Opt-in per screen, as `settle` is, so the one screen whose settling is in question is the one that carries the record. Left out of the canonical encoding when absent, so a walkbook without it hashes as it always did.
        public var motion: Bool?
        /// Whether this device walk measures the screen's route from a cold launch, and over how many iterations (SimWalk#67, M4); `nil` measures nothing unless the screen states a performance budget (`MeasureOptIn`).
        ///
        /// Written `"measure": true` or `{"iterations": N}`; `false` is the same as absent. Only a device walk runs it: a simulator walk captures the screen as usual and says the measure was not run. Left out of the canonical encoding when absent, so a walkbook without it hashes as it always did.
        public var measure: Measure?
        /// The motion this screen is held to by `bundle audit --walkbook` (SimWalk#67, M3); `nil` holds it to none.
        ///
        /// A budget implies `motion` (`MotionOptIn.records(_:in:)`): a budget nothing records can only answer UNREACHABLE. Left out of the canonical encoding when absent, so a walkbook without it hashes as it always did.
        public var budgets: Budgets?
        /// An accessibility identifier the reached screen carries (not the tab bar, toolbar or navigation bar); `nil` checks nothing.
        ///
        /// A route can complete, settle, and hold real content, and still not be the screen a walkbook believes it reached — the README's standing caveat that a route leaving the app records the wrong screenshot under a passing outcome. `expect` is how a walkbook checks itself instead of trusting the route that was meant to reach it: `ExpectedScreenCheck` compares it with the screen-level identifiers (`ScreenIdentifierRule`) of every capture the screen takes, passing on any of them, outermost or nested (SimWalk#103) — never a navigation bar's title, and a mismatch becomes the screen's outcome (`ScreenOutcome.unexpectedScreen`) rather than a note beside a passing one. Opt-in, because it only means anything for an app that sets an identifier on each screen's content for exactly this purpose.
        public var expect: String?
        /// The labels an open menu must show, in order, read top-down or bottom-up (a menu opening upwards lists its items reversed); `nil` checks nothing (SimWalk#111).
        ///
        /// For a route that ends by opening a SwiftUI system `Menu`, whose open state hides the screen's identifier and has none of its own, so `expect` cannot verify it. `ExpectedMenuCheck` holds every capture's `Button` labels to these as an ordered subsequence, each matched exactly; a mismatch is the screen's outcome (`ScreenOutcome.unexpectedScreen`). Independent of `expect` — and since an open menu hides the screen's identifier, `expect` beside `expectMenu` normally fails. Left out of the canonical encoding when absent, so a walkbook without it hashes as it always did.
        public var expectMenu: [String]?
        /// Free-form notes carried through to the differ (per-screen segmentation hints, known quirks).
        public var notes: String?
        /// The figures on this screen whose values the walk's `oracle` is asked for, in every state the screen captures; `nil` checks none.
        public var figures: [Figure]?

        public init(
            id: String,
            route: [RouteStep],
            states: [CaptureState],
            settle: Int? = nil,
            motion: Bool? = nil,
            measure: Measure? = nil,
            budgets: Budgets? = nil,
            expect: String? = nil,
            expectMenu: [String]? = nil,
            notes: String? = nil,
            figures: [Figure]? = nil
        ) {
            self.id = id
            self.route = route
            self.states = states
            self.settle = settle
            self.motion = motion
            self.measure = measure
            self.budgets = budgets
            self.expect = expect
            self.expectMenu = expectMenu
            self.notes = notes
            self.figures = figures
        }
    }

    /// The motion and performance a screen is held to: motion (SimWalk#67, M3) at most `settleMs` for its tree to settle and at most `layoutShifts` layout shifts while it does; performance (M4) at most `launchMs`, `transitionHitches`, `cpuMs` and `memoryPeakMB`, each against the median of the figures a device walk measured.
    ///
    /// A budget is a value judgement, so it is checked by `bundle audit` (`motionBudget`, `performanceBudget`) against what a walk recorded, never by the walk. Each key is optional, but a `budgets` object with none is refused (`WalkbookProblem.emptyBudgets`), as is a negative figure. **The motion keys imply `motion` and the performance keys imply `measure`, and neither implies the other** (`MotionOptIn`, `MeasureOptIn`).
    struct Budgets: Codable, Equatable, Sendable {
        /// The longest the tree may take to settle, in milliseconds.
        public var settleMs: Int?
        /// The most layout shifts the watch may see; `0` allows none.
        public var layoutShifts: Int?
        /// The longest the app may take to its first responsive frame from a cold launch, in milliseconds.
        public var launchMs: Int?
        /// The most hitches the route's navigation transition may drop; `0` allows none.
        public var transitionHitches: Int?
        /// The most CPU time the app may use over the route, in milliseconds.
        public var cpuMs: Int?
        /// The most physical memory the app may peak at over the route, in megabytes (1 MB = 1024 kB).
        public var memoryPeakMB: Int?

        public init(settleMs: Int? = nil, layoutShifts: Int? = nil, launchMs: Int? = nil, transitionHitches: Int? = nil, cpuMs: Int? = nil, memoryPeakMB: Int? = nil) {
            self.settleMs = settleMs
            self.layoutShifts = layoutShifts
            self.launchMs = launchMs
            self.transitionHitches = transitionHitches
            self.cpuMs = cpuMs
            self.memoryPeakMB = memoryPeakMB
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: AnyCodingKey.self)
            try StrictKeyDecoding.checkUnknownKeys(in: container, allowing: Self.keys, decoder: decoder)
            settleMs = try container.decodeIfPresent(Int.self, forKey: AnyCodingKey("settleMs"))
            layoutShifts = try container.decodeIfPresent(Int.self, forKey: AnyCodingKey("layoutShifts"))
            launchMs = try container.decodeIfPresent(Int.self, forKey: AnyCodingKey("launchMs"))
            transitionHitches = try container.decodeIfPresent(Int.self, forKey: AnyCodingKey("transitionHitches"))
            cpuMs = try container.decodeIfPresent(Int.self, forKey: AnyCodingKey("cpuMs"))
            memoryPeakMB = try container.decodeIfPresent(Int.self, forKey: AnyCodingKey("memoryPeakMB"))
        }

        private static let keys = ["settleMs", "layoutShifts", "launchMs", "transitionHitches", "cpuMs", "memoryPeakMB"]

        /// Each stated budget by its key, in the order the keys are documented.
        var stated: [(key: String, value: Int)] {
            [("settleMs", settleMs), ("layoutShifts", layoutShifts), ("launchMs", launchMs), ("transitionHitches", transitionHitches), ("cpuMs", cpuMs), ("memoryPeakMB", memoryPeakMB)]
                .compactMap { key, value in value.map { (key, $0) } }
        }

        /// Whether a motion budget (`settleMs`, `layoutShifts`) is stated: the ones `motionBudget` checks and that imply `motion`.
        public var hasMotionBudget: Bool {
            settleMs != nil || layoutShifts != nil
        }

        /// Whether a performance budget (`launchMs`, `transitionHitches`, `cpuMs`, `memoryPeakMB`) is stated: the ones `performanceBudget` checks and that imply `measure`.
        public var hasPerformanceBudget: Bool {
            launchMs != nil || transitionHitches != nil || cpuMs != nil || memoryPeakMB != nil
        }
    }

    /// A screen's `measure` (SimWalk#67, M4): how many times a device walk launches the app and takes the route to read its launch, CPU, memory and transition figures.
    ///
    /// `true` is the default of ``defaultIterations``; `{"iterations": N}` states it. Whether `N` is in ``allowedIterations`` is the loader's to refuse (`WalkbookProblem.measureIterationsOutOfRange`), so the problem can name the screen. **Encoded as `true` when it is the default**, so the two spellings of one request are one walkbook.
    struct Measure: Codable, Equatable, Sendable {
        /// What `"measure": true` means.
        public static let defaultIterations = 3
        /// The iteration counts a walkbook may ask for: each costs a cold launch and a route (about 6.5 s on a device, measured), and one is the least that is a measurement.
        public static let allowedIterations = 1 ... 10

        public var iterations: Int

        public init(iterations: Int = Measure.defaultIterations) {
            self.iterations = iterations
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: AnyCodingKey.self)
            try StrictKeyDecoding.checkUnknownKeys(in: container, allowing: ["iterations"], decoder: decoder)
            iterations = try container.decodeIfPresent(Int.self, forKey: AnyCodingKey("iterations")) ?? Self.defaultIterations
        }

        public func encode(to encoder: Encoder) throws {
            if iterations == Self.defaultIterations {
                var single = encoder.singleValueContainer()
                try single.encode(true)
            } else {
                var container = encoder.container(keyedBy: AnyCodingKey.self)
                try container.encode(iterations, forKey: AnyCodingKey("iterations"))
            }
        }
    }

    /// A single deterministic navigation step, executed by the XCUITest runner without improvisation.
    enum RouteStep: Codable, Equatable, Sendable, CustomStringConvertible {
        /// Select the tab with the given accessibility label.
        case tab(label: String)
        /// Tap the element with the given accessibility label.
        case tap(label: String)
        /// Tap the element with the given accessibility label and type `text` into it.
        ///
        /// The vocabulary could reach a search field and not drive it, so a search screen was capturable only empty (SimWalk#1 item 2). Tapping is part of the step rather than something an author writes before it: typing into a field that never took focus is an XCUITest failure and not a value the route loop can report, so the runner takes the focus itself, resolves the label among elements that can actually take text, and reports the step as not landed unless the field is afterwards carrying what was typed.
        case type(label: String, text: String)
        /// Scroll until the element with the given accessibility label is on screen.
        case scrollTo(label: String)
        /// Tap a point rather than an element found by its label — for an accessibility tree that lies (SimWalk#29).
        ///
        /// Apple Health's charts are the specimen: after a period switch the previous period's bars stay in the tree with zero frames, and once a bar is selected the hero freezes on the selected value, so a bar can be reached by where it is drawn and by nothing the tree says. **With a `label`, `at` is a point within that element's frame**, each coordinate a fraction from 0 to 1 (`[0.8, 0.5]`: four fifths across, halfway down) — it survives a change of device, so it is the form to reach for first; the label resolves exactly as a `scrollTo`'s does. **Without one, `at` is a point on the screen in device points** (`[201, 610]`).
        ///
        /// A step of its own rather than a `tap` with an extra field, so a route — a manifest's `routeTaken` above all — says at a glance that this step was not resolved by label. Its landing is the touch delivered inside the screen (and inside the element's frame), never that the screen changed: a bar lighting up is a change within a screen, which `ScreenIdentity` deliberately cannot see.
        case tapPoint(label: String?, point: [Double])
        /// Tap a control on a system sheet — a permission prompt the app asked the system for, not a screen of its own (SimWalk#28).
        ///
        /// **The label resolves in SpringBoard's tree first, then in the app's**, because the system draws its sheets in two places: the notifications alert is SpringBoard's, while HealthKit's authorization sheet is hosted inside the app's own window. An identifier matches as well as a label, and HealthKit's controls carry stable ones (`UIA.Health.AuthSheet.AllCategoryButton`, `UIA.Health.Allow.Button`), so a walkbook need not pin wording that counts the topics asked for.
        ///
        /// A step of its own rather than a `tap`, so a route — a manifest's `routeTaken` above all — records that it answered the system rather than navigated the app. Its landing is the touch delivered to an enabled control: `Select All` changes a sheet without leaving it, which `ScreenIdentity` is built not to see. **A sheet answered is gone for good**, so it is there only on the launch that first asks — the first state of the first screen that meets it; a later state's fresh launch finds no sheet and the step is UNREACHABLE, honestly.
        ///
        /// **`atLaunch` says the launch itself raises the sheet this step answers** (SimWalk#46) — an app that asks from its initialiser has no screen of its own to read before the sheet, so the control is taken on the author's word rather than on being new (`SystemSheetScope.admittingAll(of:)`). Written only when true, and only on a route's first step (`WalkbookLoader`).
        ///
        /// **`owner` is the runner's to write, never a walkbook's** (the SimWalk#28 review): which tree the control was found in, recorded on the step in `routeTaken`, so a manifest claims no more than the runner knew. A walkbook that writes one is refused.
        case systemTap(label: String, atLaunch: Bool = false, owner: SystemSheetOwner? = nil)
        /// Open a URL in the walked app, in place of the tap chain that would reach the same screen.
        ///
        /// A deep link is one step where the taps are five, and a route that survives a rework of the UI in between: a screen reached by its URL keeps being reached when a tab is renamed or a list is reordered. The step is refused by `validate` when the URL does not parse or names no scheme.
        ///
        /// **Landing is arrival, exactly as for a navigating `tap`**: the hierarchy must leave the screen the step was taken on (`ScreenIdentity`), else the screen is UNREACHABLE naming the step. A URL the app does not route (`simwalk-fixture://nowhere`) leaves it on the screen it was on, and is reported that way rather than captured as though it had gone anywhere.
        ///
        /// The runner opens an `http` or `https` URL through the system (`XCUIDevice.shared.system.open`), so a universal link routes as it would from outside the app, and any other scheme through the walked app (`XCUIApplication.open`). **Observed, not read from the docs** (iOS 27 simulator, `Fixtures/RouteFixture`): `XCUIApplication.open(_:)` on the app's own scheme routes it with no "Open in …?" confirmation, so no `systemTap` follows; a URL the app does not route leaves it on the screen it was on, which is the UNREACHABLE case above. The `http`/`https` path through the system was not exercised, having no fixture to answer it.
        case openURL(url: String)
        /// Navigate back one level.
        case back

        /// How a step is written wherever a route is shown to a reader — an UNREACHABLE verdict's `routeTried` above all, which is only honest if the route it names is legible.
        public var description: String {
            switch self {
            case let .tab(label):
                "tab '\(label)'"
            case let .tap(label):
                "tap '\(label)'"
            case let .type(label, text):
                "type '\(text)' into '\(label)'"
            case let .scrollTo(label):
                "scrollTo '\(label)'"
            case let .tapPoint(label?, point):
                "tap '\(label)' at \(Self.rendered(point)) of its frame"
            case let .tapPoint(nil, point):
                "tap at \(Self.rendered(point)) pt"
            case let .systemTap(label, atLaunch, owner):
                "systemTap '\(label)'" + (atLaunch ? " at launch" : "") + (owner.map { " in \($0.rendered)" } ?? "")
            case let .openURL(url):
                "openURL '\(url)'"
            case .back:
                "back"
            }
        }

        /// How a step is written into a progress file's `currentStep.action` (`Docs/SIMWALK-PROGRESS.md`): ``description`` without what can hold a secret.
        ///
        /// A status line puts that file on screen. A `type` step's text may be a password (SimWalk#90); an `openURL` step's URL may carry a token in its userinfo, path, query or fragment, so only its scheme and host are kept (SimWalk#91).
        var progressLine: String {
            switch self {
            case let .type(label, _):
                "type into '\(label)'"
            case let .openURL(url):
                "openURL '\(Self.redactedURL(url))'"
            default:
                description
            }
        }

        /// A URL cut down to where it goes: an `http` or `https` URL's `scheme://host`, then `/…` when userinfo, port, path, query or fragment was dropped.
        ///
        /// **Any other scheme keeps its scheme alone** (`scheme:…`): a custom scheme's host is whatever the app routes on, and a link like `myapp://3f9a1c-reset-token` carries its token there. One that does not parse with a scheme is only `…`, since any of it could be the secret.
        static func redactedURL(_ url: String) -> String {
            guard let components = URLComponents(string: url), let scheme = components.scheme, !scheme.isEmpty else {
                return "…"
            }
            guard ["http", "https"].contains(scheme.lowercased()), let host = components.host, !host.isEmpty else {
                return "\(scheme):…"
            }
            let trimmed = components.path.isEmpty && components.query == nil && components.fragment == nil
                && components.user == nil && components.password == nil && components.port == nil
            return "\(scheme)://\(host)" + (trimmed ? "" : "/…")
        }

        /// A point's coordinates as an author wrote them — `201,610`, `0.8,0.5` — without the `.0` a `Double` would print on every whole number.
        static func rendered(_ point: [Double]) -> String {
            point.map { value in
                let text = String(value)
                return text.hasSuffix(".0") ? String(text.dropLast(2)) : text
            }.joined(separator: ",")
        }
    }

    /// One appearance variant to capture on a screen.
    struct CaptureState: Codable, Equatable, Sendable {
        /// The interface style to capture under.
        public var theme: Theme
        /// A `UIContentSizeCategory` name (for example `UICTContentSizeCategoryAccessibilityL`); `nil` captures the device default.
        ///
        /// Passed through to the app's `-UIPreferredContentSizeCategoryName` launch argument verbatim, so it is the platform's own spelling rather than SwiftUI's `DynamicTypeSize` — `accessibility2` names the same size and is silently ignored, capturing the device default under a state slug claiming otherwise (verified byte-identical to an unset capture, screenshot and tree both).
        public var dynamicTypeSize: String?
        /// A locale identifier; `nil` captures the device's current locale.
        public var locale: String?
        /// Launch arguments the app is started with, after the ones the axes above become — verbatim and in order; `nil` launches with none of the state's own (SimWalk#44).
        ///
        /// For a screen an app shows only under a launch argument: an app's own launch argument (a data-seeding flag) raises a system authorization sheet, which a route then answers with `systemTap` steps. SimWalk cannot know whether an argument reaches the screen, so nothing here judges one beyond its being non-empty — see `StateApplicationCheck` for what that means for two states that drew one picture.
        public var arguments: [String]?
        /// Environment variables the app is launched with, laid over whatever the launch already carries with the state's value winning on a shared key; `nil` adds none.
        public var environment: [String: String]?
        /// The direction the app lays out in; `nil` leaves it to the device's language.
        ///
        /// Arrives as launch arguments (`launchArguments`), and is held to its artefact by `LayoutDirectionCheck`: a capture whose horizontal runs of siblings all run the other way is refused.
        public var layoutDirection: LayoutDirection?
        /// The location the simulator reports while this state is captured; `nil` leaves whatever the device was simulating when the walk began.
        ///
        /// Set by the runner on the device (`XCUIDevice.location`) before the launch, not passed to the app, and verified only where the capture shows the coordinate (`LocationShownCheck`); elsewhere the capture records it as set and unverified.
        public var location: Location?
        /// The protected resources whose authorization the app is reset to not-yet-asked for before this state's launch, by `ProtectedResourceName`; `nil` resets none.
        ///
        /// So a state whose route answers a permission sheet finds the sheet there on every walk, not only the first. Applied by the runner (`XCUIApplication.resetAuthorizationStatus(for:)`) after the previous state's app is terminated and before this one's launches; nothing checks it against the artefact beyond the route itself, which is UNREACHABLE at a `systemTap` whose sheet never came. Names are checked at validate against `ProtectedResourceName`.
        public var resetPermissions: [String]?

        public init(
            theme: Theme,
            dynamicTypeSize: String? = nil,
            locale: String? = nil,
            arguments: [String]? = nil,
            environment: [String: String]? = nil,
            layoutDirection: LayoutDirection? = nil,
            location: Location? = nil,
            resetPermissions: [String]? = nil
        ) {
            self.theme = theme
            self.dynamicTypeSize = dynamicTypeSize
            self.locale = locale
            self.arguments = arguments
            self.environment = environment
            self.layoutDirection = layoutDirection
            self.location = location
            self.resetPermissions = resetPermissions
        }

        /// A stable, filename-safe identifier for the state — the directory name a capture bundle files this state's artefacts under.
        ///
        /// Each optional axis carries a prefix (`dt_`, `loc_`) rather than being dropped positionally, because `dynamicTypeSize: "en_GB"` and `locale: "en_GB"` are different states and would otherwise slug identically. Two states with the same slug would overwrite each other inside a bundle, which is why `WalkbookLoader` rejects a screen carrying both rather than letting the runner discover it. The reduction itself belongs to `CaptureBundleLayout` — it is the one place a string becomes a path component.
        ///
        /// The later axes append after these, so a state that sets none of them slugs exactly as it did before they existed: `layoutDirection` as its own value (`rtl`, `ltr`), then `location` as `geo_<h>` over its latitude and longitude as Swift prints them, then `resetPermissions` as `reset_<h>` over its names de-duplicated and sorted — the same resets written in another order are the same state.
        ///
        /// **Arguments and environment are slugged by a hash, not reduced** (`args_<h>`, `env_<h>`, after the other axes): `<h>` is the first 8 hex characters of the SHA-256 of the arguments, or of the environment's key/value pairs sorted by key. Reducing them to letters would collide — `-a b` and `-a_b` are different launches and reduce to one segment — and would grow without bound with the list. The slug only has to tell states apart; the manifest's `state` carries the exact list for a reader.
        public var slug: String {
            var segments = [CaptureBundleLayout.slugSegment(theme.rawValue)]
            if let dynamicTypeSize {
                segments.append("dt_\(CaptureBundleLayout.slugSegment(dynamicTypeSize))")
            }
            if let locale {
                segments.append("loc_\(CaptureBundleLayout.slugSegment(locale))")
            }
            if let arguments {
                segments.append("args_\(Self.slugHash(arguments))")
            }
            if let environment {
                let pairs = environment.sorted { $0.key < $1.key }.flatMap { [$0.key, $0.value] }
                segments.append("env_\(Self.slugHash(pairs))")
            }
            if let layoutDirection {
                segments.append(layoutDirection.rawValue)
            }
            if let location {
                segments.append("geo_\(Self.slugHash([String(location.latitude), String(location.longitude)]))")
            }
            if let resetPermissions {
                segments.append("reset_\(Self.slugHash(Array(Set(resetPermissions)).sorted()))")
            }
            return segments.joined(separator: "-")
        }

        /// The first 8 hex characters of the SHA-256 of `parts`, each length-prefixed (`<byte count>:<bytes>`) and concatenated with no separator of its own.
        ///
        /// A joining separator is ambiguous two ways a length prefix is not: a JSON walkbook can carry a literal NUL (`"\u0000"`) inside an argument, which a NUL-joined hash cannot then tell from a part boundary, and an environment key holding `=` makes `{"A=B":"C"}` and `{"A":"B=C"}` hash alike under a `key=value` join. A length prefix can only be read one way, whatever bytes the part holds.
        private static func slugHash(_ parts: [String]) -> String {
            let encoded = parts.map { "\($0.utf8.count):\($0)" }.joined()
            return SHA256.hash(data: Data(encoded.utf8))
                .prefix(4)
                .map { String(format: "%02x", $0) }
                .joined()
        }
    }

    /// The interface style of a capture.
    enum Theme: String, Codable, Equatable, Sendable {
        case light
        case dark
    }

    /// A simulated location, in degrees.
    struct Location: Codable, Equatable, Sendable {
        public var latitude: Double
        public var longitude: Double

        public init(latitude: Double, longitude: Double) {
            self.latitude = latitude
            self.longitude = longitude
        }
    }

    /// The direction a capture lays out in — `rtl` mirrors the app as a right-to-left language would.
    enum LayoutDirection: String, Codable, Equatable, Sendable {
        case rtl
        case ltr
    }
}

extension Walkbook.RouteStep {
    /// The keys a `tapPoint` step is written with: its point is written `at`, as an author reads it (`tap 'Steps chart' at 0.8,0.5`), while the Swift name stays long enough to be a name.
    enum TapPointCodingKeys: String, CodingKey {
        case label
        case point = "at"
    }

    /// Where a `systemTap` found the control it tapped — the tree the runner read, and so the most the manifest can say about who drew it.
    public enum SystemSheetOwner: String, Codable, Equatable, Sendable {
        /// SpringBoard's tree, where the system's alerts are drawn: nothing the app draws is there.
        case springboard
        /// The app's own window, in a subtree that appeared after the app's own screen — where HealthKit hosts its authorization sheet (`SystemSheetScope`).
        case appWindow

        /// How a route shows it: `systemTap 'Allow' in SpringBoard`.
        var rendered: String {
            switch self {
            case .springboard:
                "SpringBoard"
            case .appWindow:
                "the app's window"
            }
        }
    }

    /// The name each case is written under — the only key its JSON object carries (`{"tab":{"label":"Progress"}}`).
    static let caseNames = ["tab", "tap", "type", "scrollTo", "tapPoint", "systemTap", "openURL", "back"]

    /// Decodes strictly rather than relying on synthesis, so a step naming a key its case does not take (SimWalk#10's sibling hole, one vocabulary over) is a decode failure instead of a silently ignored field.
    ///
    /// **The outer object is now `AnyCodingKey`, not a fixed case-name key (round 2, finding 2).** The container used to be keyed by an enum naming only the five cases, so its own `allKeys` silently dropped anything else — `{"tab":{"label":"You"},"expect":"x"}` decoded as a plain `tab` step, the spec's own wording ("`expect` … on a walkbook step") having led an author to put it exactly where it was invisible. Reading every key first is what lets `expect` there be reported at all, and what lets `{"tabb":…}` name the key and its nearest match instead of just "exactly one of tab, tap, …".
    public init(from decoder: Decoder) throws {
        let outer = try decoder.container(keyedBy: AnyCodingKey.self)
        try StrictKeyDecoding.checkUnknownKeys(in: outer, allowing: Self.caseNames, decoder: decoder)
        // Unknown keys may have been recorded rather than thrown (a `WalkbookProblemSink` is installed),
        // so what is left to choose among is only ever a caseName — but there can still be none (an empty
        // object, or every key present was unknown) or more than one (`{"tab":…, "tap":…}`), neither of
        // which `checkUnknownKeys` can catch: both are shapes about *which* key names the step, not about
        // a key outside its vocabulary.
        let recognized = outer.allKeys.filter { Self.caseNames.contains($0.stringValue) }
        guard recognized.count == 1, let selected = recognized.first else {
            if let sink = StrictKeyDecoding.sink(of: decoder) {
                // Recorded, and a placeholder stands in, so a misspelled case name (`tabb`) does not stop
                // every problem after it from being listed (round 4). `load` refuses whenever the sink holds
                // anything, so the placeholder is never walked, and never checked as though it were written.
                let names = Self.caseNames.filter { name in recognized.contains { $0.stringValue == name } }
                sink.record(.routeStepNotOneStep(path: StrictKeyDecoding.renderedPath(outer.codingPath), names: names))
                self = .back
                return
            }
            let allKeys = outer.allKeys.map(\.stringValue)
            let detail: String = if allKeys.isEmpty {
                "this one names none"
            } else if recognized.isEmpty {
                // Every key present was unrecognised, with no sink to have recorded them — named here,
                // because this guard always throws: there is no case left to build a value from.
                StrictKeyDecoding.message(for: allKeys, allowed: Self.caseNames)
            } else {
                "this one names \(recognized.map { "'\($0.stringValue)'" }.joined(separator: ", "))"
            }
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: outer.codingPath,
                debugDescription: "a route step names exactly one of \(Self.caseNames.joined(separator: ", ")) — \(detail)"
            ))
        }
        let payload = try outer.nestedContainer(keyedBy: AnyCodingKey.self, forKey: selected)
        switch selected.stringValue {
        case "tab":
            try StrictKeyDecoding.checkUnknownKeys(in: payload, allowing: ["label"], decoder: decoder)
            self = try .tab(label: Self.label(in: payload, decoder: decoder))
        case "tap":
            try StrictKeyDecoding.checkUnknownKeys(in: payload, allowing: ["label"], decoder: decoder)
            self = try .tap(label: Self.label(in: payload, decoder: decoder))
        case "type":
            try StrictKeyDecoding.checkUnknownKeys(in: payload, allowing: ["label", "text"], decoder: decoder)
            self = try .type(
                label: Self.label(in: payload, decoder: decoder),
                text: StrictKeyDecoding.required(String.self, forKey: AnyCodingKey("text"), in: payload, decoder: decoder, placeholder: "")
            )
        case "scrollTo":
            try StrictKeyDecoding.checkUnknownKeys(in: payload, allowing: ["label"], decoder: decoder)
            self = try .scrollTo(label: Self.label(in: payload, decoder: decoder))
        case "tapPoint":
            // `label` is optional here and only here: its presence is what makes `at` a point within an
            // element rather than one on the screen. `at` stays a plain array so a walkbook built or decoded
            // anywhere is held to one arity rule, in `WalkbookLoader`, rather than one that only the file
            // format enforces.
            try StrictKeyDecoding.checkUnknownKeys(in: payload, allowing: ["label", "at"], decoder: decoder)
            self = try .tapPoint(
                label: Self.tapPointLabel(in: payload, decoder: decoder),
                point: StrictKeyDecoding.required([Double].self, forKey: AnyCodingKey("at"), in: payload, decoder: decoder, placeholder: [])
            )
        case "systemTap":
            try StrictKeyDecoding.checkUnknownKeys(in: payload, allowing: ["label", "atLaunch", "owner"], decoder: decoder)
            self = try .systemTap(
                label: Self.label(in: payload, decoder: decoder),
                atLaunch: payload.decodeIfPresent(Bool.self, forKey: AnyCodingKey("atLaunch")) ?? false,
                owner: payload.decodeIfPresent(SystemSheetOwner.self, forKey: AnyCodingKey("owner"))
            )
        case "openURL":
            try StrictKeyDecoding.checkUnknownKeys(in: payload, allowing: ["url"], decoder: decoder)
            self = try .openURL(url: StrictKeyDecoding.required(String.self, forKey: AnyCodingKey("url"), in: payload, decoder: decoder, placeholder: ""))
        default:
            try StrictKeyDecoding.checkUnknownKeys(in: payload, allowing: [], decoder: decoder)
            self = .back
        }
    }

    /// Encodes as synthesis did before `atLaunch` (SimWalk#46), which synthesis would write on every `systemTap` as `false`: here it is written only when true, so every walkbook and manifest without the declaration is byte-identical to one written before it existed.
    public func encode(to encoder: Encoder) throws {
        var outer = encoder.container(keyedBy: AnyCodingKey.self)
        var payload = outer.nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey(caseName))
        switch self {
        case let .tab(label), let .tap(label), let .scrollTo(label):
            try payload.encode(label, forKey: AnyCodingKey("label"))
        case let .type(label, text):
            try payload.encode(label, forKey: AnyCodingKey("label"))
            try payload.encode(text, forKey: AnyCodingKey("text"))
        case let .tapPoint(label, point):
            try payload.encodeIfPresent(label, forKey: AnyCodingKey(TapPointCodingKeys.label.rawValue))
            try payload.encode(point, forKey: AnyCodingKey(TapPointCodingKeys.point.rawValue))
        case let .systemTap(label, atLaunch, owner):
            try payload.encode(label, forKey: AnyCodingKey("label"))
            if atLaunch {
                try payload.encode(atLaunch, forKey: AnyCodingKey("atLaunch"))
            }
            try payload.encodeIfPresent(owner, forKey: AnyCodingKey("owner"))
        case let .openURL(url):
            try payload.encode(url, forKey: AnyCodingKey("url"))
        case .back:
            break
        }
    }

    /// The name this step is written under, one of `caseNames`.
    private var caseName: String {
        switch self {
        case .tab: "tab"
        case .tap: "tap"
        case .type: "type"
        case .scrollTo: "scrollTo"
        case .tapPoint: "tapPoint"
        case .systemTap: "systemTap"
        case .openURL: "openURL"
        case .back: "back"
        }
    }

    /// The `label` every step but `back` and `tapPoint` requires, read through `StrictKeyDecoding.required` so a missing one is listed and decoded past on the loader's path.
    private static func label(in payload: KeyedDecodingContainer<AnyCodingKey>, decoder: Decoder) throws -> String {
        try StrictKeyDecoding.required(String.self, forKey: AnyCodingKey("label"), in: payload, decoder: decoder, placeholder: "")
    }

    /// A `tapPoint` step's `label`, where omitting the key and writing it `null` must not decode to the same thing (SimWalk#29 review, item 2): `decodeIfPresent` alone reads both as "no label", so `{"tapPoint":{"label":null,"at":[0.8,0.5]}}` — a label an author deleted the value of but not the key — silently became the absolute form and tapped the status bar rather than a point in an element.
    ///
    /// Absent is still "no label, `at` is a screen point"; written `null` is refused by name instead.
    private static func tapPointLabel(in payload: KeyedDecodingContainer<AnyCodingKey>, decoder _: Decoder) throws -> String? {
        let key = AnyCodingKey("label")
        guard payload.contains(key) else { return nil }
        guard try !payload.decodeNil(forKey: key) else {
            throw DecodingError.dataCorrupted(DecodingError.Context(
                codingPath: payload.codingPath + [key],
                debugDescription: "a tapPoint step's label is null — omit the key entirely for a point on the screen, or name the element for a point within it"
            ))
        }
        return try payload.decode(String.self, forKey: key)
    }
}

public extension Walkbook.Location {
    /// Decodes strictly, like a state: a misspelled `lat` is refused with the key it probably meant rather than decoded as a missing coordinate.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        try StrictKeyDecoding.checkUnknownKeys(in: container, allowing: ["latitude", "longitude"], decoder: decoder)
        latitude = try StrictKeyDecoding.required(Double.self, forKey: AnyCodingKey("latitude"), in: container, decoder: decoder, placeholder: 0)
        longitude = try StrictKeyDecoding.required(Double.self, forKey: AnyCodingKey("longitude"), in: container, decoder: decoder, placeholder: 0)
    }
}

public extension Walkbook.CaptureState {
    /// Decodes strictly rather than relying on synthesis (SimWalk#10): a misspelled `textSize` beside a correctly spelled `theme` decoded today, captured the device's default size, and filed it under a slug asserting the size — with `walk` reporting `0 state-not-applied`, since nothing had asked the runner to apply an axis it never saw.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        try StrictKeyDecoding.checkUnknownKeys(in: container, allowing: ["theme", "dynamicTypeSize", "locale", "arguments", "environment", "layoutDirection", "location", "resetPermissions"], decoder: decoder)
        theme = try StrictKeyDecoding.required(Walkbook.Theme.self, forKey: AnyCodingKey("theme"), in: container, decoder: decoder, placeholder: .light)
        dynamicTypeSize = try container.decodeIfPresent(String.self, forKey: AnyCodingKey("dynamicTypeSize"))
        locale = try container.decodeIfPresent(String.self, forKey: AnyCodingKey("locale"))
        arguments = try container.decodeIfPresent([String].self, forKey: AnyCodingKey("arguments"))
        environment = try container.decodeIfPresent([String: String].self, forKey: AnyCodingKey("environment"))
        layoutDirection = try container.decodeIfPresent(Walkbook.LayoutDirection.self, forKey: AnyCodingKey("layoutDirection"))
        location = try container.decodeIfPresent(Walkbook.Location.self, forKey: AnyCodingKey("location"))
        resetPermissions = try container.decodeIfPresent([String].self, forKey: AnyCodingKey("resetPermissions"))
    }

    /// The resources this state resets before its launch, de-duplicated and in `ProtectedResourceName`'s order — what the runner hands to `resetAuthorizationStatus(for:)`, one call each.
    ///
    /// A name `ProtectedResourceName` does not know is dropped here because `WalkbookLoader` has already refused it; the runner never sees a walkbook that carries one.
    var resourcesToReset: [ProtectedResourceName] {
        let named = Set(resetPermissions ?? [])
        return ProtectedResourceName.allCases.filter { named.contains($0.rawValue) }
    }

    /// The launch arguments that make this state's axes true, for the axes the device has no automation API for, followed by the state's own `arguments` verbatim.
    ///
    /// **Built here rather than in the runner**, because `swift test` never compiles `Runner/`: the runner sets what this returns and adds nothing, so the strings the app is launched with are checked by the core's tests.
    ///
    /// **Appearance is not among them, and the spike proved why.** `-UIUserInterfaceStyle` as an `NSArgumentDomain` override looked plausible and did nothing: a walk asking for light and dark produced two screenshots with different bytes — a clock and a status bar differ between any two shots — and identical mean pixel values. Both were light. A bundle labelling a light capture `dark` is the exact dishonesty this format exists to prevent, and it would have passed every check in it, because nothing here can see what a screenshot depicts. `XCUIDevice.shared.appearance` is the real mechanism and is set at the runner's call site.
    ///
    /// These remaining overrides are correctly *spelled* by then — `WalkbookLoader` refuses a `dynamicTypeSize` or `locale` this platform has no such name for — but spelling is not application, and an override that is spelled correctly and silently does nothing was for a long time unchecked by anything. `StateApplicationCheck` is that gate now: states that came back byte-identical are refused rather than filed, so these claims are held to the evidence they produce instead of taken on trust. Appearance rides it too, which is how it caught iOS 26.5 reporting `dark` set and changing nothing. The state's own `arguments` are not held to it — nothing can say whether an argument reaches the screen.
    var launchArguments: [String] {
        var launched: [String] = []
        if let dynamicTypeSize {
            launched += ["-UIPreferredContentSizeCategoryName", dynamicTypeSize]
        }
        if let locale {
            launched += ["-AppleLocale", locale, "-AppleLanguages", "(\(locale))"]
        }
        // Both overrides, because on iOS 27 neither mirrors a SwiftUI app alone: measured on the simulator,
        // `-AppleTextDirection YES` by itself and `-NSForceRightToLeftWritingDirection YES` by itself each
        // left an HStack running left to right, and the pair together mirrored it.
        if let layoutDirection {
            let forced = layoutDirection == .rtl ? "YES" : "NO"
            launched += ["-AppleTextDirection", forced, "-NSForceRightToLeftWritingDirection", forced]
        }
        return launched + (arguments ?? [])
    }

    /// The launch environment this state asks for, laid over `base` — the environment the launch already carries — with the state's value winning on a shared key, except `DYLD_INSERT_LIBRARIES`, which when both carry it becomes the state's value, `:`, then the base's.
    func launchEnvironment(over base: [String: String]) -> [String: String] {
        base.merging(environment ?? [:]) { _, stated in stated }
            .merging(joinedLibraries(over: base)) { _, joined in joined }
    }

    /// `DYLD_INSERT_LIBRARIES` joined, when the state and the base both carry it, so a state's library never drops SimWalk's (SimWalk#154); a state's empty value keeps the base's rather than replacing it.
    private func joinedLibraries(over base: [String: String]) -> [String: String] {
        let key = AnimationsOptIn.insertLibrariesKey
        guard let stated = environment?[key], let inherited = base[key], !inherited.isEmpty else { return [:] }
        return [key: stated.isEmpty ? inherited : stated + ":" + inherited]
    }
}

public extension Walkbook.Screen {
    private static let knownKeys = ["id", "route", "states", "settle", "motion", "measure", "budgets", "expect", "expectMenu", "notes", "figures"]

    /// Decodes strictly rather than relying on synthesis (round 2, finding 2): `{"expects": "…"}` on a screen — the spec's own wording, misspelled — used to decode cleanly with `expect` left `nil`, turning the check silently off on the one screen an author meant to turn it on for.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: AnyCodingKey.self)
        try StrictKeyDecoding.checkUnknownKeys(in: container, allowing: Self.knownKeys, decoder: decoder)
        id = try StrictKeyDecoding.required(String.self, forKey: AnyCodingKey("id"), in: container, decoder: decoder, placeholder: "")
        route = try StrictKeyDecoding.required([Walkbook.RouteStep].self, forKey: AnyCodingKey("route"), in: container, decoder: decoder, placeholder: [])
        states = try StrictKeyDecoding.required([Walkbook.CaptureState].self, forKey: AnyCodingKey("states"), in: container, decoder: decoder, placeholder: [])
        settle = try container.decodeIfPresent(Int.self, forKey: AnyCodingKey("settle"))
        motion = try container.decodeIfPresent(Bool.self, forKey: AnyCodingKey("motion"))
        // `true`, `false` or `{"iterations": N}`: a bare boolean is tried first, and anything else is read as the object so its own error names the key.
        if let flag = try? container.decode(Bool.self, forKey: AnyCodingKey("measure")) {
            measure = flag ? Walkbook.Measure() : nil
        } else {
            measure = try container.decodeIfPresent(Walkbook.Measure.self, forKey: AnyCodingKey("measure"))
        }
        budgets = try container.decodeIfPresent(Walkbook.Budgets.self, forKey: AnyCodingKey("budgets"))
        expect = try container.decodeIfPresent(String.self, forKey: AnyCodingKey("expect"))
        expectMenu = try container.decodeIfPresent([String].self, forKey: AnyCodingKey("expectMenu"))
        notes = try container.decodeIfPresent(String.self, forKey: AnyCodingKey("notes"))
        figures = try container.decodeIfPresent([Walkbook.Figure].self, forKey: AnyCodingKey("figures"))
    }
}

extension [Walkbook.RouteStep] {
    /// The route as a reader sees it, and the only spelling of one.
    ///
    /// An empty route renders as "nothing" rather than as nothing at all: a line reading `route tried:` with the rest missing looks like a truncated answer, where an UNREACHABLE verdict that names no attempt is a fact worth stating plainly.
    var rendered: String {
        isEmpty ? "nothing" : map(\.description).joined(separator: " → ")
    }
}

public extension Walkbook {
    /// The command a walk's figures are checked against (Brief §2.3): an external process speaking JSON on stdin and stdout, so nothing about the data source — HealthKit, a corpus, a work service — enters SimWalk.
    ///
    /// `command[0]` is the executable. **A relative path in it resolves against the walkbook's own directory**, and the command runs with that directory as its working directory, so a walkbook and the oracle beside it move together; a bare name (`python3`) is looked up on `PATH`. The protocol is `ValueOracle`'s.
    struct Oracle: Codable, Equatable, Sendable {
        /// The executable and its arguments, passed as written — never through a shell.
        public var command: [String]

        public init(command: [String]) {
            self.command = command
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: AnyCodingKey.self)
            try StrictKeyDecoding.checkUnknownKeys(in: container, allowing: ["command"], decoder: decoder)
            command = try StrictKeyDecoding.required([String].self, forKey: AnyCodingKey("command"), in: container, decoder: decoder, placeholder: [])
        }
    }

    /// One figure a screen draws, named for the oracle, found by the element that carries it, and checked under the windows the oracle computes it for.
    struct Figure: Codable, Equatable, Sendable {
        /// The figure's name as the oracle knows it (`steps-today`); unique within its screen.
        public var id: String
        /// The element carrying the number: an accessibility identifier, matched first, or else a label — whole, or as a pattern whose one `{n}` stands for the figure.
        public var element: String
        /// The window rules the oracle computes the figure under (`midnight`, `rolling24h`): free strings, passed through, which SimWalk never interprets.
        public var windows: [String]

        public init(id: String, element: String, windows: [String]) {
            self.id = id
            self.element = element
            self.windows = windows
        }

        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: AnyCodingKey.self)
            try StrictKeyDecoding.checkUnknownKeys(in: container, allowing: ["id", "element", "windows"], decoder: decoder)
            id = try StrictKeyDecoding.required(String.self, forKey: AnyCodingKey("id"), in: container, decoder: decoder, placeholder: "")
            element = try StrictKeyDecoding.required(String.self, forKey: AnyCodingKey("element"), in: container, decoder: decoder, placeholder: "")
            windows = try StrictKeyDecoding.required([String].self, forKey: AnyCodingKey("windows"), in: container, decoder: decoder, placeholder: [])
        }
    }
}
