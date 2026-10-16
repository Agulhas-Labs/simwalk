//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// The compact result built from a manifest (`Docs/SIMWALK-PROGRESS.md` §4): one fixture per outcome, the counting rule shared with the progress file, and the 16 KiB cap.
struct WalkResultBuilderTests {
    static let bundleURL = URL(fileURLWithPath: "/abs/Out.simwalk")

    @Test
    func aCapturedScreenIsAPassedStepWithItsScreenshotAndNoKind() throws {
        let result = Self.build([Self.captured("home")])
        let step = try #require(result.steps.first)

        #expect(result.verdict == .passed)
        #expect(step == WalkResult.Step(index: 1, screen: "home", outcome: .passed, screenshotPath: Self.screenshot("home", .light)))
        #expect(result.failures.isEmpty)
        #expect(result.truncated == WalkResult.Truncated(omittedSteps: 0))
    }

    @Test
    func anUnreachableScreenFailsWithTheRouteItTriedAsItsReason() throws {
        let screen = CaptureManifest.ScreenRecord(
            id: "power",
            outcome: .unreachable(routeTried: [.tab(label: "Workouts"), .tap(label: "Power")], reason: "label taken by the navigation bar"),
            routeTaken: [.tab(label: "Workouts")]
        )
        let result = Self.build([Self.captured("home"), screen])
        let failure = try #require(result.failures.first)

        #expect(result.verdict == .failed)
        #expect(failure.index == 2)
        #expect(failure.kind == "unreachable")
        #expect(failure.reason == "route tried: \([Walkbook.RouteStep.tab(label: "Workouts"), .tap(label: "Power")].rendered) — label taken by the navigation bar")
        #expect(failure.expected == Walkbook.RouteStep.tap(label: "Power").description)
        #expect(failure.actual == nil)
        #expect(failure.screenshotPath == nil)
        #expect(result.steps[1] == WalkResult.Step(index: 2, screen: "power", outcome: .failed, kind: "unreachable", reason: failure.reason))
    }

    @Test
    func anUnreachableScreensReasonNamesTheStateItFailedIn() throws {
        let route: [Walkbook.RouteStep] = [.tap(label: "Power")]
        let state = ScreenOutcome.UnreachableState(failing: "dark", among: ["light", "dark"])
        let screen = CaptureManifest.ScreenRecord(id: "power", outcome: .unreachable(routeTried: route, state: state), routeTaken: [])
        let failure = try #require(Self.build([screen]).failures.first)

        #expect(failure.reason == "in state 'dark' (reached in light), route tried: \(route.rendered)")
    }

    /// A capture carrying no screen identifier is `nil` in `found`, and `null` inside `actual`.
    @Test
    func anUnexpectedScreenCarriesExpectedAndActualWithNullForAMissingIdentifier() throws {
        let screen = CaptureManifest.ScreenRecord(
            id: "login",
            outcome: .unexpectedScreen(expected: "login", found: ["welcome", nil]),
            routeTaken: [.tap(label: "Sign in")],
            captures: [Self.capture("login", .light), Self.capture("login", .dark)]
        )
        let result = Self.build([screen])
        let failure = try #require(result.failures.first)
        let text = try String(decoding: WalkResult.encoder().encode(result), as: UTF8.self)

        #expect(failure.kind == "unexpectedScreen")
        #expect(failure.expected == "login")
        #expect(failure.actual == ["welcome", nil])
        #expect(failure.reason == CaptureBundleSummary.outcomeWords(screen.outcome))
        #expect(failure.screenshotPath == Self.screenshot("login", .light))
        #expect(text.contains(#""actual":["welcome",null]"#))
    }

    @Test
    func aStateNotAppliedScreenFailsWithItsReasonAndKeptCapture() throws {
        let screen = CaptureManifest.ScreenRecord(
            id: "today",
            outcome: .stateNotApplied(reason: "dark render measured light"),
            routeTaken: [.tab(label: "Today")],
            captures: [Self.capture("today", .light)],
            refusedStates: [Walkbook.CaptureState(theme: .dark)]
        )
        let failure = try #require(Self.build([screen]).failures.first)

        #expect(failure == WalkResult.Failure(
            index: 1,
            screen: "today",
            kind: "stateNotApplied",
            reason: "dark render measured light",
            screenshotPath: Self.screenshot("today", .light)
        ))
    }

    @Test
    func aCaptureFailedScreenFailsWithItsReason() {
        let screen = CaptureManifest.ScreenRecord(id: "sleep", outcome: .captureFailed(reason: "disk full"), routeTaken: [.tab(label: "Sleep")])
        let result = Self.build([screen])

        #expect(result.verdict == .failed)
        #expect(result.failures == [WalkResult.Failure(index: 1, screen: "sleep", kind: "captureFailed", reason: "disk full")])
    }

    @Test
    func aBuildMismatchRefusesTheWalkAndNamesBothHashes() throws {
        let screen = CaptureManifest.ScreenRecord(id: "sleep", outcome: .buildMismatch(expected: "a1b2c3d4", found: "58ebbd24"), routeTaken: [])
        let result = Self.build([Self.captured("home"), screen, Self.unreachable("power")])
        let failure = try #require(result.failures.first)

        #expect(result.verdict == .refused)
        #expect(failure.kind == "buildMismatch")
        #expect(failure.reason == "build mismatch: expected a1b2c3d4, found 58ebbd24")
    }

    /// `counts` and each step's outcome are the progress file's `matches` rule: `captured` passes, everything else fails.
    @Test
    func countsAndStepOutcomesAgreeWithTheProgressMatches() {
        let manifest = Self.manifest(Self.everyOutcome())
        let result = WalkResultBuilder().build(manifest: manifest, bundleURL: Self.bundleURL, timings: PhaseTimings(), logPath: nil)
        var matches = WalkProgress.Matches(planned: manifest.screens.count)
        for screen in manifest.screens {
            matches.record(screen.outcome)
        }

        #expect(result.counts == WalkResult.Counts(planned: matches.planned, passed: matches.passed, failed: matches.failed))
        #expect(result.steps.count { $0.outcome == .passed } == matches.passed)
        #expect(result.failures.count == matches.failed)
    }

    /// `kind` is spelt by hand; this holds it to the case name `ScreenOutcome` encodes under.
    @Test
    func kindIsTheCaseNameTheOutcomeEncodesUnder() throws {
        let manifest = Self.manifest(Self.everyOutcome().filter { !$0.outcome.isCaptured })
        let result = WalkResultBuilder().build(manifest: manifest, bundleURL: Self.bundleURL, timings: PhaseTimings(), logPath: nil)
        let encodedNames = try manifest.screens.map { screen in
            let object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(screen.outcome)) as? [String: Any]
            return try #require(object?.keys.first)
        }

        #expect(result.failures.map(\.kind) == encodedNames)
    }

    /// Over the cap, passed steps go from the end — past a failure that is last — and no more of them than it takes.
    @Test
    func overTheCapDropsPassedStepsFromTheEndAndKeepsFailures() throws {
        let manifest = Self.manifest((1 ... 200).map { Self.captured("screen-\($0)") } + [Self.unreachable("power")])
        let full = WalkResultBuilder().build(manifest: manifest, bundleURL: Self.bundleURL, timings: PhaseTimings(), logPath: nil, byteLimit: .max)
        let capped = WalkResultBuilder().build(manifest: manifest, bundleURL: Self.bundleURL, timings: PhaseTimings(), logPath: nil)
        let encoded = try WalkResult.encoder().encode(capped)
        let decoded = try WalkResult.decoder().decode(WalkResult.self, from: encoded)
        let kept = Set(capped.steps.map(\.index))
        let dropped = full.steps.filter { !kept.contains($0.index) }
        let lastDropped = try #require(dropped.first)
        var oneFewer = capped
        oneFewer.steps.insert(lastDropped, at: oneFewer.steps.firstIndex { $0.index > lastDropped.index } ?? oneFewer.steps.endIndex)
        oneFewer.truncated.omittedSteps -= 1

        #expect(try WalkResult.encoder().encode(full).count > 16 * 1024)
        #expect(encoded.count <= 16 * 1024)
        #expect(decoded == capped)
        #expect(capped.truncated.omittedSteps == dropped.count)
        #expect(dropped.allSatisfy { $0.outcome == .passed })
        #expect(capped.steps.last == full.steps.last)
        #expect(capped.steps.dropLast().allSatisfy { $0.index < lastDropped.index })
        #expect(capped.failures == full.failures)
        #expect(oneFewer.encodedSize > 16 * 1024)
    }

    /// Past every passed step, failed steps go from the end too — their `failures` entry stays whole.
    @Test
    func overTheCapWithOnlyFailuresDropsFailedStepsAndKeepsEveryFailureWhole() {
        let manifest = Self.manifest((1 ... 12).map { Self.captureFailed("screen-\($0)", reasonLength: 800) })
        let full = WalkResultBuilder().build(manifest: manifest, bundleURL: Self.bundleURL, timings: PhaseTimings(), logPath: nil, byteLimit: .max)
        let capped = WalkResultBuilder().build(manifest: manifest, bundleURL: Self.bundleURL, timings: PhaseTimings(), logPath: nil)

        #expect(full.encodedSize > 16 * 1024)
        #expect(capped.encodedSize <= 16 * 1024)
        #expect(capped.steps.count < full.steps.count)
        #expect(capped.truncated.omittedSteps == full.steps.count - capped.steps.count)
        #expect(capped.steps.allSatisfy { $0.index <= capped.steps.count })
        #expect(capped.failures == full.failures)
        #expect(capped.truncated.clippedFailures == 0)
    }

    /// Still over with no step left to drop, every failure's text is clipped to 512 characters and counted; none is dropped.
    @Test
    func overTheCapWithNoStepsLeftClipsFailureTextAndCountsIt() {
        let manifest = Self.manifest((1 ... 60).map { Self.captureFailed("screen-\($0)", reasonLength: 1000) })
        let capped = WalkResultBuilder().build(manifest: manifest, bundleURL: Self.bundleURL, timings: PhaseTimings(), logPath: nil)

        #expect(capped.steps.isEmpty)
        #expect(capped.truncated.omittedSteps == 60)
        #expect(capped.failures.count == 60)
        #expect(capped.truncated.clippedFailures == 60)
        #expect(capped.failures.allSatisfy { $0.reason.count == 512 && $0.reason.hasSuffix("…") })
        #expect(capped.encodedSize > 16 * 1024)
    }

    /// A result written before `clippedFailures` existed still decodes, as `0`.
    @Test
    func aTruncatedWithoutClippedFailuresDecodesAsZero() throws {
        let result = WalkResultBuilder().build(manifest: Self.manifest([Self.captured("home")]), bundleURL: Self.bundleURL, timings: PhaseTimings(), logPath: nil)
        var object = try #require(try JSONSerialization.jsonObject(with: WalkResult.encoder().encode(result)) as? [String: Any])
        object["truncated"] = ["omittedSteps": 3]
        let decoded = try WalkResult.decoder().decode(WalkResult.self, from: JSONSerialization.data(withJSONObject: object))

        #expect(decoded.truncated == WalkResult.Truncated(omittedSteps: 3, clippedFailures: 0))
    }

    /// A result exactly at the cap is whole; one byte under it, a step goes.
    @Test
    func withinTheCapNothingIsOmitted() {
        let manifest = Self.manifest((1 ... 5).map { Self.captured("screen-\($0)") })
        let builder = WalkResultBuilder()
        let size = builder.build(manifest: manifest, bundleURL: Self.bundleURL, timings: PhaseTimings(), logPath: nil).encodedSize
        let atTheCap = builder.build(manifest: manifest, bundleURL: Self.bundleURL, timings: PhaseTimings(), logPath: nil, byteLimit: size)
        let underIt = builder.build(manifest: manifest, bundleURL: Self.bundleURL, timings: PhaseTimings(), logPath: nil, byteLimit: size - 1)

        #expect(atTheCap.truncated.omittedSteps == 0)
        #expect(atTheCap.steps.count == 5)
        #expect(underIt.truncated.omittedSteps == 1)
        #expect(underIt.steps.map(\.index) == [1, 2, 3, 4])
    }

    @Test
    func verboseLiftsTheCapAndAddsStatesAndTheRouteTaken() throws {
        let manifest = Self.manifest((1 ... 200).map { Self.captured("screen-\($0)") })
        let verbose = WalkResultBuilder().build(manifest: manifest, bundleURL: Self.bundleURL, timings: PhaseTimings(), logPath: nil, verbose: true)
        let compact = WalkResultBuilder().build(manifest: manifest, bundleURL: Self.bundleURL, timings: PhaseTimings(), logPath: nil)
        let first = try #require(verbose.steps.first)
        let tree = CaptureBundleLayout.url(
            forRelativePath: CaptureBundleLayout.axTreePath(screenID: "screen-1", stateSlug: Walkbook.CaptureState(theme: .light).slug),
            in: Self.bundleURL
        ).path

        #expect(verbose.steps.count == 200)
        #expect(verbose.truncated.omittedSteps == 0)
        #expect(verbose.encodedSize > 16 * 1024)
        #expect(first.states == [WalkResult.State(slug: Walkbook.CaptureState(theme: .light).slug, screenshotPath: Self.screenshot("screen-1", .light), axTreePath: tree)])
        #expect(first.routeTaken == [Walkbook.RouteStep.tab(label: "Today")].rendered)
        #expect(compact.steps.allSatisfy { $0.states == nil && $0.routeTaken == nil })
    }

    @Test
    func theSameManifestEncodesToTheSameBytes() throws {
        let manifest = Self.manifest(Self.everyOutcome())
        let first = try WalkResult.encoder().encode(Self.build(manifest.screens))
        let second = try WalkResult.encoder().encode(Self.build(manifest.screens))

        #expect(first == second)
        #expect(!first.contains(UInt8(ascii: "\n")))
    }
}

extension WalkResultBuilderTests {
    static func build(_ screens: [CaptureManifest.ScreenRecord]) -> WalkResult {
        WalkResultBuilder().build(manifest: manifest(screens), bundleURL: bundleURL, timings: PhaseTimings(bootMs: 1), logPath: "/abs/usage.jsonl")
    }

    static func manifest(_ screens: [CaptureManifest.ScreenRecord]) -> CaptureManifest {
        CaptureManifest(
            walkName: "example",
            appBundleID: "com.example.App",
            appBuildHash: "a1b2c3d4",
            walkbookHash: "0f1e2d3c",
            device: CaptureManifest.Device(name: "iPhone 17", udid: "U-1", osVersion: "26.5"),
            startedAt: Date(timeIntervalSince1970: 1_790_931_600),
            finishedAt: Date(timeIntervalSince1970: 1_790_931_700),
            screens: screens
        )
    }

    static func captured(_ id: String) -> CaptureManifest.ScreenRecord {
        CaptureManifest.ScreenRecord(id: id, outcome: .captured, routeTaken: [.tab(label: "Today")], captures: [capture(id, .light)])
    }

    static func captureFailed(_ id: String, reasonLength: Int) -> CaptureManifest.ScreenRecord {
        CaptureManifest.ScreenRecord(id: id, outcome: .captureFailed(reason: String(repeating: "x", count: reasonLength)), routeTaken: [])
    }

    static func unreachable(_ id: String) -> CaptureManifest.ScreenRecord {
        CaptureManifest.ScreenRecord(id: id, outcome: .unreachable(routeTried: [.tap(label: "Power")]), routeTaken: [])
    }

    static func capture(_ id: String, _ theme: Walkbook.Theme) -> CaptureManifest.StateCapture {
        CaptureManifest.StateCapture(screenID: id, state: Walkbook.CaptureState(theme: theme))
    }

    static func screenshot(_ id: String, _ theme: Walkbook.Theme) -> String {
        CaptureBundleLayout.url(forRelativePath: capture(id, theme).screenshotPath, in: bundleURL).path
    }

    /// One screen per `ScreenOutcome` case, in declaration order.
    static func everyOutcome() -> [CaptureManifest.ScreenRecord] {
        [
            captured("home"),
            unreachable("power"),
            CaptureManifest.ScreenRecord(id: "sleep", outcome: .buildMismatch(expected: "a", found: "b"), routeTaken: []),
            CaptureManifest.ScreenRecord(id: "trends", outcome: .captureFailed(reason: "disk"), routeTaken: []),
            CaptureManifest.ScreenRecord(id: "today", outcome: .stateNotApplied(reason: "dark"), routeTaken: []),
            CaptureManifest.ScreenRecord(id: "login", outcome: .unexpectedScreen(expected: "login", found: [nil]), routeTaken: [], captures: [capture("login", .light)]),
        ]
    }
}
