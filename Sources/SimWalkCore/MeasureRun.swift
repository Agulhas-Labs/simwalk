//
// Copyright © Agulhas Labs
//

import Foundation

/// One measure run of a device walk (SimWalk#67, M4): a screen, one of its states, and how many iterations — what the host passes the runner's `testMeasure` and the runner reads back.
///
/// **Each measured screen and state is its own test run** (Brief "M4, performance on a device", ruling 3): XCTest records one set of metrics per test method, so a screen's states cannot share a run. Both ends name the variables here, in the package the runner links, so a typo on either side fails a test in `swift test` rather than measuring nothing, as ``MotionOptIn`` does for its key.
public struct MeasureRun: Equatable, Sendable {
    public let screenID: String
    public let stateSlug: String
    public let iterations: Int

    public init(screenID: String, stateSlug: String, iterations: Int) {
        self.screenID = screenID
        self.stateSlug = stateSlug
        self.iterations = iterations
    }

    /// The runs a device walk of `book` makes: every state of each measured screen (``MeasureOptIn``), in walkbook order; none when no screen is measured.
    public static func runs(for book: Walkbook) -> [MeasureRun] {
        MeasureOptIn.measuredScreens(in: book).flatMap { screen in
            screen.states.map { MeasureRun(screenID: screen.id, stateSlug: $0.slug, iterations: MeasureOptIn.iterations(for: screen) ?? Walkbook.Measure.defaultIterations) }
        }
    }

    /// `<screen>/<state>`, as the walk's answer names the run.
    public var subject: String {
        "\(screenID)/\(stateSlug)"
    }

    /// The runner's test, as `xcresulttool` names it in a result bundle's metrics.
    public static var testIdentifier: String {
        "WalkRunner/testMeasure()"
    }

    /// The variables the host sets, which `xcodebuild` forwards to the test process with the `TEST_RUNNER_` prefix stripped.
    public var hostEnvironment: [String: String] {
        [
            "TEST_RUNNER_" + Self.screenKey: screenID,
            "TEST_RUNNER_" + Self.stateKey: stateSlug,
            "TEST_RUNNER_" + Self.iterationsKey: String(iterations),
        ]
    }

    /// The run the runner's environment names, or `nil` when it names none — `testMeasure` then returns at once, as `testSession` does without a session.
    ///
    /// - Throws: ``Incomplete`` when a screen is named without a state or a positive iteration count: the host sets all three or none.
    public static func named(in environment: [String: String]) throws -> MeasureRun? {
        guard let screenID = environment[screenKey] else { return nil }
        guard let slug = environment[stateKey], !slug.isEmpty else {
            throw Incomplete(missing: stateKey)
        }
        guard let iterations = environment[iterationsKey].flatMap(Int.init), iterations > 0 else {
            throw Incomplete(missing: iterationsKey)
        }
        return MeasureRun(screenID: screenID, stateSlug: slug, iterations: iterations)
    }

    static var screenKey: String {
        "SIMWALK_MEASURE_SCREEN"
    }

    static var stateKey: String {
        "SIMWALK_MEASURE_STATE"
    }

    static var iterationsKey: String {
        "SIMWALK_MEASURE_ITERATIONS"
    }
}

public extension MeasureRun {
    /// A measure run named without one of the variables it needs.
    struct Incomplete: Error, Equatable, CustomStringConvertible {
        public let missing: String

        public var description: String {
            "measure run: \(missing) is missing or invalid — the host sets the screen, the state and the iterations together"
        }
    }
}
