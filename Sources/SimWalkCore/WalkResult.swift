//
// Copyright © Agulhas Labs
//

import Foundation

/// The compact result a walk leaves when it ends (`Docs/SIMWALK-PROGRESS.md` §4): what a `/simwalk` results pane renders, bounded at 16 KiB unless the run asked for `verbose`.
///
/// Built from the manifest by ``WalkResultBuilder`` and written before the progress file names it (``ProgressWriter/finish(writing:to:as:error:)``). A walk compares no screenshots, so there is no reference image and no diff percentage here: a step passes when its screen was reached and captured as the walkbook said.
public struct WalkResult: Codable, Equatable, Sendable {
    /// The schema this build writes.
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// The face that ran the walk, as the progress file names it.
    public var tool: String
    public var verdict: Verdict
    public var walkName: String
    /// The bundle identifier of the app that was walked.
    public var app: String
    public var device: WalkProgress.Device
    /// The capture bundle, absolute.
    public var bundlePath: String
    public var logPath: String?
    public var timings: PhaseTimings
    public var counts: Counts
    /// Every screen in walkbook order, less what the cap dropped from the end: passed steps first, then failed ones (which `failures` still carries in full).
    public var steps: [Step]
    /// Every screen that did not pass — never dropped, whatever the cap; past it, only the long `reason`/`expected`/`actual` text is clipped (`truncated.clippedFailures`), and the result can still ship over the cap.
    public var failures: [Failure]
    public var truncated: Truncated

    /// The encoder the result file is written with: the progress file's — compact, sorted keys, unescaped slashes — so the same run's bytes are the same bytes.
    public static func encoder() -> JSONEncoder {
        WalkProgress.encoder()
    }

    /// The matching decoder.
    public static func decoder() -> JSONDecoder {
        WalkProgress.decoder()
    }

    /// The size this result encodes to, which is what the cap is measured in.
    var encodedSize: Int {
        (try? Self.encoder().encode(self).count) ?? 0
    }
}

public extension WalkResult {
    /// The walk's verdict: `refused` when any screen refused on a build mismatch, else `failed` when any screen did not pass, else `passed`.
    enum Verdict: String, Codable, Equatable, Sendable {
        case passed
        case failed
        case refused
    }

    /// The screens counted by outcome, under the rule the progress file's `matches` counts them by.
    struct Counts: Codable, Equatable, Sendable {
        public var planned: Int
        public var passed: Int
        public var failed: Int

        public init(planned: Int, passed: Int, failed: Int) {
            self.planned = planned
            self.passed = passed
            self.failed = failed
        }
    }

    /// One screen of the walk.
    struct Step: Codable, Equatable, Sendable {
        /// 1-based, in walkbook order — kept when steps before it are dropped, so a reader can see the gap.
        public var index: Int
        /// The walkbook id of the screen.
        public var screen: String
        public var outcome: Outcome
        /// The `ScreenOutcome` case of a step that did not pass; absent on a passed one.
        public var kind: String?
        public var reason: String?
        /// The first capture's screenshot, absolute, on a passed step; a failed step's is in ``WalkResult/failures``.
        public var screenshotPath: String?
        /// Every state captured, with both artefacts' absolute paths — `verbose` only.
        public var states: [State]?
        /// The route the runner completed, rendered — `verbose` only.
        public var routeTaken: String?

        public init(
            index: Int,
            screen: String,
            outcome: Outcome,
            kind: String? = nil,
            reason: String? = nil,
            screenshotPath: String? = nil
        ) {
            self.index = index
            self.screen = screen
            self.outcome = outcome
            self.kind = kind
            self.reason = reason
            self.screenshotPath = screenshotPath
        }
    }

    /// A step's verdict: `passed` for a screen reached and captured as the walkbook said, `failed` for every other outcome.
    enum Outcome: String, Codable, Equatable, Sendable {
        case passed
        case failed
    }

    /// One captured state of a step, in a `verbose` result.
    struct State: Codable, Equatable, Sendable {
        public var slug: String
        public var screenshotPath: String
        public var axTreePath: String

        public init(slug: String, screenshotPath: String, axTreePath: String) {
            self.slug = slug
            self.screenshotPath = screenshotPath
            self.axTreePath = axTreePath
        }
    }

    /// A screen that did not pass, with what a reader needs to act on it.
    struct Failure: Codable, Equatable, Sendable {
        public var index: Int
        public var screen: String
        /// The `ScreenOutcome` case.
        public var kind: String
        public var reason: String
        /// The screen identifier the walkbook expected (`unexpectedScreen`), or the last route step an `unreachable` screen was reaching for.
        public var expected: String?
        /// The screen identifiers the captures showed (`unexpectedScreen`), `null` for one carrying none; `nil` for `unreachable`, whose manifest records no identifiers of where the walk stopped.
        public var actual: [String?]?
        /// The first capture's screenshot, absolute — the *actual* capture, for a screen that filed one.
        public var screenshotPath: String?

        public init(
            index: Int,
            screen: String,
            kind: String,
            reason: String,
            expected: String? = nil,
            actual: [String?]? = nil,
            screenshotPath: String? = nil
        ) {
            self.index = index
            self.screen = screen
            self.kind = kind
            self.reason = reason
            self.expected = expected
            self.actual = actual
            self.screenshotPath = screenshotPath
        }
    }

    /// What the cap left out: always present, `0` when nothing was.
    struct Truncated: Codable, Equatable, Sendable {
        /// Steps dropped from `steps`, passed ones first and then failed ones.
        public var omittedSteps: Int
        /// Failures whose `reason`, `expected` or `actual` was clipped to 512 characters; a file written before the field decodes as `0`.
        public var clippedFailures: Int

        public init(omittedSteps: Int, clippedFailures: Int = 0) {
            self.omittedSteps = omittedSteps
            self.clippedFailures = clippedFailures
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            omittedSteps = try container.decode(Int.self, forKey: .omittedSteps)
            clippedFailures = try container.decodeIfPresent(Int.self, forKey: .clippedFailures) ?? 0
        }
    }
}
