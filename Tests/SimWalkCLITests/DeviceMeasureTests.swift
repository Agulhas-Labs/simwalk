//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCLI
import SimWalkCore
import SimWalkDriver
import SimWalkTestSupport
import Testing

/// A device walk's measure runs (SimWalk#67, M4): one `testMeasure` run per measured screen and state before the walk, each read with `xcresulttool` and its result bundle deleted, the records passed to the walk, a failed run named without failing the walk.
struct DeviceMeasureTests {
    /// `general` is measured (two states); `today` is not.
    static var walkbook: String {
        #"{"name":"w","appBundleID":"com.apple.Preferences","screens":[{"id":"general","route":[{"tab":{"label":"General"}}],"states":[{"theme":"light"},{"theme":"dark"}],"measure":true},{"id":"today","route":[{"tab":{"label":"Progress"}}],"states":[{"theme":"light"}]}]}"#
    }

    /// What `xcresulttool get test-results metrics` printed for a measure run on an iPad (the core's committed fixture).
    static func metricsJSON() throws -> String {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("SimWalkCoreTests/Fixtures/xcresult-metrics-ipad-settings.json")
        return try String(contentsOf: url, encoding: .utf8)
    }

    static func isMeasure(_ call: DeviceWalkCommandTests.Call) -> Bool {
        call.arguments.contains("-only-testing:SimWalkRunner/WalkRunner/testMeasure")
    }

    static func isWalk(_ call: DeviceWalkCommandTests.Call) -> Bool {
        call.arguments.contains("-only-testing:SimWalkRunner/WalkRunner/testWalk")
    }

    static func isMetricsRead(_ call: DeviceWalkCommandTests.Call) -> Bool {
        call.arguments.starts(with: ["xcresulttool", "get", "test-results", "metrics"])
    }

    /// A phone whose measure runs make their result bundle and succeed, except a state named in `failing`, and whose `xcresulttool` prints the fixture.
    static func phone(failing: Set<String> = [], keep: TemporaryDirectory) throws -> DeviceWalkCommandTests.Phone {
        let metrics = try metricsJSON()
        let phone = DeviceWalkCommandTests().phone(appearances: [DeviceWalkCommandTests.appearance("light")], keep: keep)
        phone.answering = { call in
            if isMeasure(call) {
                // The bundle the run writes, so a test can see it removed; a run named without one makes none.
                if let path = call.arguments.firstIndex(of: "-resultBundlePath").map({ call.arguments[$0 + 1] }) {
                    try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
                }
                if failing.contains(call.environment["TEST_RUNNER_SIMWALK_MEASURE_STATE"] ?? "") {
                    return Shell.Result(status: 65, standardOutput: "WalkRunner.swift:200: error: -[WalkRunner testMeasure] : measure general/dark: route step 0 did not land", standardError: "** TEST FAILED **")
                }
                return Shell.Result(status: 0, standardOutput: "", standardError: "")
            }
            return isMetricsRead(call) ? Shell.Result(status: 0, standardOutput: metrics, standardError: "") : nil
        }
        return phone
    }

    static func expectedRecord() throws -> CaptureManifest.Performance {
        try XCResultMetrics.performance(from: Data(metricsJSON().utf8), test: "WalkRunner/testMeasure()", iterations: 3)
    }

    @Test
    func aMeasuredScreenOfTwoStatesRunsTwoMeasureRunsBeforeTheWalkEachReadByXcresulttool() throws {
        let fixture = try DeviceWalkCommandTests.Fixture(walkbook: Self.walkbook)
        let keep = try TemporaryDirectory()
        let phone = try Self.phone(keep: keep)

        let answer = try fixture.answer(phone)

        let runs = phone.calls.filter { Self.isMeasure($0) || Self.isWalk($0) || Self.isMetricsRead($0) }
        #expect(runs.map { Self.isMeasure($0) ? "measure" : Self.isWalk($0) ? "walk" : "metrics" } == ["measure", "metrics", "measure", "metrics", "walk"])
        let measures = runs.filter(Self.isMeasure)
        #expect(measures.map { $0.environment["TEST_RUNNER_SIMWALK_MEASURE_SCREEN"] } == ["general", "general"])
        #expect(measures.map { $0.environment["TEST_RUNNER_SIMWALK_MEASURE_STATE"] } == ["light", "dark"])
        #expect(measures.allSatisfy { $0.environment["TEST_RUNNER_SIMWALK_MEASURE_ITERATIONS"] == "3" })
        #expect(measures.allSatisfy { $0.arguments.contains("test-without-building") && $0.arguments.contains { $0.contains("platform=iOS,id=\(DeviceWalkCommandTests.udid)") } })
        #expect(measures.allSatisfy { $0.environment["TEST_RUNNER_SIMWALK_WALKBOOK_JSON"] == Self.walkbook })
        // Each read names the bundle its run wrote.
        let bundles = measures.compactMap { call in call.arguments.firstIndex(of: "-resultBundlePath").map { call.arguments[$0 + 1] } }
        #expect(runs.filter(Self.isMetricsRead).map(\.arguments.last) == bundles)
        #expect(Set(bundles).count == 2)
        #expect(answer.residue.contains("measured general/light: 3 iterations, launch 307 ms, cpu 1347 ms, memory peak 62.5 MB, transition hitches 0"))
        #expect(answer.residue.contains("measured general/dark: 3 iterations, launch 307 ms, cpu 1347 ms, memory peak 62.5 MB, transition hitches 0"))
        #expect(answer.verdict == .unqualified("1 of 1 screens captured · 1 capture"))
    }

    /// G2: the walk's runner is handed both records, keyed by screen and state, and so files them on the manifest.
    @Test
    func theWalkReceivesEveryRecordInItsEnvironment() throws {
        let fixture = try DeviceWalkCommandTests.Fixture(walkbook: Self.walkbook)
        let keep = try TemporaryDirectory()
        let phone = try Self.phone(keep: keep)

        _ = try fixture.answer(phone)

        let walk = try #require(phone.calls.first(where: Self.isWalk))
        let json = try #require(walk.environment[MeasuredPerformance.hostEnvironmentKey])
        let sent = try MeasuredPerformance.read(from: [MeasuredPerformance.environmentKey: json])
        let expected = try Self.expectedRecord()

        #expect(sent.performance(screenID: "general", stateSlug: "light") == expected)
        #expect(sent.performance(screenID: "general", stateSlug: "dark") == expected)
        #expect(sent.performance(screenID: "today", stateSlug: "light") == nil)
    }

    @Test
    func aFailedMeasureRunIsNamedWithItsReasonAndTheWalkGoesOnWithoutItsRecord() throws {
        let fixture = try DeviceWalkCommandTests.Fixture(walkbook: Self.walkbook)
        let keep = try TemporaryDirectory()
        let phone = try Self.phone(failing: ["dark"], keep: keep)

        let answer = try fixture.answer(phone)

        // The failed run's bundle is not read; the walk still runs.
        #expect(phone.calls.filter(Self.isMetricsRead).count == 1)
        let walk = try #require(phone.calls.first(where: Self.isWalk))
        let sent = try MeasuredPerformance.read(from: [MeasuredPerformance.environmentKey: #require(walk.environment[MeasuredPerformance.hostEnvironmentKey])])
        #expect(sent.performance(screenID: "general", stateSlug: "light") != nil)
        #expect(sent.performance(screenID: "general", stateSlug: "dark") == nil)
        let failure = try #require(answer.residue.first { $0.hasPrefix("measure run general/dark failed, no record: ") })
        #expect(failure.contains("route step 0 did not land"))
        #expect(answer.residue.contains { $0.hasPrefix("measured general/light: ") })
        guard case let .qualified(qualifications, _) = answer.verdict else {
            Issue.record("a failed measure run qualifies the verdict: \(answer.verdict)")
            return
        }
        #expect(qualifications == ["1 measure run left no record"])
    }

    @Test
    func aWalkbookWithNoMeasuredScreenRunsNoMeasureRunAndSendsNoRecords() throws {
        let fixture = try DeviceWalkCommandTests.Fixture()
        let keep = try TemporaryDirectory()
        let phone = try Self.phone(keep: keep)

        let answer = try fixture.answer(phone)

        #expect(!phone.calls.contains(where: Self.isMeasure))
        #expect(!phone.calls.contains(where: Self.isMetricsRead))
        let walk = try #require(phone.calls.first(where: Self.isWalk))
        #expect(walk.environment[MeasuredPerformance.hostEnvironmentKey] == nil)
        #expect(!answer.residue.contains { $0.hasPrefix("measure") })
    }

    @Test
    func screensExcludingTheMeasuredScreenRunNoMeasureRun() throws {
        let fixture = try DeviceWalkCommandTests.Fixture(walkbook: Self.walkbook)
        let keep = try TemporaryDirectory()
        let phone = try Self.phone(keep: keep)
        let walk = DeviceWalk(walkbook: fixture.walkbookPath, requestedUDID: DeviceWalkCommandTests.udid, lease: nil, team: "TEAM", runnerBundleID: nil, app: nil, output: fixture.output, screens: ["today"], settle: nil, motion: false)

        _ = try walk.answer(shell: phone.shell, builds: fixture.builds, resolveRunner: fixture.source(), leases: fixture.leases, holderPID: fixture.holderPID)

        #expect(!phone.calls.contains(where: Self.isMeasure))
        #expect(phone.calls.contains(where: Self.isWalk))
    }

    @Test
    func everyMeasureResultBundleIsRemovedOnceRead() throws {
        let fixture = try DeviceWalkCommandTests.Fixture(walkbook: Self.walkbook)
        let keep = try TemporaryDirectory()
        let phone = try Self.phone(failing: ["dark"], keep: keep)

        _ = try fixture.answer(phone)

        let bundles = phone.calls.filter(Self.isMeasure).compactMap { call in call.arguments.firstIndex(of: "-resultBundlePath").map { call.arguments[$0 + 1] } }

        #expect(bundles.count == 2)
        #expect(bundles.allSatisfy { $0.hasPrefix(fixture.builds.directory.path) && $0.contains("/Logs/Test/") })
        #expect(bundles.allSatisfy { !FileManager.default.fileExists(atPath: $0) })
    }

    /// A runner that failed before its test leaves a bundle with no activities for it, only a summary of failures (SimWalk#124): the run's failure carries that text, read before the bundle is deleted.
    @Test
    func aMeasureRunThatFailedBeforeItsTestNamesTheBundlesDiagnosis() throws {
        let fixture = try DeviceWalkCommandTests.Fixture(walkbook: Self.walkbook)
        let keep = try TemporaryDirectory()
        let phone = try Self.phone(failing: ["dark"], keep: keep)
        let measureAnswering = phone.answering
        let summary = #"{"testFailures":[{"testName":"WalkRunner/testMeasure()","failureText":"Timed out while enabling automation mode"}]}"#
        phone.answering = { call in
            if call.arguments.starts(with: ["xcresulttool", "get", "test-results", "activities"]) {
                return Shell.Result(status: 0, standardOutput: "", standardError: "")
            }
            if call.arguments.starts(with: ["xcresulttool", "get", "test-results", "summary"]) {
                return Shell.Result(status: 0, standardOutput: summary, standardError: "")
            }
            return try measureAnswering(call)
        }

        let answer = try fixture.answer(phone)

        let read = try #require(phone.calls.first { $0.arguments.starts(with: ["xcresulttool", "get", "test-results", "activities"]) })
        #expect(read.arguments.contains("WalkRunner/testMeasure()"))
        let failure = try #require(answer.residue.first { $0.hasPrefix("measure run general/dark failed, no record: ") })
        #expect(failure.contains("failure: Timed out while enabling automation mode (WalkRunner/testMeasure())"))
    }

    @Test
    func aMeasureRunWhoseXcresulttoolExitsNonZeroFailsNamingItAndTheWalkGoesOn() throws {
        let fixture = try DeviceWalkCommandTests.Fixture(walkbook: Self.walkbook)
        let keep = try TemporaryDirectory()
        let phone = try Self.phone(keep: keep)
        let measureAnswering = phone.answering
        phone.answering = { call in
            Self.isMetricsRead(call) ? Shell.Result(status: 1, standardOutput: "", standardError: "Error: not a bundle") : try measureAnswering(call)
        }

        let answer = try fixture.answer(phone)

        #expect(answer.residue.contains("measure run general/light failed, no record: xcresulttool could not read the result bundle's metrics: Error: not a bundle"))
        #expect(answer.residue.contains { $0.hasPrefix("measure run general/dark failed, no record: ") })
        #expect(phone.calls.contains(where: Self.isWalk))
    }

    @Test
    func aMeasureRunWhoseXcresulttoolTimesOutFailsNamingItAndTheWalkGoesOn() throws {
        let fixture = try DeviceWalkCommandTests.Fixture(walkbook: Self.walkbook)
        let keep = try TemporaryDirectory()
        let phone = try Self.phone(keep: keep)
        let measureAnswering = phone.answering
        phone.answering = { call in
            if Self.isMetricsRead(call) {
                throw ShellError.timedOut(command: "xcrun xcresulttool get test-results metrics", seconds: 120)
            }
            return try measureAnswering(call)
        }

        let answer = try fixture.answer(phone)

        let failure = try #require(answer.residue.first { $0.hasPrefix("measure run general/light failed, no record: ") })

        #expect(failure.contains("xcresulttool"))
        #expect(failure.contains("did not finish within 120s"))
        #expect(phone.calls.contains(where: Self.isWalk))
    }

    /// The lease is renewed before each run, so one that lapses between two runs refuses before the second.
    @Test
    func aLeaseThatLapsesBetweenMeasureRunsIsRefusedBeforeTheNextRun() throws {
        let fixture = try DeviceWalkCommandTests.Fixture(walkbook: Self.walkbook)
        let keep = try TemporaryDirectory()
        let phone = try Self.phone(keep: keep)
        let lease = try fixture.leases.acquire(udid: DeviceWalkCommandTests.udid, ttl: 300, holderPID: 99, now: Date(), physicalDevice: true)
        phone.onCall = { call in
            if Self.isMetricsRead(call) {
                _ = try? fixture.leases.remove(udid: DeviceWalkCommandTests.udid, token: lease.token)
            }
        }

        let thrown = try #require(#expect(throws: DeviceWalkRefusal.self) { try fixture.answer(phone, device: ["--lease", lease.token]) })

        #expect(thrown.description.contains("no lease carries that token"))
        #expect(phone.calls.filter(Self.isMeasure).count == 1)
        #expect(!phone.calls.contains(where: Self.isWalk))
    }

    @Test
    func aDeviceWalkOfMoreThanTwentyMeasuredScreenStatesNotesTheLaunchEnvironment() throws {
        let screens = (0 ..< 21).map { #"{"id":"s\#($0)","route":[{"tab":{"label":"General"}}],"states":[{"theme":"light"}],"measure":{"iterations":1}}"# }
        let book = #"{"name":"w","appBundleID":"com.apple.Preferences","screens":[\#(screens.joined(separator: ","))]}"#
        let fixture = try DeviceWalkCommandTests.Fixture(walkbook: book)
        let keep = try TemporaryDirectory()
        let phone = try Self.phone(keep: keep)

        let answer = try fixture.answer(phone)

        #expect(answer.residue.contains { $0.hasPrefix("measure: 21 screen-states — each adds about 3 KB") })
    }
}
