//
// Copyright © Agulhas Labs
//

import XCTest

/// Guards the assumption the whole capture path rests on: **the runner can put a capture bundle on the host's disk.**
///
/// The runner executes on the simulator, so everything it writes lands wherever the simulator says its filesystem is. If that were only the app container, every walk would end with a second step — pull the bundle out with `simctl get_app_container`, or route it through `XCTAttachment` and dig it out of the `.xcresult` — and that step would have to be designed rather than discovered. It is not: arbitrary host paths are writable directly, verified 2026-08-17 down to the exact directory a driver names, so `CaptureBundleWriter` does the whole job (Brief §7.4).
///
/// These assert rather than report, because the finding is settled and what is worth keeping is the alarm: if a later OS or Xcode sandboxes the runner, this fails in one fast run naming the consequence, instead of leaving a walk mysteriously producing an empty directory.
final class HostReachabilityProbe: XCTestCase {
    /// The host path the driver actually asked for is the one that matters, so the probe checks that before any fallback.
    func testTheRunnerCanWriteWhereTheDriverPointsIt() throws {
        let requested = ProcessInfo.processInfo.environment["SIMWALK_OUTPUT"]
        let directory = requested.map { URL(fileURLWithPath: $0).deletingLastPathComponent() }
            ?? URL(fileURLWithPath: "/private/tmp")

        try assertRoundTrip(in: directory)
    }

    /// The host's own home, reported to the simulator as `SIMULATOR_HOST_HOME` — the cleanest single piece of evidence that the host filesystem is visible from in here at all.
    func testTheHostFilesystemIsVisibleFromInsideTheSimulator() throws {
        let hostHome = try XCTUnwrap(
            ProcessInfo.processInfo.environment["SIMULATOR_HOST_HOME"],
            "SIMULATOR_HOST_HOME is unset — the runner cannot see the host's filesystem, so a capture bundle would have to be extracted from the simulator container instead of written to the path the driver names"
        )

        try assertRoundTrip(in: URL(fileURLWithPath: hostHome))
    }

    /// Whether the runner can see SpringBoard, which is what the permission-sheet tap depends on — the capability XCUITest was chosen for over window-poking from the host (Brief §2.1).
    func testSpringBoardIsReachable() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")

        XCTAssertTrue(springboard.exists, "SpringBoard is not reachable from the runner process, so a walk could not answer a permission sheet")
    }

    private func assertRoundTrip(in directory: URL, file: StaticString = #filePath, line: UInt = #line) throws {
        let target = directory.appendingPathComponent("simwalk-probe-\(UUID().uuidString).txt")
        let written = Data("probe".utf8)
        do {
            try written.write(to: target)
        } catch {
            XCTFail("the runner cannot write to \(directory.path): \(error.localizedDescription) — a capture bundle can no longer be written to the path the driver names, and the write side needs a way out of the simulator container", file: file, line: line)
            return
        }
        defer { try? FileManager.default.removeItem(at: target) }

        XCTAssertEqual(try Data(contentsOf: target), written, "wrote to \(target.path) but read back something else", file: file, line: line)
    }
}
