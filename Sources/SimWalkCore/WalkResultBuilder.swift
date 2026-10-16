//
// Copyright © Agulhas Labs
//

import Foundation

/// Builds a walk's ``WalkResult`` from the manifest it wrote (`Docs/SIMWALK-PROGRESS.md` §4).
///
/// **One count, three readings.** Each step's outcome, `counts` and the `failed` verdict all come from a single ``WalkProgress/Matches`` fold, so the result cannot disagree with the progress file's `matches` about what passed. **Failures are never dropped**: over the cap, passed steps go from the end first, then failed ones (each still whole in `failures`); still over, every failure's text is clipped to 512 characters; and a result whose failures alone still exceed the cap is written over it rather than without them.
public struct WalkResultBuilder {
    /// The face the result names, as the progress file does: `walk`, `walk --dry-run` or `session`.
    ///
    /// A property of the builder rather than one set on the result afterwards, so the cap is measured with it in.
    public var tool: String

    public init(tool: String = "walk") {
        self.tool = tool
    }

    /// The result for `manifest`, the bundle at `bundleURL` holding it; capped at `byteLimit` bytes unless `verbose`, which adds each step's states and completed route.
    public func build(
        manifest: CaptureManifest,
        bundleURL: URL,
        timings: PhaseTimings,
        logPath: String?,
        verbose: Bool = false,
        byteLimit: Int = 16 * 1024
    ) -> WalkResult {
        var matches = WalkProgress.Matches(planned: manifest.screens.count)
        var steps: [WalkResult.Step] = []
        var failures: [WalkResult.Failure] = []
        for (offset, screen) in manifest.screens.enumerated() {
            let passedBefore = matches.passed
            matches.record(screen.outcome)
            let read = ScreenReading(screen: screen, index: offset + 1, bundleURL: bundleURL)
            steps.append(read.step(passed: matches.passed > passedBefore, verbose: verbose))
            if let failure = read.failure(passed: matches.passed > passedBefore) {
                failures.append(failure)
            }
        }
        let refused = manifest.screens.contains { screen in
            if case .buildMismatch = screen.outcome {
                true
            } else {
                false
            }
        }
        let verdict: WalkResult.Verdict = if refused {
            .refused
        } else if matches.failed > 0 {
            .failed
        } else {
            .passed
        }
        let full = WalkResult(
            schemaVersion: WalkResult.currentSchemaVersion,
            tool: tool,
            verdict: verdict,
            walkName: manifest.walkName,
            app: manifest.appBundleID,
            device: WalkProgress.Device(manifest.device),
            bundlePath: bundleURL.path,
            logPath: logPath,
            timings: timings,
            counts: WalkResult.Counts(planned: matches.planned, passed: matches.passed, failed: matches.failed),
            steps: steps,
            failures: failures,
            truncated: WalkResult.Truncated(omittedSteps: 0)
        )
        return verbose ? full : Self.fitting(full, within: byteLimit)
    }

    /// The longest a failure's `reason`, `expected` or `actual` identifier gets once the cap has to clip them.
    static let clipLength = 512

    /// `result` brought within `byteLimit` where it can be: passed steps dropped from the end, then failed ones, then every failure's long text clipped at once.
    ///
    /// A dropped failed step keeps its whole `failures` entry, and no entry is ever dropped, so a result can still come back over the limit.
    static func fitting(_ result: WalkResult, within byteLimit: Int) -> WalkResult {
        var fitted = result
        for outcome in [WalkResult.Outcome.passed, .failed] {
            while let index = lastStep(in: fitted, outcome: outcome, within: byteLimit) {
                fitted.steps.remove(at: index)
                fitted.truncated.omittedSteps += 1
            }
        }
        if fitted.encodedSize > byteLimit {
            fitted.failures = fitted.failures.map { failure in
                let clipped = failure.clipped(to: clipLength)
                if clipped != failure {
                    fitted.truncated.clippedFailures += 1
                }
                return clipped
            }
        }
        return fitted
    }

    /// The last step of `result` with `outcome` when it encodes over `byteLimit`; `nil` once it fits.
    private static func lastStep(in result: WalkResult, outcome: WalkResult.Outcome, within byteLimit: Int) -> Int? {
        guard result.encodedSize > byteLimit else { return nil }
        return result.steps.lastIndex { $0.outcome == outcome }
    }
}

private extension WalkResult.Failure {
    /// This failure with `reason`, `expected` and each `actual` identifier cut to `length` characters, ending in `…`.
    func clipped(to length: Int) -> WalkResult.Failure {
        func clip(_ text: String) -> String {
            text.count > length ? text.prefix(length - 1) + "…" : text
        }
        var copy = self
        copy.reason = clip(reason)
        copy.expected = expected.map(clip)
        copy.actual = actual?.map { $0.map(clip) }
        return copy
    }
}

private extension WalkResultBuilder {
    /// One screen of the manifest, read for the result.
    struct ScreenReading {
        let screen: CaptureManifest.ScreenRecord
        let index: Int
        let bundleURL: URL

        func step(passed: Bool, verbose: Bool) -> WalkResult.Step {
            var step = WalkResult.Step(index: index, screen: screen.id, outcome: passed ? .passed : .failed)
            if passed {
                step.screenshotPath = firstScreenshotPath
            } else {
                step.kind = kind
                step.reason = reason
            }
            if verbose {
                step.states = screen.captures.map { capture in
                    WalkResult.State(slug: capture.state.slug, screenshotPath: absolute(capture.screenshotPath), axTreePath: absolute(capture.axTreePath))
                }
                step.routeTaken = screen.routeTaken.rendered
            }
            return step
        }

        func failure(passed: Bool) -> WalkResult.Failure? {
            guard !passed else { return nil }
            var failure = WalkResult.Failure(index: index, screen: screen.id, kind: kind, reason: reason, screenshotPath: firstScreenshotPath)
            switch screen.outcome {
            case let .unexpectedScreen(expected, found, _):
                failure.expected = expected
                failure.actual = found
            case let .unreachable(routeTried, _, _, _):
                // The step the runner was reaching for. The manifest records the steps taken, not the identifiers of the screen the walk stopped on, so `actual` stays `nil`.
                failure.expected = routeTried.last?.description
            default:
                break
            }
            return failure
        }

        /// The first capture's screenshot, absolute, through the layout rather than spelt here.
        private var firstScreenshotPath: String? {
            screen.captures.first.map { absolute($0.screenshotPath) }
        }

        private func absolute(_ relativePath: String) -> String {
            CaptureBundleLayout.url(forRelativePath: relativePath, in: bundleURL).path
        }

        /// The `ScreenOutcome` case name.
        private var kind: String {
            switch screen.outcome {
            case .captured: "captured"
            case .unreachable: "unreachable"
            case .buildMismatch: "buildMismatch"
            case .captureFailed: "captureFailed"
            case .stateNotApplied: "stateNotApplied"
            case .unexpectedScreen: "unexpectedScreen"
            }
        }

        /// One line a pane can show: the route tried for an unreachable screen, both hashes for a build mismatch, the outcome's own reason otherwise.
        private var reason: String {
            switch screen.outcome {
            case .captured:
                CaptureBundleSummary.outcomeWords(screen.outcome)
            case let .unreachable(routeTried, reason, _, state):
                (state.map { "\($0.clause), " } ?? "") + "route tried: \(routeTried.rendered)" + (reason.map { " — \($0)" } ?? "")
            case let .buildMismatch(expected, found):
                "build mismatch: expected \(expected), found \(found)"
            case let .captureFailed(reason), let .stateNotApplied(reason):
                reason
            case let .unexpectedScreen(_, _, reason):
                reason ?? CaptureBundleSummary.outcomeWords(screen.outcome)
            }
        }
    }
}
