//
// Copyright © Agulhas Labs
//

import Foundation

/// What a walk actually did, written to `manifest.json` at the root of a capture bundle (Brief §2.1).
///
/// The manifest is the readable half of the bundle: everything a differ or an oracle needs to know before opening a single image — which walk this was, against which build, on which device, and what the runner can honestly claim about each screen. Timestamps and the build hash arrive as inputs rather than being read from the environment here, so a manifest attests to the run that produced it and a test can produce a byte-identical one.
public struct CaptureManifest: Codable, Equatable, Sendable {
    /// The bundle format this manifest is written in; a reader refuses a version it does not know rather than guessing at the layout.
    ///
    /// **Format 2 is the accessibility tree becoming typed.** Format 1 wrote `{"raw": "<XCUITest's debug dump>"}`; format 2 writes an `AXNode` tree. That is an incompatible change to an artefact — the manifest's own shape is unchanged — and it is exactly the change Brief §2.1 said would not get format 1's "nothing exists to be incompatible with" excuse.
    ///
    /// **Format 3 is the manifest's own vocabulary growing**: a `type` route step, which a `routeTried` may now name, and `ScreenOutcome.stateNotApplied`, which is a verdict an older build has no case for. Both make a new bundle undecodable by an old one, which is the definition of the bump — and the point of taking it is that such a reader refuses by name ("format 3, this build reads 2, 1") instead of reporting a perfectly good manifest as torn.
    ///
    /// **Format 4 is a refusal that keeps what it can (SimWalk#15)**: a `stateNotApplied` screen may now carry the captures of the states it did not refuse, beside a `refusedStates` list naming the ones it did. A format-3 reader would decode that, ignore the list, and report the captures as a refusal contradicting itself — a torn bundle, where the truth is a partial one. The bump makes it refuse by name instead.
    ///
    /// **Format 5 is a verdict an older build has no case for**: `ScreenOutcome.unexpectedScreen`, a screen whose captures are of a different screen than its walkbook `expect`ed. A format-4 reader decoding one fails on the outcome itself and reports a good manifest as torn — exactly what format 3's bump exists to prevent — so this one refuses by name instead ("format 5, this build reads 4, 3, 2, 1").
    ///
    /// **Format 6 is a route step an older build has no case for**: `tapPoint` (SimWalk#29), which a `routeTaken` or `routeTried` may now name. A format-5 reader decoding one fails on the step and reports a good manifest as torn, as format 3's `type` would have — so it refuses by name instead ("format 6, this build reads 5, 4, 3, 2, 1").
    ///
    /// **Format 7 is another such step**: `systemTap` (SimWalk#28), a route's answer to a system permission sheet, which a format-6 reader has no case for — so it refuses by name too.
    ///
    /// **Format 8 is a state's own launch `arguments` and `environment` (SimWalk#44).** Optional and written only when present, but that does not keep them inside format 7 the way `identicalTo` and `device.locale` stayed inside format 4: those sit in containers an older reader decodes leniently and loses nothing by ignoring, where a state decodes *strictly* (SimWalk#10), so a format-7 reader meets `arguments` as an unknown key and reports a good manifest as torn. That is the definition of the bump, so it refuses by name instead ("format 8, this build reads 7, …").
    ///
    /// **Format 9 is three more route steps an older build has no case for** (SimWalk#198): `longPress`, `swipe`, and `type`'s `replace`, which a `routeTaken` or `routeTried` may now name; a format-8 reader would report a good manifest as torn, so it refuses by name instead.
    ///
    /// **Format 10 is a state axis an older build has no key for** (SimWalk#199): `orientation`, which a manifest's `state` carries whole. A state decodes strictly (SimWalk#10), so a format-9 reader meets `orientation` as an unknown key and would report a good manifest as torn; it refuses by name instead ("format 10, this build reads 9, …").
    ///
    /// **Format 11 is another route step an older build has no case for**: `drag` (SimWalk#148), a press-and-drag between two points, which a `routeTaken` or `routeTried` may now name. A format-10 reader would report a good manifest as torn, as format 6's `tapPoint` would have, so it refuses by name instead ("format 11, this build reads 10, …").
    public static let currentFormatVersion = 11
    /// The format in which an accessibility tree became a typed `AXNode` rather than an untyped dump — named rather than assumed to be the current one, so a refusal blaming the old tree shape keeps naming the format that actually replaced it.
    public static let typedTreeFormatVersion = 2
    /// The format in which a `stateNotApplied` screen began naming the states it refused and keeping the rest — named, like `typedTreeFormatVersion`, rather than assumed to be the current one.
    public static let refusedStatesFormatVersion = 4
    /// The format in which a screen could be recorded `unexpectedScreen` — named, like `refusedStatesFormatVersion`, so a record claiming that verdict in an older format is refused as one no walk wrote.
    public static let unexpectedScreenFormatVersion = 5
    /// The formats this build will open, newest first.
    ///
    /// Older formats are **read**, not refused, and the distinction is deliberate. What changed between 1 and 2 is the ax-tree artefact, not the manifest: a format-1 bundle's manifest, screenshots and outcomes are all exactly as true today as they were when it was written, and refusing to open one would take `bundle inspect` away from every bundle already on disk to protect a reader from a file it need not open. Formats 2 to 7 lose nothing at all here — each one's vocabulary is a subset of the next. What must never happen is a reader *pretending* to decode a format-1 tree, and that is refused where it happens — `CaptureBundle.axTree(for:)` names the artefact and the format rather than throwing Foundation's `keyNotFound 'type'` at a caller with no idea which file it meant.
    public static let readableFormatVersions = [11, 10, 9, 8, 7, 6, 5, 4, 3, 2, 1]

    /// The format version of the enclosing bundle.
    public var formatVersion: Int
    /// The walkbook's name, carried through from the plan that was executed.
    public var walkName: String
    /// The bundle identifier of the app that was walked.
    public var appBundleID: String
    /// The build the walk claims to have validated — a capture whose installed app does not match it refuses per screen with `ScreenOutcome.buildMismatch`.
    public var appBuildHash: String
    /// The content hash of the walkbook that was executed, from `WalkbookIdentity` — build-mismatch's counterpart for the plan, so two bundles of "the same walk" can be shown to be exactly that.
    public var walkbookHash: String
    /// The device the walk ran on.
    public var device: Device
    /// When the runner launched the app, rounded to the millisecond the manifest format can carry.
    public private(set) var startedAt: Date
    /// When the runner finished the last screen, rounded to the millisecond the manifest format can carry.
    public private(set) var finishedAt: Date
    /// One entry per screen the walkbook asked for, in walkbook order — including the ones that were refused.
    public var screens: [ScreenRecord]
    /// How long the accessibility tree had to hold still before each capture, in milliseconds; `nil` in a bundle written before the runner recorded it.
    ///
    /// The threshold is the other half of what `StateCapture.axTreeSettled` claims. "The tree had stopped changing" is a statement about a window, and a bundle that does not say which window leaves a reader unable to tell a screen that was genuinely still from one watched for 250ms — which is the whole complaint that produced `--settle` in the first place.
    public var settleQuietMilliseconds: Int?
    /// The commit the XCUITest runner that wrote this bundle was built from — `<sha>`, or `<sha>-dirty…` for a working tree with changes; `nil` when it could not be told or the bundle predates the field.
    ///
    /// The runner is the write half of this format and the CLI the read half, and they are meant to come from one commit (SimWalk#16). A bundle that names its runner is one whose writer can be found again when a reader disagrees with it.
    public var runnerCommit: String?
    /// The settle the walk made after screens refused an appearance the device reported set and did not draw, and the screens it walked again once it held (SimWalk#26); `nil` when there was none.
    ///
    /// **Why the walk took longer, and why a screen's record is its second attempt.** A reboot is tens of seconds and a second pass over the affected screens more, none of which a reader can otherwise account for — and a retried screen's record replaces its first, so without this nothing in the bundle would say that a first attempt existed or what it found.
    ///
    /// **Absent rather than empty, and inside format 5.** A manifest with no settle is byte-for-byte what it was before the field existed, and a format-5 reader that predates it decodes one that has it and reads every screen correctly: the records are the second attempt's, each true of the capture it names, and what that reader misses is the explanation, not a fact about any capture. No bump is taken for a field whose absence cannot make a reader misreport the bundle — the test the format-3, 4 and 5 bumps each met and this does not.
    public var appearanceSettle: AppearanceSettle?
    /// The value this walk's host generated and passed the runner, echoed back — what tells this bundle from one an overlapping walk of the same build left, the way `RouteProbeReport.nonce` tells a dry run's report from one (SimWalk#36, SimWalk#41).
    ///
    /// **Absent rather than empty**, like `appearanceSettle`: a bundle written before this field existed decodes with `nil` here, correctly, and a reader that checks a walk's own bundle back (`WalkCommand.bundleWrittenBy`) refuses one that carries no nonce exactly as it refuses one carrying another walk's — `bundle inspect`, `bundle screen` and `bundle audit` never ask for it, so an old bundle stays fully readable by every other verb. No bump is taken for the same reason `appearanceSettle` took none: its absence cannot make a reader misreport what the bundle holds.
    public var nonce: String?
    /// The walkbook's `setup` as the host made it and handed it back; `nil` when the walkbook had none, or in a bundle written before the field existed.
    ///
    /// Written by the host after the handback (`SetupRecord.write(into:)`), never by the runner — so it is the one field a runner's manifest never carries.
    public var deviceSetup: SetupRecord?
    /// How the walk came to know `appBuildHash`; `nil` means it was read back from the installed app, as every simulator walk does.
    ///
    /// **Absent rather than empty, inside the current format**, like `nonce`: a bundle written before the field decodes with `nil`, which is what it meant, and a reader that predates it still reads every screen correctly. Written by the runner from `SIMWALK_BUILD_PROVENANCE` beside the hash, so the nonce check covers it.
    public var appBuildProvenance: AppBuildProvenance?
    /// Whether the app ran with UIKit animations on or off (SimWalk#154); `nil` in a bundle written before SimWalk recorded it, when every walk ran with them on.
    ///
    /// **Absent rather than empty, and inside format 8.** The manifest's top level decodes leniently, so a format-8 reader that predates the field ignores it and reads every screen correctly; what it misses is which state the figures were taken in, not a fact about any capture. No bump is taken for a field whose absence cannot make a reader misreport the bundle, the test the format-3 to 8 bumps each met and this does not. `bundle diff` reads it through ``recordedAnimations`` and refuses to compare a pair that differ.
    public var animations: Animations?

    /// The state the bundle was captured in: `animations`, or `.on` for a bundle that does not say, since every walk before SimWalk recorded it ran with animations on.
    public var recordedAnimations: Animations {
        animations ?? .enabled
    }

    /// The screens the walkbook asked for that this bundle does not hold, in walkbook order.
    ///
    /// A walk that refuses a screen honestly is still a walk that did not capture it, and the difference matters to anything deciding what to do next rather than reading the report. Empty means the bundle holds everything that was asked for.
    public var shortfall: [ScreenRecord] {
        screens.filter { !$0.outcome.isCaptured }
    }

    /// Every capture taken before the accessibility tree stopped changing — or while it still held only the app's chrome (SimWalk#81) — in manifest order.
    ///
    /// One generator, because three readers want it — the summary calls them out, `walk` gates its exit code on them, and anything deciding whether to trust a bundle asks the same question. A capture whose bundle never recorded settling is not listed: it makes no claim either way, and inventing one would be the dishonesty the flag exists to prevent.
    public var unsettledCaptures: [CaptureReference] {
        screens.flatMap { screen in
            screen.captures
                .filter { $0.axTreeSettled == false }
                .map { CaptureReference(screenID: screen.id, stateSlug: $0.state.slug) }
        }
    }

    /// The unsettled captures whose tree was genuinely still changing: those not already counted as holding only the app's chrome.
    ///
    /// A still spinner is filed unsettled too (SimWalk#81), and a verdict that counted it here and again as chrome-only would state one bare capture as two qualifications; the chrome-only one is the true account of it, since that tree held perfectly still.
    public var movingCaptures: [CaptureReference] {
        screens.flatMap { screen in
            screen.captures
                .filter { $0.axTreeSettled == false && $0.axTreeHasContent != false }
                .map { CaptureReference(screenID: screen.id, stateSlug: $0.state.slug) }
        }
    }

    /// Every capture whose accessibility tree held the app's chrome and nothing else, in manifest order.
    ///
    /// The bundle's second qualification, beside an unsettled capture and read the same way: the artefacts are real and honest, and what they are of is a screen that had not arrived. A capture whose bundle never recorded the check is not listed, for the reason `unsettledCaptures` does not invent an answer either.
    public var chromeOnlyCaptures: [CaptureReference] {
        screens.flatMap { screen in
            screen.captures
                .filter { $0.axTreeHasContent == false }
                .map { CaptureReference(screenID: screen.id, stateSlug: $0.state.slug) }
        }
    }

    /// Every capture that set a state axis its artefacts show nothing to verify by, in manifest order — the third qualification, read like the other two.
    public var unverifiedCaptures: [CaptureReference] {
        screens.flatMap { screen in
            screen.captures
                .filter { $0.unverifiedAxes?.isEmpty == false }
                .map { CaptureReference(screenID: screen.id, stateSlug: $0.state.slug) }
        }
    }

    public init(
        formatVersion: Int = CaptureManifest.currentFormatVersion,
        walkName: String,
        appBundleID: String,
        appBuildHash: String,
        walkbookHash: String,
        device: Device,
        startedAt: Date,
        finishedAt: Date,
        settleQuietMilliseconds: Int? = nil,
        runnerCommit: String? = nil,
        appearanceSettle: AppearanceSettle? = nil,
        nonce: String? = nil,
        appBuildProvenance: AppBuildProvenance? = nil,
        animations: Animations? = nil,
        screens: [ScreenRecord]
    ) {
        self.formatVersion = formatVersion
        self.walkName = walkName
        self.appBundleID = appBundleID
        self.appBuildHash = appBuildHash
        self.walkbookHash = walkbookHash
        self.device = device
        // Rounded on the way in, not on the way out: a manifest that stated more precision than its
        // own format carries would not survive its own round trip.
        self.startedAt = Timestamp.millisecondRounded(startedAt)
        self.finishedAt = Timestamp.millisecondRounded(finishedAt)
        self.settleQuietMilliseconds = settleQuietMilliseconds
        self.runnerCommit = runnerCommit
        self.appearanceSettle = appearanceSettle
        self.nonce = nonce
        self.appBuildProvenance = appBuildProvenance
        self.animations = animations
        self.screens = screens
    }
}

public extension CaptureManifest {
    /// The simulator a walk ran on, named precisely enough that a later run's differences can be attributed to the device rather than to the app.
    struct Device: Codable, Equatable, Sendable {
        /// The device's model name, for example `iPhone 17 Pro`.
        public var name: String
        /// The simulator's UDID — the identity a fleet lease is taken against (Brief §2.4).
        public var udid: String
        /// The OS version the device was running, for example `26.0`.
        public var osVersion: String
        /// The locale the device was already in before the walk, as the host read it; `nil` when it could not be read, named no single locale, or the bundle predates the field.
        ///
        /// What explains a capture recorded `identicalTo` its base: a state asking for the device's own locale draws what the plain state draws (SimWalk#18).
        public var locale: String?

        public init(name: String, udid: String, osVersion: String, locale: String? = nil) {
            self.name = name
            self.udid = udid
            self.osVersion = osVersion
            self.locale = locale
        }
    }

    /// A settle made on the walk's device, and the screens walked again once it held (SimWalk#26).
    ///
    /// The trap it answers: a simulator whose appearance was just switched, or never set at all, can report `dark` from `simctl ui` and go on drawing light until it is rebooted. `StateApplicationCheck` refuses what that draws — correctly, and unrecoverably inside one pass. So the walk sets the device dark, shuts it down, boots it, puts back the appearance it found it in, and walks those screens once more; this is the record of that.
    struct AppearanceSettle: Codable, Equatable, Sendable {
        /// The appearance the device was set to before it was shut down and booted — `dark`, the one sequence measured to cure the trap, whatever the refused states asked for.
        ///
        /// For a settle `declined`, the one it would have been set to.
        public var appearance: Walkbook.Theme
        /// The appearance the walk found the device in: what it was put back to after the boot, or — when it is `appearance` — left in, with nothing switched after the boot.
        public var found: Walkbook.Theme
        /// How long setting it, shutting the device down, booting it and putting its own appearance back took, in milliseconds — not the second pass over the screens, whose time the walk's own timestamps carry.
        public var milliseconds: Int
        /// The screens the settle was made for, in walkbook order, each with what its first attempt recorded — walked again once it held, unless `settleFailure` or `secondPassFailure` says why not.
        public var retried: [Retry]
        /// The step the settle stopped at and what `simctl` said — `nil` when it completed.
        ///
        /// When set, no screen was walked again, and every retried screen's record is its first attempt; the device may have been shut down, which is why it is recorded rather than left to the answer.
        public var settleFailure: String?
        /// Why walking the screens again left nothing that could be folded in, when the settle completed — `nil` when the second attempt was folded.
        ///
        /// When set, every retried screen's record is its first attempt.
        public var secondPassFailure: String?
        /// Why no settle was made at all, and the command that makes it — `nil` when one was attempted (the round-3 review).
        ///
        /// A walk reboots only a device it owns; on any other the refusals stand, and the walk's answer says so — but the answer is transient and the manifest is the record, read a week later by `inspect` on another machine. When set, nothing was rebooted and no screen walked again: `milliseconds` is 0, and every retried screen's record is its first attempt.
        public var declined: Declined?

        public init(
            appearance: Walkbook.Theme,
            found: Walkbook.Theme,
            milliseconds: Int,
            retried: [Retry],
            settleFailure: String? = nil,
            secondPassFailure: String? = nil,
            declined: Declined? = nil
        ) {
            self.appearance = appearance
            self.found = found
            self.milliseconds = milliseconds
            self.retried = retried
            self.settleFailure = settleFailure
            self.secondPassFailure = secondPassFailure
            self.declined = declined
        }

        /// Whether any retried screen's record can be its second attempt — false when the settle was declined, stopped short, or the second pass left nothing to fold.
        public var folded: Bool {
            settleFailure == nil && secondPassFailure == nil && declined == nil
        }
    }

    /// What happened at one screen: the verdict, the route the runner actually walked, and the artefacts it produced.
    ///
    /// `outcome` and `captures` are not redundant. A captured screen has both; a refusal has an outcome that names its evidence and no captures at all, which is what keeps "unreachable" from ever reading as "captured nothing".
    ///
    /// Nor are `routeTaken` and an unreachable outcome's `routeTried`, though their names invite the reading: **completed is not attempted.** The runner that reached the Workouts tab and then failed to find Power completed one step and attempted two, and both are worth recording — how far it got, and what it was reaching for. `CaptureManifestValidator` pins the relationship rather than trusting it, since two unconstrained answers to "what did the runner do" leave a reader unable to tell which is the honest one.
    struct ScreenRecord: Codable, Equatable, Sendable {
        /// The walkbook screen id this record answers.
        public var id: String
        /// The honest verdict for the screen.
        public var outcome: ScreenOutcome
        /// The steps the runner **completed** — shorter than the plan when it gave up part-way, and the leading part of an unreachable outcome's `routeTried`.
        public var routeTaken: [Walkbook.RouteStep]
        /// One entry per state actually captured; empty for a refusal of the whole screen, and the states that were kept for a `stateNotApplied` that refused only some.
        public private(set) var captures: [StateCapture]
        /// The quiet period this screen was captured under when its walkbook entry asked for its own, in milliseconds; `nil` when it ran at the walk's.
        ///
        /// Recorded only where it differs, because the alternative is the walk's own number repeated on every screen line — and the reader's question is not "what was the threshold" but "which screens paid for more than the default". The walk-level `settleQuietMilliseconds` says what the rest ran under.
        public var settleQuietMilliseconds: Int?
        /// The states a state refusal refused, in capture order; `nil` when none were — carried by a `stateNotApplied` verdict, or by an `unexpectedScreen` whose `reason` records a state refusal that held at the same time.
        ///
        /// What lets a bundle say "refused on this device" about a state rather than leaving it absent, which reads as "never reached" (SimWalk#15) — the manifest does not carry the walkbook, so without this a missing dark capture beside a filed light one has no explanation a reader can find. **Absent rather than empty**, so a manifest with no refusal in it is byte-for-byte what it was before the field existed, the way `settleQuietMilliseconds` is.
        public private(set) var refusedStates: [Walkbook.CaptureState]?
        /// The states in `refusedStates` that the appearance check refused — a render that did not show the appearance its state asked for — in capture order; `nil` when none were (SimWalk#26).
        ///
        /// **The reason a walk settles its device, carried as a field rather than read from the refusal's sentence.** A settle reboots the simulator, and it cures one thing: a device that reported an appearance and drew another. A collision over a locale or a Dynamic Type size is refused as well, and a reboot does nothing for it — so the walk keys its settle on this list, never on `refusedStates` alone and never on the wording of the reason. Absent rather than empty, and inside format 5 for the reason `appearanceSettle` is: a reader that predates it reads every record correctly and misses only which refusal was which.
        public private(set) var refusedOnAppearance: [Walkbook.CaptureState]?
        /// The protected resources the runner reset before each launch it made for this screen, one entry per state launched, in launch order; `nil` when no launch reset anything (SimWalk#62 item 2).
        ///
        /// **Written where the runner applies the reset, so it holds for a screen with no captures** — an unreachable one, a capture that failed, a state filing refused — which the captures' own states cannot. **Absent rather than empty**, and inside format 8 for the reason `refusedOnAppearance` stayed inside format 5: a record decodes leniently, so an older reader ignores the key and misses only the disclosure.
        public private(set) var launchResets: [LaunchReset]?
        /// The element each landed `tap`, `scrollTo` and `type` step bound, one entry per such step, in `routeTaken` order; `nil` when the bundle does not record it, `[]` when the route bound nothing (SimWalk#93).
        ///
        /// **A sibling list rather than a field on a `routeTaken` step**, because those decode strictly and a field there would be a format bump; `step` indexes `routeTaken`. **`nil` is an older bundle, not "nothing bound"**: the writer files a list — empty where no step bound an element — so a reader can tell a route that bound nothing from a bundle that never said, as `launchResets` cannot (its absence means no reset). Inside format 8 for the reason `launchResets` is: a record decodes leniently, so an older reader ignores the key.
        public private(set) var boundElements: [BoundElement]?
        /// The device that captured this screen, written only by a parallel walk.
        ///
        /// `nil` in every serial walk, whose one device is ``CaptureManifest/device``, so a serial manifest's JSON is unchanged. Inside format 8 for the reason `launchResets` is: a record decodes leniently, so an older reader ignores the key.
        public var capturedOn: CapturingDevice?
        /// The slugs of the states whose launch left the app landscape on a device held portrait, so the runner turned the device to match (SimWalk#222); `nil` when none did.
        ///
        /// **Absent rather than empty**, and inside format 11 for the reason `launchResets` is inside format 8: a record decodes leniently, so an older reader ignores the key and misses only the disclosure.
        public var deviceTurns: [String]?
        /// The appearance the walkbook fixed for this screen (SimWalk#19), so the walk's line can say light and dark were not compared; `nil` when it fixed none.
        ///
        /// **Absent rather than empty**, and inside format 11 for the reason `deviceTurns` is: a record decodes leniently, so an older reader ignores the key and misses only the disclosure.
        public var fixedAppearance: Walkbook.Theme?

        public init(
            id: String,
            outcome: ScreenOutcome,
            routeTaken: [Walkbook.RouteStep],
            captures: [StateCapture] = [],
            settleQuietMilliseconds: Int? = nil,
            refusedStates: [Walkbook.CaptureState] = [],
            refusedOnAppearance: [Walkbook.CaptureState] = [],
            launchResets: [LaunchReset] = [],
            boundElements: [BoundElement]? = nil,
            deviceTurns: [String] = [],
            fixedAppearance: Walkbook.Theme? = nil
        ) {
            self.id = id
            self.outcome = outcome
            self.routeTaken = routeTaken
            self.captures = captures
            self.settleQuietMilliseconds = settleQuietMilliseconds
            self.refusedStates = refusedStates.isEmpty ? nil : refusedStates
            self.refusedOnAppearance = refusedOnAppearance.isEmpty ? nil : refusedOnAppearance
            self.launchResets = launchResets.isEmpty ? nil : launchResets
            self.boundElements = boundElements
            self.deviceTurns = deviceTurns.isEmpty ? nil : deviceTurns
            self.fixedAppearance = fixedAppearance
        }

        /// A record as the runner files it: `launchResets`, `boundElements` and `deviceTurns` have **no default**, so the runner cannot omit them (SimWalk#91 item 6, SimWalk#93).
        ///
        /// The runner has no unit tests, and `init` defaults `launchResets` to empty for the many tests that have none to give, so deleting the runner's argument left `swift test` green while every screen's reset disclosure vanished from the bundle. Every record the runner builds goes through here, so deleting the argument stops the runner compiling.
        public static func filed(
            id: String,
            outcome: ScreenOutcome,
            routeTaken: [Walkbook.RouteStep],
            captures: [StateCapture] = [],
            settleQuietMilliseconds: Int?,
            refusedStates: [Walkbook.CaptureState] = [],
            refusedOnAppearance: [Walkbook.CaptureState] = [],
            launches: Launches,
            boundElements: [BoundElement],
            fixedAppearance: Walkbook.Theme? = nil
        ) -> ScreenRecord {
            ScreenRecord(
                id: id,
                outcome: outcome,
                routeTaken: routeTaken,
                captures: captures,
                settleQuietMilliseconds: settleQuietMilliseconds,
                refusedStates: refusedStates,
                refusedOnAppearance: refusedOnAppearance,
                launchResets: launches.resets,
                boundElements: boundElements,
                deviceTurns: launches.deviceTurns,
                fixedAppearance: fixedAppearance
            )
        }
    }

    /// The device a parallel walk captured a screen on, named and identified as the walk listed it.
    struct CapturingDevice: Codable, Equatable, Sendable {
        public var name: String
        public var udid: String

        public init(name: String, udid: String) {
            self.name = name
            self.udid = udid
        }
    }

    /// The element a landed `tap`, `scrollTo` or `type` step bound: what the runner chose among the screen's matches for the label (SimWalk#93).
    struct BoundElement: Codable, Equatable, Sendable {
        /// The step's index in the record's `routeTaken`.
        public var step: Int
        /// The element's type, as `AXNode.type` names it.
        public var type: String
        public var identifier: String?
        public var label: String?
        /// Where the snapshot the choice was made from had it.
        public var frame: AXNode.Frame

        public init(step: Int, type: String, identifier: String?, label: String?, frame: AXNode.Frame) {
            self.step = step
            self.type = type
            self.identifier = identifier
            self.label = label
            self.frame = frame
        }

        public init(step: Int, node: AXNode) {
            self.init(step: step, type: node.type, identifier: node.identifier, label: node.label, frame: node.frame)
        }
    }

    /// The resources the runner reset before launching the app for one state.
    struct LaunchReset: Codable, Equatable, Sendable {
        /// The slug of the state whose launch it was.
        public var state: String
        /// The `ProtectedResourceName` raw values reset, in that enum's order.
        public var resources: [String]

        public init(state: String, resources: [String]) {
            self.state = state
            self.resources = resources
        }
    }

    /// What the runner saw of a screen settling between the route's last step landing and its capture, at the resolution it read at (SimWalk#67, M1).
    ///
    /// **Figures the watch already paid for.** `SettleTracker` reads the tree every `SettleWindow.interval` until the screen holds still, and this keeps two facts about those reads instead of throwing them away: when the tree last changed, and how many reads it took. **The cadence is recorded beside them because it is their resolution**: a change that comes and goes between two reads is never seen, and neither is an animation the tree cannot see — a chart drawing in, a cross-fade — the blind spot `axTreeSettled` documents. A settle time is "the tree stopped changing by then, to within one interval", never "the screen stopped moving then".
    ///
    /// **M2 adds what the reads showed moving** (SimWalk#67): the layout shifts `LayoutShiftRule` finds between them, the reads' measured spacing beside the pause, and how long the route's last step took to land. Every M2 key is optional and absent from an M1 record, so it stays inside format 8 for M1's reason: a reader that predates a key ignores it.
    struct Motion: Codable, Equatable, Sendable {
        /// How far into the capture's watch the tree took the form it was captured in, in milliseconds: the last read that differed from the one before it, or the first read when none did (`SettleTracker.settleTime`).
        ///
        /// The watch opens once the route's last step has landed, or, for a screen with no route, once the launch has returned, so this is time after the landing, not after the touch. Each read is timed as it returns, so the figure includes one read's own cost (5–40 ms measured): a screen that never changed records that, not 0.
        ///
        /// **Absent when the watch ran out of budget unsettled** (`axTreeSettled: false`): a screen that never held still has no settle time, and the last change seen before the budget ran out would read as a measured settle where the measurement is that there was none. The cadence and the read count are still recorded.
        public var settleMilliseconds: Int?
        /// How long the runner paused between two reads, in milliseconds (`SettleWindow.interval`) — the resolution of `settleMilliseconds`.
        ///
        /// The reads are at least this far apart: each one's own cost comes on top, which `measuredReadSpacingMilliseconds` records.
        public var readIntervalMilliseconds: Int
        /// How many reads the watch compared, the one bracketing the picture included; an unsettled capture's own last read, taken after the watch gave up, is not among them.
        public var readCount: Int
        /// How far apart the watch's reads actually were, in milliseconds: the **median** gap between consecutive reads (SimWalk#92 item 9); absent with fewer than two reads, and in a record from before M2.
        ///
        /// `readIntervalMilliseconds` is only the pause, and each read's own cost comes on top, so this is the resolution the settle time and the shifts were really read at. **The median rather than the mean** because the gaps are not alike: the read that brackets the picture follows the screenshot with no pause, and one slow read (a snapshot of a busy tree) is a single long gap. A watch is a handful of reads, so either would drag a mean away from the spacing nearly every other pair of reads had; the median is that spacing.
        public var measuredReadSpacingMilliseconds: Int?
        /// How long the route's last step took to land, in milliseconds: from the moment its action returned (the tap delivered, the URL handed over) to the first read that showed the screen it was taken on had been left.
        ///
        /// **It times the start of an arrival, not its end**: that read is the first structural change (`ScreenIdentity` finding the screen left), so for a push it is when the new screen starts to arrive, not when its slide finishes.
        ///
        /// **Absent for a screen with no route, and for a last step that does not wait for arrival** — a `type`, a `scrollTo`, a `tapPoint` or a `drag` (which wait a fixed quiet period), a `systemTap`, or a `tab` already selected — since none of them has an arrival to time. Measured in the step's own reads, `StepPerformer.settleInterval` apart, each read's cost included; the clock starts when XCUITest's action returns, so time the action spent waiting for the app to go idle is not in it.
        public var landingMilliseconds: Int?
        /// The layout shifts the watch saw, in the order seen (`LayoutShiftRule`): an empty list is a watch that saw none, and **absent is "not recorded"** — a record from before M2 — never "no shifts".
        public var shifts: [Shift]?

        public init(
            settleMilliseconds: Int?,
            readIntervalMilliseconds: Int,
            readCount: Int,
            measuredReadSpacingMilliseconds: Int? = nil,
            landingMilliseconds: Int? = nil,
            shifts: [Shift]? = nil
        ) {
            self.settleMilliseconds = settleMilliseconds
            self.readIntervalMilliseconds = readIntervalMilliseconds
            self.readCount = readCount
            self.measuredReadSpacingMilliseconds = measuredReadSpacingMilliseconds
            self.landingMilliseconds = landingMilliseconds
            self.shifts = shifts
        }

        /// The record of `tracker`'s watch, whose reads `fold` has seen, read every `interval` after the landing `watch` names, each figure rounded to the millisecond.
        public init(of tracker: SettleTracker, interval: TimeInterval, fold: LayoutShiftRule.Fold, watch: MotionWatch) {
            let gaps = fold.gaps.sorted()
            let median = gaps.isEmpty ? nil : (gaps[(gaps.count - 1) / 2] + gaps[gaps.count / 2]) / 2
            self.init(
                settleMilliseconds: tracker.settleTime.map(Self.milliseconds),
                readIntervalMilliseconds: Self.milliseconds(interval),
                readCount: tracker.reads,
                measuredReadSpacingMilliseconds: median.map(Self.milliseconds),
                landingMilliseconds: watch.landing.map(Self.milliseconds),
                shifts: fold.shifts
            )
        }

        private static func milliseconds(_ seconds: TimeInterval) -> Int {
            Int((seconds * 1000).rounded())
        }
    }

    /// One state of one screen, and where its two artefacts live inside the bundle.
    struct StateCapture: Codable, Equatable, Sendable {
        /// The state that was requested and captured.
        public private(set) var state: Walkbook.CaptureState
        /// The screenshot — the viewport the tree is rooted at, not a stitched full-scroll image — as a bundle-relative path; derived, never assignable from outside the module.
        public private(set) var screenshotPath: String
        /// The accessibility tree with text runs and frames, as a bundle-relative path — derived, never assignable from outside the module.
        public private(set) var axTreePath: String
        /// Whether the **accessibility tree** had stopped changing when this was captured; `nil` in a bundle written before the runner recorded it.
        ///
        /// The one thing a reader otherwise cannot recover. A card that is still populating captures with its heading drawn and its body empty, and the artefacts are then perfectly consistent with each other and perfectly wrong about the screen — the reviewer who met this could not tell a capture race from an app bug, which is the honesty contract failing rather than a missing convenience. `false` does not mean the capture is worthless; it means read it knowing the tree was still moving.
        ///
        /// **The name states exactly what was measured, and the narrower claim is the true one.** This was `settled`, which reads as "the screen had stopped" — a claim nothing in the runner makes. Settling is decided by two identical `AXNode` trees, so every animation the tree cannot see settles instantly: a chart drawing in, a cross-fade, a shimmer, an image decoding into a frame that was already the right size. `true` therefore means the hierarchy was stable, never that the picture was. Comparing screenshot bytes instead was considered and rejected: the status-bar clock alone makes two shots of a motionless screen differ, so a byte comparison would report a still screen as unsettled at every minute boundary — a false alarm generator on a flag that now moves an exit code.
        ///
        /// **From the build that added `SettleTracker`, `true` also means the two artefacts are of one hierarchy** — the screenshot is taken between two reads and kept only if they match, so a settled capture's picture and tree cannot be of different screens (SimWalk#4). `false` is where that guarantee is absent as well as the stillness, which is what it has always been shorthand for; a bundle written before this carries the weaker `true`, and the manifest cannot tell a reader which it holds.
        ///
        /// **From SimWalk#81, `true` also means the tree held more than the app's chrome** — a still spinner is waited on rather than settled on, and one still bare when `SettleWindow.contentWait` runs out is filed `false`, so a capture `axTreeHasContent: false` names is never counted settled beside it.
        public private(set) var axTreeSettled: Bool?
        /// Whether the accessibility tree held anything but the app's chrome; `nil` in a bundle written before the runner recorded it.
        ///
        /// `false` is a capture of a screen that had not arrived — a spinner inside a tab bar, filed under a screen id and perfectly still while it loaded. It is a qualification and not a refusal: the artefacts are honest, and what they are of is the load rather than the screen. `ScreenContentCheck` is where "content" is decided.
        public private(set) var axTreeHasContent: Bool?
        /// The slug of the state on the same screen whose screenshot this one is byte-identical to, when that is the right result rather than a discard; `nil` otherwise.
        ///
        /// Set where the device was already in the conditions this state asked for — `light-loc_en_gb` on a device in `en_GB` draws what `light` draws (SimWalk#18). Applied, and identical to its base: filed and said so, where the identity rule used to refuse both. **Absent rather than empty**, like every optional field here.
        public private(set) var identicalTo: String?
        /// The state axes this capture set that its artefacts show nothing to verify by — `layoutDirection` on a screen with no horizontal run, `location` on one that never shows the coordinate, `orientation` on one whose root frame is square or empty — by their walkbook keys; absent when every axis it set was verified or none needed it.
        ///
        /// A qualification, not a refusal: the axis was set, and nothing here can say it did not take — only that the capture cannot show it did.
        public private(set) var unverifiedAxes: [String]?
        /// When this state was read — the moment its picture was taken — rounded to the millisecond like `startedAt`; `nil` in a bundle written before the field existed.
        ///
        /// Carried by the runner from the settled read (`SettledCapture.takenAfter`), not the moment the artefacts were filed: the runner files every state of a screen together after the last is read, and a state read before midnight stamped when its siblings' relaunches were done would be checked against the next day's windows. `CaptureBundleWriter` stamps the moment it prepared the state's directory only onto a capture that arrives without one. It is what a value oracle computes a rolling window back from, so an oracle check refuses a bundle without it rather than guessing (`OracleCheckError.noCaptureTime`). Optional and written only when present, and a capture decodes leniently, so it stays inside format 8 as `identicalTo` stayed inside format 4.
        public private(set) var capturedAt: Date?
        /// What the runner saw of the screen settling before this capture, with the cadence it read at; `nil` where the walk did not ask for it.
        ///
        /// **Recorded only when asked for** — a screen's `"motion": true`, or a walk's `--motion` (`MotionOptIn`) — so absent means "motion not recorded", never "no motion". **Inside format 8**, as `capturedAt` is: a capture decodes leniently, so a reader that predates it ignores the key and loses only the record, the rule that kept `ScreenRecord.launchResets` inside format 8.
        public private(set) var motion: Motion?
        /// What XCTest measured of this screen's route on a physical device, from launches of their own (`Performance`); `nil` where the walk did not ask for it or ran on a simulator.
        ///
        /// **Recorded only when asked for** — a screen's `"measure"` or a performance budget (`MeasureOptIn`) — and only by a device walk, so absent means "not measured", never "no cost". Inside format 8, as `motion` is.
        public private(set) var performance: Performance?
        /// Where this state's Apple accessibility audit record is, and what it came to (`AppleAuditRecord`); `nil` where the walk did not audit.
        ///
        /// **Recorded only when asked for** — the walkbook's `"appleAudit": true`, or `--apple-audit` (`AppleAuditOptIn`) — so absent means "not audited", never "clean". **Inside format 8, no bump**, as `capturedAt` and `motion` are: a capture decodes leniently, so a reader that predates it ignores the key and loses only the record.
        public private(set) var appleAudit: AppleAuditEntry?

        /// Deliberately **not public**, so the bundle-path rule cannot be bypassed by restating a path — a caller outside the module gets only the layout-deriving initialiser below.
        ///
        /// Decoding does not route through here, so a manifest read off disk is unaffected.
        init(
            state: Walkbook.CaptureState,
            screenshotPath: String,
            axTreePath: String,
            axTreeSettled: Bool? = nil,
            axTreeHasContent: Bool? = nil,
            identicalTo: String? = nil,
            unverifiedAxes: [String]? = nil,
            capturedAt: Date? = nil,
            motion: Motion? = nil,
            performance: Performance? = nil,
            appleAudit: AppleAuditEntry? = nil
        ) {
            self.capturedAt = capturedAt.map(Timestamp.millisecondRounded)
            self.state = state
            self.screenshotPath = screenshotPath
            self.axTreePath = axTreePath
            self.axTreeSettled = axTreeSettled
            self.axTreeHasContent = axTreeHasContent
            self.identicalTo = identicalTo
            self.unverifiedAxes = unverifiedAxes
            self.motion = motion
            self.performance = performance
            self.appleAudit = appleAudit
        }

        /// Builds the record for a captured state with both paths derived from `CaptureBundleLayout`, so a writer cannot invent a path a reader will not look in.
        public init(
            screenID: String,
            state: Walkbook.CaptureState,
            axTreeSettled: Bool? = nil,
            axTreeHasContent: Bool? = nil,
            identicalTo: String? = nil,
            unverifiedAxes: [String]? = nil,
            capturedAt: Date? = nil,
            motion: Motion? = nil,
            performance: Performance? = nil,
            appleAudit: AppleAuditRecord? = nil
        ) {
            self.capturedAt = capturedAt.map(Timestamp.millisecondRounded)
            self.state = state
            screenshotPath = CaptureBundleLayout.screenshotPath(screenID: screenID, stateSlug: state.slug)
            axTreePath = CaptureBundleLayout.axTreePath(screenID: screenID, stateSlug: state.slug)
            self.axTreeSettled = axTreeSettled
            self.axTreeHasContent = axTreeHasContent
            self.identicalTo = identicalTo
            self.unverifiedAxes = unverifiedAxes?.isEmpty == true ? nil : unverifiedAxes
            self.motion = motion
            self.performance = performance
            self.appleAudit = appleAudit.map { AppleAuditEntry(screenID: screenID, stateSlug: state.slug, record: $0) }
        }

        /// Reads `axTreeSettled` under either spelling, because format 1 wrote it as `settled`.
        ///
        /// Dropping the old key would silently turn a recorded `false` into "never recorded" on every bundle already on disk — the flag reading as absent rather than as the warning it is, which is a worse outcome than the imprecise name it was renamed away from.
        public init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            state = try container.decode(Walkbook.CaptureState.self, forKey: .state)
            screenshotPath = try container.decode(String.self, forKey: .screenshotPath)
            axTreePath = try container.decode(String.self, forKey: .axTreePath)
            if let recorded = try container.decodeIfPresent(Bool.self, forKey: .axTreeSettled) {
                axTreeSettled = recorded
            } else {
                axTreeSettled = try decoder.container(keyedBy: LegacyCodingKeys.self).decodeIfPresent(Bool.self, forKey: .settled)
            }
            axTreeHasContent = try container.decodeIfPresent(Bool.self, forKey: .axTreeHasContent)
            identicalTo = try container.decodeIfPresent(String.self, forKey: .identicalTo)
            unverifiedAxes = try container.decodeIfPresent([String].self, forKey: .unverifiedAxes)
            capturedAt = try container.decodeIfPresent(Date.self, forKey: .capturedAt)
            motion = try container.decodeIfPresent(Motion.self, forKey: .motion)
            performance = try container.decodeIfPresent(Performance.self, forKey: .performance)
            appleAudit = try container.decodeIfPresent(AppleAuditEntry.self, forKey: .appleAudit)
        }

        /// This record with `capturedAt` set, unless it already carries one — how `CaptureBundleWriter.finalise` stamps, as a fallback, a capture that arrived without its read time.
        func stamped(capturedAt time: Date?) -> Self {
            guard capturedAt == nil, let time else { return self }
            var stamped = self
            stamped.capturedAt = Timestamp.millisecondRounded(time)
            return stamped
        }
    }

    /// One capture, named by the two things that locate it in a bundle.
    ///
    /// Shared by every list of captures a reader is pointed at — the ones taken before the tree stopped changing, and the ones holding nothing but chrome. One shape rather than one per qualification, because "which capture" is the same question each time and two structs answering it identically is two places for a screen id to be spelled.
    struct CaptureReference: Equatable, Sendable {
        public let screenID: String
        public let stateSlug: String

        public init(screenID: String, stateSlug: String) {
            self.screenID = screenID
            self.stateSlug = stateSlug
        }
    }
}

extension CaptureManifest.StateCapture {
    /// Declared rather than synthesised, because the format-1 fallback in `init(from:)` needs a container to fall back *from*.
    enum CodingKeys: String, CodingKey {
        case state
        case screenshotPath
        case axTreePath
        case axTreeSettled
        case axTreeHasContent
        case identicalTo
        case unverifiedAxes
        case capturedAt
        case motion
        case performance
        case appleAudit
    }

    /// Format 1's spelling, read but never written.
    enum LegacyCodingKeys: String, CodingKey {
        case settled
    }
}

public extension CaptureManifest.AppearanceSettle {
    /// One screen walked again after the settle, and what its first attempt recorded — the only place that attempt survives, since the screen's own record is now the second one's.
    struct Retry: Codable, Equatable, Sendable {
        /// The walkbook screen id walked again.
        public var id: String
        /// The verdict the first attempt recorded, reason and all — why the screen was walked again.
        public var firstOutcome: ScreenOutcome
        /// The states the first attempt refused.
        public var firstRefusedStates: [Walkbook.CaptureState]
        /// Those of `firstRefusedStates` the appearance check refused — the refusals that caused the settle, which the screen's own `refusedOnAppearance` stops saying once its record is replaced (the round-2 review).
        public var firstRefusedOnAppearance: [Walkbook.CaptureState]
        /// Why this screen's second attempt was not taken — it kept less than the first did — so its record is still the first attempt; `nil` when it was taken, or when no second attempt was folded at all (the settle's own `settleFailure` or `secondPassFailure` says why).
        public var notFolded: String?

        public init(
            id: String,
            firstOutcome: ScreenOutcome,
            firstRefusedStates: [Walkbook.CaptureState],
            firstRefusedOnAppearance: [Walkbook.CaptureState],
            notFolded: String? = nil
        ) {
            self.id = id
            self.firstOutcome = firstOutcome
            self.firstRefusedStates = firstRefusedStates
            self.firstRefusedOnAppearance = firstRefusedOnAppearance
            self.notFolded = notFolded
        }
    }

    /// A settle the walk did not make, why, and how a person makes it.
    struct Declined: Codable, Equatable, Sendable {
        /// Why the walk did not make it — the device was not the walk's to reboot.
        public var reason: String
        /// The settle as a person runs it on the walk's device, before walking again.
        public var command: String

        public init(reason: String, command: String) {
            self.reason = reason
            self.command = command
        }
    }
}

extension CaptureManifest {
    /// This manifest with every capture that carries no `capturedAt` stamped with `time(screenID, stateSlug)`, where that has one.
    func stampingCaptureTimes(_ time: (String, String) -> Date?) -> CaptureManifest {
        var stamped = self
        stamped.screens = screens.map { screen in
            screen.stampingCaptureTimes { time(screen.id, $0) }
        }
        return stamped
    }
}

public extension CaptureManifest.ScreenRecord {
    /// What a screen's launches did to the device, both required of the runner's `filed` (one argument, so the factory stays within the parameter limit): the permission resets they applied and the states whose launch turned the device to the app (SimWalk#222).
    struct Launches: Equatable, Sendable {
        public let resets: [CaptureManifest.LaunchReset]
        public let deviceTurns: [String]

        public init(resets: [CaptureManifest.LaunchReset], deviceTurns: [String]) {
            self.resets = resets
            self.deviceTurns = deviceTurns
        }
    }
}

extension CaptureManifest.ScreenRecord {
    /// This record with each capture stamped by `time(stateSlug)` — here, beside `captures`' private setter.
    func stampingCaptureTimes(_ time: (String) -> Date?) -> Self {
        var stamped = self
        stamped.captures = captures.map { $0.stamped(capturedAt: time($0.state.slug)) }
        return stamped
    }
}

public extension CaptureManifest.Motion {
    /// One element displaced between two of the watch's reads, and what displaced it.
    struct Shift: Codable, Equatable, Sendable {
        /// The element that moved, as the later read holds it.
        public var element: Element
        /// Its box in the earlier read, in points.
        public var before: AXNode.Frame
        /// Its box in the later read.
        public var after: AXNode.Frame
        /// How far into the watch the later read was taken, in milliseconds: when the move was seen, to within one read.
        public var movedAtMilliseconds: Int
        /// The change that most likely displaced it; absent where none is named.
        ///
        /// `LayoutShiftRule` reports a move only with one, so every M2 shift carries it; the field is optional so a rule that one day reports a move without a cause in the tree can say so without a format change.
        public var cause: Cause?

        public init(element: Element, before: AXNode.Frame, after: AXNode.Frame, movedAtMilliseconds: Int, cause: Cause?) {
            self.element = element
            self.before = before
            self.after = after
            self.movedAtMilliseconds = movedAtMilliseconds
            self.cause = cause
        }
    }

    /// An element of a read, named the ways a reader can find it again: its type, identifier and label, and its tree path — the child index at each level below the app's root.
    struct Element: Codable, Equatable, Sendable {
        public var type: String
        public var identifier: String?
        public var label: String?
        /// In the read the element is in: the later one, or the earlier for one removed.
        public var path: [Int]
        /// The name of the nearest named ancestor other than the app's root, for an element with no name of its own.
        ///
        /// It lets a reader place the element. Absent when the element is named or no such ancestor exists, and in a manifest written before it.
        public var within: String?

        public init(type: String, identifier: String?, label: String?, path: [Int], within: String? = nil) {
            self.type = type
            self.identifier = identifier
            self.label = label
            self.path = path
            self.within = within
        }
    }

    /// What displaced a shifted element: another element inserted, removed or resized on its line of motion.
    struct Cause: Codable, Equatable, Sendable {
        public var change: Change
        public var element: Element

        public init(change: Change, element: Element) {
            self.change = change
            self.element = element
        }
    }
}

public extension CaptureManifest.Motion.Cause {
    /// How the tree changed.
    enum Change: String, Codable, Equatable, Sendable {
        case inserted
        case removed
        case resized
    }
}

public extension CaptureManifest {
    /// How a manifest's `appBuildHash` was known, when it was not read back from the installed app.
    enum AppBuildProvenance: String, Codable, Equatable, Sendable {
        /// The host hashed the `.app` on the Mac and installed it (`device walk --app`); the phone's copy was not read back.
        case installed
    }
}

public extension CaptureManifest {
    /// The animation state of the app under walk.
    enum Animations: String, Codable, Equatable, Sendable {
        case enabled = "on"
        case disabled = "off"
    }
}
