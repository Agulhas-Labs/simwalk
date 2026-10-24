//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

/// Every failure kind's wire spelling, which of this module's own error types conforms to which kind, and the text inference a log line written before the field existed falls back to.
struct UsageFailureKindTests {
    /// The wire spelling `simwalk usage` prints and a log line stores — pinned because it is read by `jq` and by a reader's own eyes, not just decoded back by this package.
    @Test
    func eachKindsWireSpellingIsKebabCase() {
        #expect(UsageFailureKind.inputRefused.rawValue == "input-refused")
        #expect(UsageFailureKind.routeUnreachable.rawValue == "route-unreachable")
        #expect(UsageFailureKind.runnerFailed.rawValue == "runner-failed")
        #expect(UsageFailureKind.deviceLeftBad.rawValue == "device-left-bad")
        #expect(UsageFailureKind.setupFailed.rawValue == "setup-failed")
        #expect(UsageFailureKind.toolError.rawValue == "tool-error")
    }

    @Test
    func walkbookLoadErrorIsAlwaysInputRefused() {
        let unreadable = WalkbookLoadError.unreadable(source: "x.json", reason: "no such file")
        let malformed = WalkbookLoadError.malformed(source: "x.json", reason: "bad JSON")
        let invalid = WalkbookLoadError.invalid(source: "x.json", problems: [])

        #expect(UsageFailureKind.of(unreadable) == .inputRefused)
        #expect(UsageFailureKind.of(malformed) == .inputRefused)
        #expect(UsageFailureKind.of(invalid) == .inputRefused)
    }

    @Test
    func walkbookSubsetErrorIsInputRefused() {
        let error = WalkbookSubsetError.unknownScreens(requested: ["ghost"], available: ["today"])

        #expect(UsageFailureKind.of(error) == .inputRefused)
    }

    /// `CaptureBundleError`'s default covers `bundle inspect`/`bundle audit` reading a caller's own bundle path, and `walk`'s pre-flight check on `--output` — every manifest-level case, because both call sites can throw any of them.
    ///
    /// `artefactUnreadable` is not among them: it defaults to `.runnerFailed` (below), because the common case is a bundle this tool just wrote.
    @Test
    func captureBundleErrorDefaultsToInputRefused() {
        let cases: [CaptureBundleError] = [
            .misnamedBundle(path: "/tmp", expectedExtension: "simwalk"),
            .notABundle(path: "/nope.simwalk"),
            .manifestMissing(bundlePath: "/a.simwalk", expectedPath: "/a.simwalk/manifest.json"),
            .manifestUnreadable(path: "/a.simwalk/manifest.json", reason: "denied"),
            .manifestMalformed(path: "/a.simwalk/manifest.json", reason: "torn"),
            .unsupportedFormatVersion(path: "/a.simwalk/manifest.json", found: 99, supported: [4]),
            .manifestInvalid(path: "/a.simwalk/manifest.json", problems: []),
            .notWritable(path: "/a.simwalk", reason: "denied"),
            .bundleDirectoryNotEmpty(path: "/a.simwalk", entries: 3),
            .bundleFromAnotherWalk(path: "/a.simwalk", problems: ["it started before this walk launched its runner"]),
        ]

        for error in cases {
            #expect(UsageFailureKind.of(error) == .inputRefused)
        }
    }

    /// `bundle audit` is the only thing that decodes accessibility trees — a walk's own read-back checks that the tree files exist, not that they decode — so a mismatch between how the runner writes a tree and how the host reads it surfaces first here, on a bundle the tool just wrote, and is the runner's problem to answer for, not a caller's.
    @Test
    func artefactUnreadableIsRunnerFailed() {
        let error = CaptureBundleError.artefactUnreadable(path: "/a.simwalk/screens/x/light/ax-tree.json", reason: "denied")

        #expect(UsageFailureKind.of(error) == .runnerFailed)
    }

    /// A bad step or state is the caller's argument, not a tool fault (SimWalk#123).
    @Test
    func bundleScreenErrorIsAlwaysInputRefused() {
        let cases: [BundleScreenError] = [
            .stepOutOfRange(step: 9, screenCount: 2),
            .screenIDNotFound(id: "ghost", available: ["today"]),
            .ambiguousStep(step: "2", positionScreenID: "a", idPosition: 1),
            .screenNotCaptured(step: 1, screenID: "vault", outcome: "UNREACHABLE"),
            .stateNotFound(step: 1, screenID: "today", requested: "dark", available: ["light"]),
            .stateRefused(step: 1, screenID: "today", requested: "dark", available: ["light"]),
        ]

        for error in cases {
            #expect(UsageFailureKind.of(error) == .inputRefused)
        }
    }

    /// An older bundle's untyped tree is the caller's file, not the runner's output; a damaged current-format tree stays the runner's (SimWalk#123).
    @Test
    func anOlderFormatBundlesTreeIsInputRefused() throws {
        let directory = try TemporaryDirectory()
        let older = try CaptureBundleFixture.write(
            in: directory,
            captures: [CaptureBundleFixture.Capture(screenID: "s", state: Walkbook.CaptureState(theme: .light), tree: AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 1, height: 1)))],
            rawTreeBytes: #"{"raw":"Attributes: Application"}"#,
            formatVersion: 1
        )
        let capture = try #require(older.manifest.screens.first?.captures.first)

        let thrown = try #require(#expect(throws: CaptureBundleError.self) { try older.axTree(for: capture) })

        #expect(thrown.description.contains("this bundle is format 1"))
        #expect(UsageFailureKind.of(thrown) == .inputRefused)
    }

    @Test
    func appBuildIdentityErrorIsRunnerFailed() {
        let notAnApp = AppBuildIdentityError.notAnApp(path: "/x.app")
        let unreadable = AppBuildIdentityError.unreadableExecutable(path: "/x.app/x", reason: "denied")

        #expect(UsageFailureKind.of(notAnApp) == .runnerFailed)
        #expect(UsageFailureKind.of(unreadable) == .runnerFailed)
    }

    /// An error type that has never conformed has no opinion — recorded as a site not yet mapped, never guessed at.
    @Test
    func anUnconformedErrorHasNoKind() {
        struct Unmapped: Error {}

        #expect(UsageFailureKind.of(Unmapped()) == nil)
    }

    // MARK: - Text inference for lines written before the field existed

    @Test
    func inputRefusedTextIsInferredFromRealErrorShapes() {
        let samples = [
            "cannot read walkbook at /nope.json: The file couldn't be opened because there is no such file.",
            "walkbook at /tmp/x.json is not a walkbook: expected Dictionary<String, Any> at screens.Index 0",
            "walkbook at /tmp/x.json is not executable — 1 problem:   - screen id 'today' is used 2 times",
            "no screen named 'ghost' in this walkbook — it has: today, yesterday",
            "no simulator named 'iPhone 99' — available: iPhone 17 Pro",
            "/tmp is not named as a capture bundle — a bundle directory ends in .simwalk",
            "/a.simwalk already holds 3 items — a walk writes a fresh bundle, or it would validate",
            "unknown tool 'nope' — this server serves walk, validate, inspect, audit",
            "validate needs 'walkbook', which was not given",
            "walk was given a blank 'walkbook'",
            "walk was given a 'output' of 4 — it takes a path",
            "walk was given a 'device' of 4 — it takes a non-empty string",
            "walk was given a 'settle' of 0.5 — it takes a whole number of milliseconds",
            "walk was given a 'screenIDs' of today — it takes an array of screen ids",
            "walk was given a 'screenIDs' entry of 4 — every entry is a screen id",
            "--settle takes a quiet period in milliseconds greater than zero; 0 would be discarded",
            "com.example.app declares iPhone only (UIDeviceFamily [1]) and iPad Pro 11-inch (M5) (UDID-1) is an iPad, where it runs scaled",
        ]

        for text in samples {
            #expect(UsageFailureKind.inferred(fromErrorText: text) == .inputRefused, "\(text)")
        }
    }

    @Test
    func runnerFailedTextIsInferredFromRealErrorShapes() {
        let samples = [
            "the walk runner could not be built:   xcodebuild: error: '/Runner/SimWalkRunner.xcodeproj' does not exist.",
            "the walk did not complete:   /Runner/WalkRunner.swift:207: error: Failed to get matching snapshots",
            "no walk runner is installed for this simwalk binary (sha256 2c947434) — the runner and the binary are two halves of one contract",
            "the walk runner snapshot for commit 9916b2d3 is not at /x any more — run `simwalk install-hook`",
            "SIMWALK_RUNNER_PROJECT points at /x, which is not there — a walk builds the runner from source, so that path must be a SimWalkRunner.xcodeproj",
            "cannot read this simwalk binary to tell which runner it was installed with — set SIMWALK_RUNNER_PROJECT",
            "/checkout is not a git checkout the runner can be snapshotted from (no .git directory)",
            "/x.app is not an app bundle — no readable Info.plist naming a CFBundleExecutable",
            "cannot read /x.app/x to identify the build being walked: denied",
            "no available simulators — install a runtime in Xcode, or check `xcrun simctl list devices available`",
            "cannot read `simctl list devices --json` — the format is not what this build expects",
        ]

        for text in samples {
            #expect(UsageFailureKind.inferred(fromErrorText: text) == .runnerFailed, "\(text)")
        }
    }

    /// Deliberately unmatched: `bundle inspect` reading a caller's own bundle and a walk reading back the bundle its own runner just wrote can print the identical sentence for two different reasons, and the text alone cannot tell them apart — this is what the report counts as `unclassified`.
    @Test
    func ambiguousCaptureBundleShapesAreNotInferred() {
        let samples = [
            "capture bundle at /a.simwalk has no manifest — expected /a.simwalk/manifest.json",
            "cannot read manifest at /a.simwalk/manifest.json: denied",
            "manifest at /a.simwalk/manifest.json does not describe a walk that could have happened — 1 problem",
            "manifest at /a.simwalk/manifest.json states bundle format 4; this build reads format 3",
            "no capture bundle at /nope.simwalk — expected a directory",
        ]

        for text in samples {
            #expect(UsageFailureKind.inferred(fromErrorText: text) == nil, "\(text)")
        }
    }

    /// Deliberately unmatched, for a different reason than the `CaptureBundleError` shapes above: this exact sentence used to be written for *any* `simctl` failure a device-lookup ran into, not only a genuinely absent app, until the fix that narrowed it.
    ///
    /// A line already on disk cannot be told which binary wrote it, so this stays `unclassified` rather than risk reading a real `runner-failed` as an engineered `input-refused` — the one direction this whole field exists to refuse.
    @Test
    func anInstalledAppCheckIsNotInferredEvenThoughItLooksLikeAClearRefusal() {
        #expect(UsageFailureKind.inferred(fromErrorText: "com.example.app is not installed on 914BA16A — install it first, or pass --app-path") == nil)
    }

    /// ArgumentParser's own sentences are never read as a caller's mistake: only the MCP face can log one, and there it means this server built a vector its own command rejected — `tool-error` on the live path.
    ///
    /// These are the shapes MCP servers wrote for a walkbook named `-x.json` or `--version`, and for a negative `settle` passed as its own token — all three this server's own bugs, and all three counted as `input-refused` while this inference existed.
    @Test
    func argumentParsersOwnSentencesAreNotInferred() {
        let samples = [
            "Missing expected argument '<walkbook>'",
            "Missing value for '--settle <settle>'",
        ]

        for text in samples {
            #expect(UsageFailureKind.inferred(fromErrorText: text) == nil, "\(text)")
        }
    }

    @Test
    func unrecognisedTextIsNotInferred() {
        #expect(UsageFailureKind.inferred(fromErrorText: "") == nil)
        #expect(UsageFailureKind.inferred(fromErrorText: "something this list has never seen") == nil)
    }

    /// `the walk did not complete:` embeds the runner's own captured output, which can itself quote a lower-level error — here a `WalkbookLoadError.invalid` description carrying its own `is not a walkbook:` marker.
    ///
    /// The outer, real error is the runner failing; checking runner markers first is what keeps the quoted phrase from winning.
    @Test
    func arunnerFailureEmbeddingAWalkbookErrorIsInferredAsRunnerFailed() {
        let text = #"the walk did not complete:   caught error: "walkbook at /tmp/x.json is not a walkbook: expected Dictionary<String, Any> at screens.Index 0""#

        #expect(UsageFailureKind.inferred(fromErrorText: text) == .runnerFailed)
    }
}
