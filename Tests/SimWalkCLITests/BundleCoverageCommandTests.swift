//
// Copyright © Agulhas Labs
//

import ArgumentParser
import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkTestSupport
import Testing

/// `bundle coverage`'s verdict line and exit code — the half a pipeline reads.
///
/// Uncovered controls are a qualified answer, on `bundle audit`'s rule: the report is printed either way, so only the code can tell a script there is a step to add.
struct BundleCoverageCommandTests {
    /// A bundle whose every control is a route's target is the plain `ok`, and exits 0.
    @Test
    func aBundleWhoseEveryControlIsRoutedExitsZero() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory, routeTaken: [.tab(label: "Progress"), .tap(label: "Filter")])
        let recorder = StreamRecorder()

        try Self.command(for: bundle).run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError)

        #expect(recorder.out.first?.components(separatedBy: "\n").dropFirst().first == "ok — read 1 of 1 screen, 2 controls reachable")
        #expect(recorder.err.isEmpty)
    }

    /// A control no route reaches is named as the step that would, and the call exits with the qualified code.
    @Test
    func aControlNoRouteReachesExitsWithTheQualifiedCode() throws {
        let directory = try TemporaryDirectory()
        let bundle = try Self.bundle(in: directory, routeTaken: [.tab(label: "Progress")])
        let recorder = StreamRecorder()

        let thrown = try #require(#expect(throws: ExitCode.self) {
            try Self.command(for: bundle).run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError)
        })

        #expect(thrown == ExitCode(AnswerVerdict.qualifiedExitCode))
        let lines = try #require(recorder.out.first).components(separatedBy: "\n")
        #expect(lines[1] == "qualified — 1 control no route step covers, on 1 screen · read 1 of 1 screen, 2 controls reachable")
        #expect(Array(lines[2 ... 3]) == ["progress: 1 uncovered control", "  tap 'Filter'"])
        let entry = try #require(try UsageReport.entries(at: Self.log(in: directory).fileURL).entries.first)
        #expect(entry.tool == "bundle coverage")
    }

    /// One screen with a selected tab and a `Filter` button, walked by `routeTaken`.
    private static func bundle(in directory: TemporaryDirectory, routeTaken: [Walkbook.RouteStep]) throws -> CaptureBundle {
        let tree = AXNode(
            type: "Application",
            frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
            children: [
                AXNode(type: "Button", frame: AXNode.Frame(x: 16, y: 120, width: 80, height: 32), label: "Filter"),
                AXNode(
                    type: "TabBar",
                    frame: AXNode.Frame(x: 0, y: 791, width: 402, height: 83),
                    children: [AXNode(type: "Button", frame: AXNode.Frame(x: 25, y: 795, width: 85, height: 54), label: "Progress", isSelected: true)]
                ),
            ]
        )
        return try CaptureBundleFixture.writeWalk(in: directory, screens: [
            CaptureBundleFixture.ScreenSpec(
                id: "progress",
                routeTaken: routeTaken,
                captures: [CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: .light), tree: tree)]
            ),
        ])
    }

    private static func command(for bundle: CaptureBundle) throws -> BundleCoverageCommand {
        try BundleCoverageCommand.parse([bundle.url.path])
    }

    private static func log(in directory: TemporaryDirectory) -> UsageLog {
        UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
    }
}
