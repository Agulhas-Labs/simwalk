//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// Both CLI faces print what these render, so the refusals must survive the rendering — a summary that reported only counts would hide exactly what the bundle exists to state.
struct SummaryRenderingTests {
    @Test
    func aBundleSummaryNamesTheRouteAnUnreachableScreenTried() {
        let bundle = CaptureBundle(url: URL(fileURLWithPath: "/tmp/example.simwalk"), manifest: CaptureBundleTests.manifest())

        let rendered = CaptureBundleSummary(bundle).render()

        #expect(rendered.contains("power-detail — UNREACHABLE, route tried: tab 'Workouts' → tap 'Power'"))
    }

    /// `routeTaken` was recorded by every walk and printed by nothing, so how a captured screen was reached — and how far an unreachable one got before it gave up — were facts the bundle held and no reader ever saw.
    @Test
    func aBundleSummaryNamesTheRouteEachScreenActuallyWalked() {
        let bundle = CaptureBundle(url: URL(fileURLWithPath: "/tmp/example.simwalk"), manifest: CaptureBundleTests.manifest())

        let rendered = CaptureBundleSummary(bundle).render()

        #expect(rendered.contains("today — captured [light, dark] via tab 'Today'"))
        #expect(rendered.contains("route tried: tab 'Workouts' → tap 'Power'; completed: tab 'Workouts'"))
    }

    /// **A screen a snapshot-blind `systemTap` could not reach is its own qualification** (SimWalk#48, #55 item 2), so a reader of the verdict can tell it from a missing control without reading the screen's line.
    @Test
    func aSnapshotBlindScreenIsNamedApartFromAnUnreachableOne() {
        var manifest = CaptureBundleTests.manifest()
        manifest.screens.append(CaptureManifest.ScreenRecord(
            id: "health-access",
            outcome: .unreachable(routeTried: [.systemTap(label: "Allow")], reason: "a 'Allow' is on screen and reachable", cause: .snapshotBlind),
            routeTaken: []
        ))
        let bundle = CaptureBundle(url: URL(fileURLWithPath: "/tmp/example.simwalk"), manifest: manifest)

        let rendered = CaptureBundleSummary(bundle).render()

        #expect(rendered.contains("qualified — 1 screen unreachable; 1 screen unreachable behind a system sheet the app's snapshot cannot see; 1 screen refused on a build mismatch · 1 of 4 screens captured"))
    }

    @Test
    func aBundleSummaryNamesBothHashesOfABuildMismatch() {
        let bundle = CaptureBundle(url: URL(fileURLWithPath: "/tmp/example.simwalk"), manifest: CaptureBundleTests.manifest())

        let rendered = CaptureBundleSummary(bundle).render()

        #expect(rendered.contains("sleep-detail — REFUSED, build mismatch: expected a1b2c3d4, found 58ebbd24"))
    }

    @Test
    func aBundleSummaryTalliesOutcomesSeparatelyRatherThanAsOneScreenCount() {
        let bundle = CaptureBundle(url: URL(fileURLWithPath: "/tmp/example.simwalk"), manifest: CaptureBundleTests.manifest())

        let rendered = CaptureBundleSummary(bundle).render()

        #expect(rendered.contains("qualified — 1 screen unreachable; 1 screen refused on a build mismatch · 1 of 3 screens captured · 2 captures"))
        // The outcomes that did not happen are not printed at all: the old tally spelled out two zeroes
        // here on every walk, and a heading over nothing is the thing the contract's third rule forbids.
        #expect(!rendered.contains("capture-failed"))
        #expect(!rendered.contains("state-not-applied"))
    }

    /// "Reached and could not record it" is a fact about the tool; "could not get there" is a fact about the app.
    ///
    /// A summary that renders them alike sends someone to read a route that was walked perfectly well.
    @Test
    func aCaptureFailureNamesItsReasonAndWhatItDidManageToRecord() {
        var manifest = CaptureBundleTests.manifest()
        manifest.screens = [
            CaptureManifest.ScreenRecord(
                id: "today",
                outcome: .captureFailed(reason: "state 'dark': no space left on device"),
                routeTaken: [.tab(label: "Today")],
                captures: [CaptureManifest.StateCapture(screenID: "today", state: Walkbook.CaptureState(theme: .light))]
            ),
        ]
        let bundle = CaptureBundle(url: URL(fileURLWithPath: "/tmp/example.simwalk"), manifest: manifest)

        let rendered = CaptureBundleSummary(bundle).render()

        #expect(rendered.contains("qualified — 1 screen that failed mid-capture · 0 of 1 screens captured · 1 capture"))
        #expect(rendered.contains("today — CAPTURE FAILED after [light], via tab 'Today': state 'dark': no space left on device"))
        #expect(!rendered.contains("UNREACHABLE"))
    }

    /// A screen refused because its states cannot all have applied was *reached and drawn* — it is a refusal, not a shortfall of navigation, and the line has to name which states collided or a reader cannot act on it.
    @Test
    func astateThatNeverAppliedIsRenderedAsARefusalNamingTheStates() {
        var manifest = CaptureBundleTests.manifest()
        manifest.screens = [
            CaptureManifest.ScreenRecord(
                id: "browse",
                outcome: .stateNotApplied(reason: "states 'light' and 'dark' produced byte-identical screenshots"),
                routeTaken: [.tab(label: "Browse")]
            ),
        ]
        let bundle = CaptureBundle(url: URL(fileURLWithPath: "/tmp/example.simwalk"), manifest: manifest)

        let rendered = CaptureBundleSummary(bundle).render()

        #expect(rendered.contains("qualified — 1 screen refused, state not applied · 0 of 1 screens captured · 0 captures"))
        #expect(rendered.contains("browse — REFUSED, state not applied, via tab 'Browse': states 'light' and 'dark' produced byte-identical screenshots"))
        #expect(!rendered.contains("UNREACHABLE"))
    }

    /// A screen that landed on the wrong screen was also *reached and drawn* — every state it captured is printed, because the wrong screenshot is exactly the evidence a reader needs to see, and it is never counted as captured however much of it filed cleanly.
    @Test
    func ascreenThatDidNotMatchWhatWasExpectedNamesWhatItFoundInstead() {
        var manifest = CaptureBundleTests.manifest()
        manifest.screens = [
            CaptureManifest.ScreenRecord(
                id: "activity-detail",
                outcome: .unexpectedScreen(expected: "activity-detail-root", found: ["workouts-list-root", nil]),
                routeTaken: [.tab(label: "Activity")],
                captures: [CaptureManifest.StateCapture(screenID: "activity-detail", state: Walkbook.CaptureState(theme: .light))]
            ),
        ]
        let bundle = CaptureBundle(url: URL(fileURLWithPath: "/tmp/example.simwalk"), manifest: manifest)

        let rendered = CaptureBundleSummary(bundle).render()

        #expect(rendered.contains("qualified — 1 screen not the screen its walkbook expected · 0 of 1 screens captured · 1 capture"))
        #expect(rendered.contains(
            "activity-detail — REFUSED, expected 'activity-detail-root', found [workouts-list-root, no identifier] among the states it took (captured [light]), via tab 'Activity'"
        ))
        #expect(!rendered.contains("UNREACHABLE"))
    }

    /// Round 3, finding 5: `found` covers every state the screen took, refused ones included, so the line names that same set — naming only the kept `light` pinned a refused `dark` state's identifier on it.
    @Test
    func aWrongScreenLineNamesTheRefusedStatesItsFoundListCovers() {
        var manifest = CaptureBundleTests.manifest()
        manifest.screens = [
            CaptureManifest.ScreenRecord(
                id: "progress",
                outcome: .unexpectedScreen(expected: "progress-root", found: ["workouts-list-root"], reason: "state 'dark' is no darker than 'light'"),
                routeTaken: [.tab(label: "Progress")],
                captures: [CaptureManifest.StateCapture(screenID: "progress", state: Walkbook.CaptureState(theme: .light))],
                refusedStates: [Walkbook.CaptureState(theme: .dark)]
            ),
        ]
        let bundle = CaptureBundle(url: URL(fileURLWithPath: "/tmp/example.simwalk"), manifest: manifest)

        let rendered = CaptureBundleSummary(bundle).render()

        #expect(rendered.contains(
            "progress — REFUSED, expected 'progress-root', found [workouts-list-root] among the states it took (captured [light]; refused [dark]), via tab 'Progress' — state 'dark' is no darker than 'light'"
        ))
    }

    /// After a write failure the states taken are in neither list, so the line states no count at all rather than "among 0 captured states" beside the identifiers those states produced.
    @Test
    func aWrongScreenWhoseWriteFailedClaimsNoCountOfStates() {
        var manifest = CaptureBundleTests.manifest()
        manifest.screens = [
            CaptureManifest.ScreenRecord(
                id: "progress",
                outcome: .unexpectedScreen(expected: "progress-root", found: ["workouts-list-root"], reason: "The states it kept could not be filed: disk full"),
                routeTaken: [.tab(label: "Progress")]
            ),
        ]
        let bundle = CaptureBundle(url: URL(fileURLWithPath: "/tmp/example.simwalk"), manifest: manifest)

        let rendered = CaptureBundleSummary(bundle).render()

        #expect(rendered.contains("found [workouts-list-root] among the states it took (captured nothing), via tab 'Progress' — The states it kept could not be filed: disk full"))
        #expect(!rendered.contains("0 captured states"))
    }

    /// SimWalk#15: a screen that refused its dark state and kept its light one says both — "refused on this device" and "here is what was filed" — rather than reading as a screen that was never reached.
    @Test
    func aScreenThatRefusedOneStateNamesWhatItRefusedAndWhatItKept() {
        var manifest = CaptureBundleTests.manifest()
        manifest.screens = [
            CaptureManifest.ScreenRecord(
                id: "progress",
                outcome: .stateNotApplied(reason: "state 'dark' is no darker than 'light'"),
                routeTaken: [.tab(label: "Progress")],
                captures: [CaptureManifest.StateCapture(screenID: "progress", state: Walkbook.CaptureState(theme: .light))],
                refusedStates: [Walkbook.CaptureState(theme: .dark)]
            ),
        ]
        let bundle = CaptureBundle(url: URL(fileURLWithPath: "/tmp/example.simwalk"), manifest: manifest)

        let rendered = CaptureBundleSummary(bundle).render()

        #expect(rendered.contains("qualified — 1 screen refused, state not applied · 0 of 1 screens captured · 1 capture"))
        #expect(rendered.contains("progress — REFUSED [dark], state not applied; kept [light], via tab 'Progress': state 'dark' is no darker than 'light'"))
    }

    /// A capture of a screen that was still moving reads identically to a clean one unless the summary says otherwise — which is what left a half-rendered card unattributable between the tool and the app.
    @Test
    func aCaptureOfAMovingScreenIsCalledOutAndASettledOneIsNot() {
        var manifest = CaptureBundleTests.manifest()
        manifest.screens = [
            CaptureManifest.ScreenRecord(
                id: "heart-detail",
                outcome: .captured,
                routeTaken: [.tab(label: "Browse")],
                captures: [
                    CaptureManifest.StateCapture(screenID: "heart-detail", state: Walkbook.CaptureState(theme: .light), axTreeSettled: false),
                    CaptureManifest.StateCapture(screenID: "heart-detail", state: Walkbook.CaptureState(theme: .dark), axTreeSettled: true),
                ]
            ),
        ]
        let bundle = CaptureBundle(url: URL(fileURLWithPath: "/tmp/example.simwalk"), manifest: manifest)

        let rendered = CaptureBundleSummary(bundle).render()

        #expect(rendered.contains("1 capture was taken before the accessibility tree stopped changing"))
        #expect(rendered.contains("heart-detail [light]"))
        #expect(!rendered.contains("heart-detail [dark]"))
    }

    /// A capture of a screen that had not populated reads identically to a real one unless the summary says otherwise — and the fix is nameable, so the line names it.
    @Test
    func aCaptureHoldingOnlyChromeIsCalledOutAndApopulatedOneIsNot() {
        var manifest = CaptureBundleTests.manifest()
        manifest.screens = [
            CaptureManifest.ScreenRecord(
                id: "browse",
                outcome: .captured,
                routeTaken: [.tab(label: "Browse")],
                captures: [
                    CaptureManifest.StateCapture(screenID: "browse", state: Walkbook.CaptureState(theme: .light), axTreeSettled: true, axTreeHasContent: false),
                    CaptureManifest.StateCapture(screenID: "browse", state: Walkbook.CaptureState(theme: .dark), axTreeSettled: true, axTreeHasContent: true),
                ]
            ),
        ]
        let bundle = CaptureBundle(url: URL(fileURLWithPath: "/tmp/example.simwalk"), manifest: manifest)

        let rendered = CaptureBundleSummary(bundle).render()

        #expect(rendered.contains("1 capture holds the app's chrome and nothing else"))
        #expect(rendered.contains("only a `settle` above 3.75 s extends it"))
        #expect(rendered.contains("browse [light]"))
        #expect(!rendered.contains("browse [dark]"))
    }

    /// One bare capture, filed unsettled as well, is one qualification in the verdict, and the warning's advice states the cap rather than telling the reader to raise `settle` unconditionally.
    @Test
    func aBareCaptureIsOneQualificationInTheVerdict() {
        var manifest = CaptureBundleTests.manifest()
        manifest.screens = [
            CaptureManifest.ScreenRecord(
                id: "browse",
                outcome: .captured,
                routeTaken: [.tab(label: "Browse")],
                captures: [CaptureManifest.StateCapture(screenID: "browse", state: Walkbook.CaptureState(theme: .light), axTreeSettled: false, axTreeHasContent: false)]
            ),
        ]
        let rendered = CaptureBundleSummary(CaptureBundle(url: URL(fileURLWithPath: "/tmp/example.simwalk"), manifest: manifest)).render()

        #expect(rendered.contains("1 capture holding the app's chrome and nothing else"))
        #expect(!rendered.contains("1 capture taken before the tree settled"))
        #expect(rendered.contains("15 s content wait"))
        #expect(!rendered.contains("raise that screen's"))
    }

    /// A bundle written before the runner recorded the content check says nothing about it, exactly as it says nothing about settling.
    @Test
    func aBundleThatNeverRecordedTheContentCheckClaimsNothingAboutIt() {
        let bundle = CaptureBundle(url: URL(fileURLWithPath: "/tmp/example.simwalk"), manifest: CaptureBundleTests.manifest())

        #expect(!CaptureBundleSummary(bundle).render().contains("chrome and nothing else"))
    }

    /// The settle line states one number for the walk, so a screen that paid for more has to say so where a reader is already looking — and one that did not must not print a number it never asked for.
    @Test
    func aScreenThatPaidForItsOwnQuietPeriodSaysSoOnItsOwnLine() {
        var manifest = CaptureBundleTests.manifest()
        manifest.screens = [
            CaptureManifest.ScreenRecord(
                id: "browse",
                outcome: .captured,
                routeTaken: [.tab(label: "Browse")],
                captures: [CaptureManifest.StateCapture(screenID: "browse", state: Walkbook.CaptureState(theme: .light))],
                settleQuietMilliseconds: 6000
            ),
            CaptureManifest.ScreenRecord(
                id: "you",
                outcome: .captured,
                routeTaken: [.tab(label: "You")],
                captures: [CaptureManifest.StateCapture(screenID: "you", state: Walkbook.CaptureState(theme: .light))]
            ),
        ]
        let bundle = CaptureBundle(url: URL(fileURLWithPath: "/tmp/example.simwalk"), manifest: manifest)

        let rendered = CaptureBundleSummary(bundle).render()

        #expect(rendered.contains("browse — captured [light] via tab 'Browse' · settle 6000ms"))
        #expect(rendered.contains("you — captured [light] via tab 'You'"))
        #expect(!rendered.contains("you — captured [light] via tab 'You' · settle"))
    }

    /// A bundle written before the runner recorded settling says nothing about it, rather than guessing either way.
    @Test
    func aBundleThatNeverRecordedSettlingClaimsNothingAboutIt() {
        let bundle = CaptureBundle(url: URL(fileURLWithPath: "/tmp/example.simwalk"), manifest: CaptureBundleTests.manifest())

        #expect(!CaptureBundleSummary(bundle).render().contains("stopped changing"))
    }

    /// "The tree had stopped changing" is a claim about a window, so the summary states the window — and states that a quiet tree is not a still screen.
    @Test
    func aBundleSummaryStatesTheQuietPeriodEachCaptureWasTakenUnder() {
        var manifest = CaptureBundleTests.manifest()
        manifest.settleQuietMilliseconds = 800

        let rendered = CaptureBundleSummary(CaptureBundle(url: URL(fileURLWithPath: "/tmp/example.simwalk"), manifest: manifest)).render()

        #expect(rendered.contains("hold still for 800ms before each capture"))
        #expect(rendered.contains("animations it cannot see"))
    }

    /// A bundle that never recorded the threshold says so, rather than printing a default it cannot know was used.
    @Test
    func aBundleThatNeverRecordedTheQuietPeriodSaysUnrecordedRatherThanGuessing() {
        let bundle = CaptureBundle(url: URL(fileURLWithPath: "/tmp/example.simwalk"), manifest: CaptureBundleTests.manifest())

        #expect(CaptureBundleSummary(bundle).render().contains("hold still for unrecorded"))
    }

    @Test
    func aBundleSummaryNamesTheWalkbookThatProducedIt() {
        let bundle = CaptureBundle(url: URL(fileURLWithPath: "/tmp/example.simwalk"), manifest: CaptureBundleTests.manifest())

        let rendered = CaptureBundleSummary(bundle).render()

        #expect(rendered.hasPrefix("walk: 'example-validation'  app: dev.simwalk.route-fixture  build: a1b2c3d4  walkbook: 0f1e2d3c  device: iPhone 17 Pro (26.0)  settled: unrecorded\n"))
    }

    @Test
    func aWalkbookSummaryCountsScreensAndCapturesAndListsEachScreensStates() throws {
        let book = Walkbook(
            name: "example-validation",
            appBundleID: "dev.simwalk.route-fixture",
            screens: [
                Walkbook.Screen(
                    id: "today",
                    route: [.tab(label: "Today")],
                    states: [Walkbook.CaptureState(theme: .light), Walkbook.CaptureState(theme: .dark)]
                ),
            ]
        )

        let rendered = try WalkbookSummary(book).render()

        // The plan's name and its app sit exactly where a bundle's header puts them, so one rule covers
        // every face rather than `validate` alone stating them in its verdict.
        #expect(try rendered.hasPrefix("walk: 'example-validation'  app: dev.simwalk.route-fixture  walkbook: \(ShortHash.of(WalkbookIdentity.hash(of: book)))  screens: 1  steps: 1\n"))
        #expect(rendered.contains("ok — 2 captures planned"))
        #expect(rendered.contains("today — 1 step → [light, dark]"))
        // A validation stands in for nothing, so it claims no saving rather than claiming one of zero.
        #expect(!rendered.contains("tokens saved"))
    }

    /// A bundle without the runner's own record of its resets reads them from the captured states (SimWalk#62 item 2), and claims only that they were reset and not restored.
    @Test
    func aBundleWithoutLaunchResetsNamesTheResourcesFromItsCaptures() {
        var manifest = CaptureBundleTests.manifest()
        manifest.screens = [
            CaptureManifest.ScreenRecord(
                id: "nearby",
                outcome: .captured,
                routeTaken: [.tab(label: "Nearby")],
                captures: [CaptureManifest.StateCapture(screenID: "nearby", state: Walkbook.CaptureState(theme: .light, resetPermissions: ["location", "camera"]))]
            ),
            CaptureManifest.ScreenRecord(
                id: "photos",
                outcome: .unreachable(routeTried: [.tab(label: "Photos")], reason: "no such tab", cause: nil),
                routeTaken: [],
                captures: []
            ),
        ]
        let bundle = CaptureBundle(url: URL(fileURLWithPath: "/tmp/example.simwalk"), manifest: manifest)

        let rendered = CaptureBundleSummary(bundle).render()

        #expect(rendered.contains("permissions reset before launch and not restored by the walk, for"))
        #expect(rendered.contains(": camera, location (states:"))
        #expect(!rendered.contains("left reset"))
        #expect(rendered.contains("nearby [\(Walkbook.CaptureState(theme: .light, resetPermissions: ["location", "camera"]).slug)]"))
    }

    /// The UNREACHABLE line names the state whose route failed, and an old bundle's line is unchanged (SimWalk#120).
    @Test
    func anUnreachableLineNamesTheStateItFailedIn() {
        let state = ScreenOutcome.UnreachableState(failing: "xxxl", among: ["light", "dark", "xxxl", "xxxl-dark"])
        var manifest = CaptureBundleTests.manifest()
        manifest.screens = [
            CaptureManifest.ScreenRecord(id: "with", outcome: .unreachable(routeTried: [.tab(label: "Photos")], state: state), routeTaken: []),
            CaptureManifest.ScreenRecord(id: "without", outcome: .unreachable(routeTried: [.tab(label: "Photos")]), routeTaken: []),
        ]
        let rendered = CaptureBundleSummary(CaptureBundle(url: URL(fileURLWithPath: "/tmp/example.simwalk"), manifest: manifest)).render()

        #expect(rendered.contains("with — UNREACHABLE in state 'xxxl' (reached in light, dark; not tried: xxxl-dark), route tried: "))
        #expect(rendered.contains("without — UNREACHABLE, route tried: "))
    }

    /// A state whose reset ran but whose screen filed no capture is still named, because the runner records the reset itself (SimWalk#62 item 2).
    @Test
    func anUnreachableScreenWhoseStateResetLocationNamesItInTheLine() {
        let state = Walkbook.CaptureState(theme: .light, resetPermissions: ["location"])
        var manifest = CaptureBundleTests.manifest()
        manifest.screens = [
            CaptureManifest.ScreenRecord(
                id: "nearby",
                outcome: .unreachable(routeTried: [.tab(label: "Nearby")], reason: "no such tab", cause: nil),
                routeTaken: [],
                launchResets: [CaptureManifest.LaunchReset(state: state.slug, resources: ["location"])]
            ),
        ]
        let bundle = CaptureBundle(url: URL(fileURLWithPath: "/tmp/example.simwalk"), manifest: manifest)

        let rendered = CaptureBundleSummary(bundle).render()

        #expect(rendered.contains(": location (states: nearby [\(state.slug)])"))
    }

    /// A record carrying `launchResets` survives a round trip, and one without the key still decodes.
    @Test
    func launchResetsRoundTripAndAreOptionalOnDecode() throws {
        let record = CaptureManifest.ScreenRecord(
            id: "nearby", outcome: .captured, routeTaken: [],
            launchResets: [CaptureManifest.LaunchReset(state: "light", resources: ["location"])]
        )
        let decoded = try JSONDecoder().decode(CaptureManifest.ScreenRecord.self, from: JSONEncoder().encode(record))
        #expect(decoded == record)
        let bare = CaptureManifest.ScreenRecord(id: "a", outcome: .captured, routeTaken: [])
        #expect(try !String(decoding: JSONEncoder().encode(bare), as: UTF8.self).contains("launchResets"))
    }

    /// The runner's `filed` factory carries `launchResets` through (and an empty one reads as absent), the pin that keeps the runner's argument from being deleted (SimWalk#91 item 6).
    @Test
    func theRunnersFactoryCarriesLaunchResets() {
        let resets = [CaptureManifest.LaunchReset(state: "light", resources: ["location"])]

        let filed = CaptureManifest.ScreenRecord.filed(id: "nearby", outcome: .captured, routeTaken: [], settleQuietMilliseconds: 250, launches: CaptureManifest.ScreenRecord.Launches(resets: resets, deviceTurns: []), boundElements: [])
        let none = CaptureManifest.ScreenRecord.filed(id: "nearby", outcome: .captured, routeTaken: [], settleQuietMilliseconds: nil, launches: CaptureManifest.ScreenRecord.Launches(resets: [], deviceTurns: []), boundElements: [])

        #expect(filed == CaptureManifest.ScreenRecord(id: "nearby", outcome: .captured, routeTaken: [], settleQuietMilliseconds: 250, launchResets: resets, boundElements: []))
        #expect(filed.launchResets == resets)
        #expect(none.launchResets == nil)
    }

    private static let cell = CaptureManifest.BoundElement(step: 1, type: "Cell", identifier: nil, label: "Steps", frame: AXNode.Frame(x: 16, y: 214, width: 370, height: 132))

    /// A record without the `boundElements` key decodes as `nil`, one with it round-trips, and an empty list stays distinct from an absent one (SimWalk#93).
    @Test
    func boundElementsRoundTripAndAbsentIsNotEmpty() throws {
        let bound = CaptureManifest.ScreenRecord(id: "a", outcome: .captured, routeTaken: [], boundElements: [Self.cell])
        let empty = CaptureManifest.ScreenRecord(id: "a", outcome: .captured, routeTaken: [], boundElements: [])
        let absent = CaptureManifest.ScreenRecord(id: "a", outcome: .captured, routeTaken: [])

        let roundTripped = try [bound, empty, absent].map { try JSONDecoder().decode(CaptureManifest.ScreenRecord.self, from: JSONEncoder().encode($0)) }

        #expect(roundTripped == [bound, empty, absent])
        #expect(try JSONDecoder().decode(CaptureManifest.ScreenRecord.self, from: JSONEncoder().encode(absent)).boundElements == nil)
        #expect(try String(decoding: JSONEncoder().encode(absent), as: UTF8.self).contains("boundElements") == false)
        #expect(try String(decoding: JSONEncoder().encode(empty), as: UTF8.self).contains(#""boundElements":[]"#))
        #expect(bound.boundElements == [Self.cell])
        #expect(empty.boundElements == [])
    }

    /// A screen whose record names device turns puts the `⚠ device turned` line in the summary, naming the screen and state; a bundle with none has no such line (SimWalk#222).
    @Test
    func aDeviceTurnIsDisclosedInTheSummary() {
        var manifest = CaptureBundleTests.manifest()
        manifest.screens = [CaptureManifest.ScreenRecord.filed(id: "home", outcome: .captured, routeTaken: [], settleQuietMilliseconds: nil, launches: CaptureManifest.ScreenRecord.Launches(resets: [], deviceTurns: ["light"]), boundElements: [])]
        let turned = CaptureBundleSummary(CaptureBundle(url: URL(fileURLWithPath: "/tmp/example.simwalk"), manifest: manifest)).render()
        manifest.screens = [CaptureManifest.ScreenRecord.filed(id: "home", outcome: .captured, routeTaken: [], settleQuietMilliseconds: nil, launches: CaptureManifest.ScreenRecord.Launches(resets: [], deviceTurns: []), boundElements: [])]
        let none = CaptureBundleSummary(CaptureBundle(url: URL(fileURLWithPath: "/tmp/example.simwalk"), manifest: manifest)).render()

        #expect(turned.contains("⚠ device turned"))
        #expect(turned.contains("(states: home [light])"))
        #expect(!none.contains("device turned"))
    }

    /// The runner's `filed` factory carries `boundElements` through, an empty list as empty rather than absent.
    @Test
    func theRunnersFactoryCarriesBoundElements() {
        let filed = CaptureManifest.ScreenRecord.filed(id: "a", outcome: .captured, routeTaken: [], settleQuietMilliseconds: nil, launches: CaptureManifest.ScreenRecord.Launches(resets: [], deviceTurns: []), boundElements: [Self.cell])
        let none = CaptureManifest.ScreenRecord.filed(id: "a", outcome: .captured, routeTaken: [], settleQuietMilliseconds: nil, launches: CaptureManifest.ScreenRecord.Launches(resets: [], deviceTurns: []), boundElements: [])

        #expect(filed.boundElements == [Self.cell])
        #expect(none.boundElements == [])
    }

    /// A walk that reset nothing prints no line about it.
    @Test
    func aWalkThatResetNothingSaysNothingAboutResets() {
        let bundle = CaptureBundle(url: URL(fileURLWithPath: "/tmp/example.simwalk"), manifest: CaptureBundleTests.manifest())

        #expect(!CaptureBundleSummary(bundle).render().contains("permissions reset"))
    }
}
