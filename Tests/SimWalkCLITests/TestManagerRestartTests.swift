//
// Copyright © Agulhas Labs
//

import Fieldwork
import Foundation
@testable import SimWalkCLI
@testable import SimWalkCore
import SimWalkDriver
import SimWalkTestSupport
import Testing

/// SimWalk#173: a walk whose Apple audit timed out on a device restarts that device's `testmanagerd` before it gives the device back.
struct TestManagerRestartTests {
    /// What the runner records when XCTest's audit gives up at its own bound.
    static let timedOut = AppleAuditRecord(milliseconds: 15009, error: #"Error Domain=com.apple.xcode.xctest.accessibilityAudit Code=-56 "Audit failed to complete in time" UserInfo={NSLocalizedDescription=Audit failed to complete in time}"#)

    /// The restart's one call on `udid`.
    static func restart(_ udid: String) -> [String] {
        ["simctl", "spawn", udid, "launchctl", "kill", "SIGKILL", "user/foreground/com.apple.testmanagerd"]
    }

    /// `launchctl`'s reply to the restart: `status`, and `error` on standard error.
    static func reply(status: Int32, _ error: String) -> Shell.Result {
        Shell.Result(status: status, standardOutput: "", standardError: error)
    }

    @Test
    func aWalkWhoseAuditTimedOutRestartsTestmanagerdOnItsDeviceBeforeTheLeaseGoes() throws {
        let walk = try SerialWalk(audits: [Self.timedOut, Self.timedOut])

        let outcome = try walk.run()

        #expect(walk.script.calls.filter { $0.arguments == Self.restart("UDID-1") }.count == 1)
        #expect(walk.leasedAtRestart == [["UDID-1"]])
        #expect(walk.leases.all().isEmpty)
        #expect(outcome.servedAnswer().residue.contains("apple audit: 2 audits timed out (progress [light, dark]); testmanagerd on iPhone 17 Pro was restarted, since it keeps computing a timed-out audit until it stops"))
    }

    @Test
    func aWalkWhoseAuditsDidNotTimeOutSpawnsNothingForTestmanagerd() throws {
        let other = AppleAuditRecord(milliseconds: 900, error: #"Error Domain=com.apple.xcode.xctest.accessibilityAudit Code=-1 "Audit failed""#)
        let walk = try SerialWalk(audits: [AppleAuditRecord(milliseconds: 2000), other])

        let outcome = try walk.run()

        #expect(!walk.script.calls.contains { $0.arguments.contains("launchctl") })
        #expect(!outcome.servedAnswer().residue.contains { $0.contains("testmanagerd") })
    }

    @Test
    func aRestartThatFailsIsSaidAndLeavesTheVerdictAsItWas() throws {
        let restarted = try SerialWalk(audits: [Self.timedOut, AppleAuditRecord(milliseconds: 2000)]).run()
        let walk = try SerialWalk(audits: [Self.timedOut, AppleAuditRecord(milliseconds: 2000)], restartReply: Self.reply(status: 1, "Could not kill service\n"))

        let outcome = try walk.run()

        #expect(walk.script.calls.filter { $0.arguments == Self.restart("UDID-1") }.count == 1)
        #expect(outcome.servedAnswer().residue.contains("apple audit: 1 audit timed out (progress [light]); testmanagerd on iPhone 17 Pro could not be restarted (Could not kill service); it may keep a core busy until the device shuts down"))
        #expect(outcome.answer().verdict == restarted.answer().verdict)
    }

    @Test
    func aTestmanagerdThatHadAlreadyStoppedIsNotAFailedRestart() throws {
        // What launchctl answers, exit 3 (ESRCH), when the service has no process: measured on iOS 27.0.
        let walk = try SerialWalk(audits: [Self.timedOut, AppleAuditRecord(milliseconds: 2000)], restartReply: Self.reply(status: 3, "No process to signal.\n"))

        let outcome = try walk.run()

        #expect(outcome.servedAnswer().residue.contains("apple audit: 1 audit timed out (progress [light]); testmanagerd on iPhone 17 Pro had already stopped, so nothing was left computing it"))
        #expect(!outcome.servedAnswer().residue.contains { $0.contains("could not be restarted") })
    }

    @Test
    func aParallelWalkRestartsTestmanagerdOnlyOnTheShardWhoseAuditTimedOutBeforeItsDeviceGoes() throws {
        let machine = try ParallelWalkTests.Machine(auditTimedOut: ["browse"])

        let outcome = try machine.walk(machine.command())

        let calls = machine.script.calls
        let clone = ParallelWalkTests.ParallelScript.clone
        #expect(calls.filter { $0.contains("launchctl") } == [Self.restart(clone)])
        let restart = try #require(calls.firstIndex(of: Self.restart(clone)))
        let delete = try #require(calls.firstIndex(of: ["simctl", "delete", clone]))
        #expect(restart < delete)
        #expect(outcome.servedAnswer().residue.contains("apple audit: 1 audit timed out (browse [light]); testmanagerd on iPhone 17 Pro (SimWalk lease) was restarted, since it keeps computing a timed-out audit until it stops"))
    }

    /// A shard whose audit timed out, stopped in its appearance retry by the other shard's failure, still holds its device: the failure's stop never refuses its restart, which runs before the lease goes, and its note is under the shard in the refusal.
    @Test
    func aShardStoppedByTheOtherShardsFailureStillRestartsTestmanagerdBeforeItsDeviceGoes() throws {
        let machine = try ParallelWalkTests.Machine(mode: .cloneFailsDuringRetry, firstShardRefusedOnAppearance: true, auditTimedOut: ["progress"])

        let refusal = try #require(#expect(throws: ParallelWalkRefusal.self) {
            try machine.walk(machine.command())
        })

        #expect(machine.script.stoppedRunners == ["UDID-1"])
        #expect(machine.script.calls.filter { $0.contains("launchctl") } == [Self.restart("UDID-1")])
        #expect(machine.script.leasedAtRestart.map { $0.contains("UDID-1") } == [true])
        #expect(refusal.others.contains("  apple audit: 1 audit timed out (progress [light]); testmanagerd on iPhone 17 Pro was restarted, since it keeps computing a timed-out audit until it stops"))
    }

    /// A shard that failed after the first, its runner crashed after its audit timed out and before it finalised its manifest, refuses: its device's testmanagerd is restarted from the records on disk, and the note is under the shard in the parallel refusal (SimWalk#193).
    @Test
    func aShardWhoseBundleCannotBeReadSaysItRestartedTestmanagerdInTheParallelRefusal() throws {
        let machine = try ParallelWalkTests.Machine(mode: .cloneCrashesBeforeItsManifestAfterShardZeroFails, auditTimedOut: ["browse"])
        let clone = ParallelWalkTests.ParallelScript.clone

        let refusal = try #require(#expect(throws: ParallelWalkRefusal.self) {
            try machine.walk(machine.command())
        })

        #expect(machine.script.calls.filter { $0.contains("launchctl") } == [Self.restart(clone)])
        #expect(refusal.others.contains("  apple audit: 1 audit timed out (browse [light]); testmanagerd on iPhone 17 Pro (SimWalk lease) was restarted, since it keeps computing a timed-out audit until it stops"))
    }

    /// An interruption gives the device back from its handler, so a restart the walk reaches after it spawns nothing on the device, and says it was not restarted.
    @Test
    func aWalkInterruptedBeforeItsRestartSpawnsNothingForTestmanagerd() throws {
        let walk = try SerialWalk(audits: [Self.timedOut, Self.timedOut])

        let outcome = try walk.run(interruptedAtRunner: true)

        #expect(!walk.script.calls.contains { $0.arguments.contains("launchctl") })
        #expect(outcome.servedAnswer().residue.contains { $0.hasPrefix("apple audit: 2 audits timed out (progress [light, dark]); testmanagerd on iPhone 17 Pro could not be restarted (") })
    }

    /// A first-pass audit that timed out keeps testmanagerd computing it after the appearance retry walks the screen again, even though the retry's audit returned and its fold replaced the capture.
    @Test
    func aFirstPassTimeoutTheAppearanceRetryFoldsOverStillRestartsTestmanagerd() throws {
        let walk = try SerialWalk(audits: [Self.timedOut], retryAudits: [AppleAuditRecord(milliseconds: 2000), AppleAuditRecord(milliseconds: 2000)])

        let outcome = try walk.run()

        #expect(outcome.bundle.manifest.appearanceSettle?.retried.map(\.id) == ["progress"])
        #expect(AppleAuditScan(outcome.bundle).timeouts.isEmpty)
        #expect(walk.script.calls.filter { $0.arguments == Self.restart("UDID-1") }.count == 1)
        #expect(outcome.servedAnswer().residue.contains("apple audit: 1 audit timed out (progress [light]); testmanagerd on iPhone 17 Pro was restarted, since it keeps computing a timed-out audit until it stops"))
    }

    /// The retry's timed-out audit, its fold succeeding, restarts testmanagerd once and the note names it (SimWalk#195).
    ///
    /// The folded bundle carries the same audit, so this pins the behaviour but not `.folded`'s own `timeouts:`.
    @Test
    func aTimeoutInAnAppearanceRetryTheFoldKeepsRestartsTestmanagerdOnce() throws {
        let walk = try SerialWalk(audits: [AppleAuditRecord(milliseconds: 2000)], retryAudits: [AppleAuditRecord(milliseconds: 2000), Self.timedOut])

        let outcome = try walk.run()

        #expect(outcome.bundle.manifest.appearanceSettle?.retried.map(\.id) == ["progress"])
        #expect(walk.script.calls.filter { $0.arguments == Self.restart("UDID-1") }.count == 1)
        #expect(outcome.servedAnswer().residue.contains("apple audit: 1 audit timed out (progress [dark]); testmanagerd on iPhone 17 Pro was restarted, since it keeps computing a timed-out audit until it stops"))
    }

    /// An appearance retry whose bundle reads with a timed-out audit but whose fold is refused for its content leaves the first pass's bundle as it was, with no timeout in it: only the timeouts read from the retry's scratch bundle first restart testmanagerd (SimWalk#195, `.retryFailed`'s `timeouts:`).
    @Test
    func aTimeoutInAnAppearanceRetryWhoseFoldWasRefusedStillRestartsTestmanagerdOnce() throws {
        let walk = try SerialWalk(audits: [AppleAuditRecord(milliseconds: 2000)], retryAudits: [AppleAuditRecord(milliseconds: 2000), Self.timedOut], retryRecordsOtherScreens: true)

        let outcome = try walk.run()

        #expect(AppleAuditScan(outcome.bundle).timeouts.isEmpty)
        #expect(walk.script.calls.filter { $0.arguments == Self.restart("UDID-1") }.count == 1)
        #expect(outcome.servedAnswer().residue.contains("apple audit: 1 audit timed out (progress [dark]); testmanagerd on iPhone 17 Pro was restarted, since it keeps computing a timed-out audit until it stops"))
    }

    /// A runner stopped after its audits timed out, before it finalised the manifest, leaves no bundle to read but its records on disk: the device's testmanagerd is restarted once, before the lease goes, and the refusal says so (SimWalk#190).
    @Test
    func aWalkWhoseBundleCannotBeReadStillRestartsTestmanagerdFromTheRecordsOnDisk() throws {
        let walk = try SerialWalk(audits: [Self.timedOut, Self.timedOut], unreadable: .firstPass)

        let refusal = try #require(#expect(throws: WalkCommand.Refusal.self) {
            try walk.run()
        })

        #expect(walk.script.calls.filter { $0.arguments == Self.restart("UDID-1") }.count == 1)
        #expect(walk.leasedAtRestart == [["UDID-1"]])
        #expect(walk.leases.all().isEmpty)
        #expect(refusal.description.contains("apple audit: 2 audits timed out (progress [dark, light]); testmanagerd on iPhone 17 Pro was restarted, since it keeps computing a timed-out audit until it stops"))
    }

    /// A first-pass timeout, then an appearance retry that leaves the bundle unreadable: the walk refuses, its restart ran once, and the refusal carries the restart's note rather than dropping it (SimWalk#190).
    @Test
    func aWalkThatRefusesAfterItsAppearanceRetrySaysItRestartedTestmanagerd() throws {
        let walk = try SerialWalk(audits: [Self.timedOut], unreadable: .afterRetry)

        let refusal = try #require(#expect(throws: WalkCommand.Refusal.self) {
            try walk.run()
        })

        #expect(walk.script.calls.filter { $0.arguments == Self.restart("UDID-1") }.count == 1)
        #expect(refusal.description.contains("apple audit: 1 audit timed out (progress [light]); testmanagerd on iPhone 17 Pro was restarted, since it keeps computing a timed-out audit until it stops"))
    }

    /// A bundle refused as another walk's is not this walk's evidence: its timed-out records on disk spawn nothing for this device's testmanagerd, and the refusal says nothing about it (SimWalk#193).
    @Test
    func aBundleRefusedAsAnotherWalksLeavesTestmanagerdAlone() throws {
        let walk = try SerialWalk(audits: [Self.timedOut, Self.timedOut], unreadable: .anotherWalks)

        let refusal = try #require(#expect(throws: WalkCommand.Refusal.self) {
            try walk.run()
        })

        #expect(!walk.script.calls.contains { $0.arguments.contains("launchctl") })
        #expect(refusal.testManagerNote == nil)
        #expect(!refusal.description.contains("testmanagerd"))
    }

    /// An appearance retry whose runner crashed after its audit timed out leaves nothing to fold in, and its scratch bundle is removed: its records are read first, so the device's testmanagerd is restarted and the walk says so (SimWalk#193).
    @Test
    func aTimeoutInAnAppearanceRetryWhoseRunnerCrashedStillRestartsTestmanagerd() throws {
        let walk = try SerialWalk(audits: [AppleAuditRecord(milliseconds: 2000)], retryAudits: [AppleAuditRecord(milliseconds: 2000), Self.timedOut], unreadable: .retryRunnerCrashed)

        let outcome = try walk.run()

        #expect(walk.script.calls.filter { $0.arguments == Self.restart("UDID-1") }.count == 1)
        #expect(outcome.servedAnswer().residue.contains("apple audit: 1 audit timed out (progress [dark]); testmanagerd on iPhone 17 Pro was restarted, since it keeps computing a timed-out audit until it stops"))
    }

    /// A first pass that read with no timeout, then an appearance retry that leaves the walk's bundle unreadable with a timed-out record in it: the final read's records on disk restart testmanagerd (SimWalk#193).
    @Test
    func aTimeoutOnlyTheUnreadableFinalBundleRecordsStillRestartsTestmanagerd() throws {
        let walk = try SerialWalk(audits: [AppleAuditRecord(milliseconds: 2000)], unreadable: .afterRetryLeavingARecord)

        let refusal = try #require(#expect(throws: WalkCommand.Refusal.self) {
            try walk.run()
        })

        #expect(walk.script.calls.filter { $0.arguments == Self.restart("UDID-1") }.count == 1)
        #expect(refusal.description.contains("apple audit: 1 audit timed out (progress [dark]); testmanagerd on iPhone 17 Pro was restarted, since it keeps computing a timed-out audit until it stops"))
    }

    @Test
    func aTimeoutInBothPassesIsListedOnceAndTheFirstPassComesFirst() {
        let first = [AppleAuditScan.Failure(screenID: "b", stateSlug: "light", error: "x")]
        let final = [AppleAuditScan.Failure(screenID: "a", stateSlug: "light", error: "x"), AppleAuditScan.Failure(screenID: "b", stateSlug: "light", error: "x")]

        let note = TestManagerRestart.afterTimeouts([first, final], on: Simulator(udid: "UDID-1", name: "iPhone 17 Pro", osVersion: "26.5", isBooted: true), shell: Shell(script: { _, _, _ in Self.reply(status: 0, "") }))

        #expect(note?.hasPrefix("apple audit: 2 audits timed out (b [light], a [light]); ") == true)
    }

    @Test
    func theScreenListNamesThreeScreensAndCountsTheRest() {
        let timeouts = ["a", "b", "b", "c", "d", "e"].map { AppleAuditScan.Failure(screenID: $0, stateSlug: "light", error: "x") }

        #expect(TestManagerRestart.described(timeouts) == "a [light], b [light, light], c [light] and 2 more screens")
    }
}

extension TestManagerRestartTests {
    /// A serial walk of `progress` in light and dark on `UDID-1`, whose runner files `audits` for the two states.
    struct SerialWalk {
        let directory: TemporaryDirectory
        let script: WalkCommandTests.WalkScript
        let leases: LeaseStore
        let restartReply: Shell.Result
        private let walkbook: String
        private let output: URL
        private let recorder = Recorder()
        private let unreadable: Unreadable?

        /// `retryAudits`, when given, makes the first pass capture `progress` in light alone, with its dark state refused on appearance, and the appearance retry capture both states with these audits.
        ///
        /// `unreadable` leaves the walk no manifest to read where it says, its records on disk all the same.
        ///
        /// `retryRecordsOtherScreens` makes the retry's bundle record a second screen the retry was not sent for, so its fold is refused for its content and the first pass's bundle stays as it was (SimWalk#195).
        init(audits: [AppleAuditRecord], retryAudits: [AppleAuditRecord]? = nil, retryRecordsOtherScreens: Bool = false, restartReply: Shell.Result = TestManagerRestartTests.reply(status: 0, ""), unreadable: Unreadable? = nil) throws {
            directory = try TemporaryDirectory()
            self.unreadable = unreadable
            let stage = try TemporaryDirectory()
            let bundle = try Self.progress(audits: audits, refusingDark: retryAudits != nil || unreadable == .afterRetry || unreadable == .afterRetryLeavingARecord, in: stage)
            let url = directory.url.appendingPathComponent("book.json")
            try Data(#"{"name":"probe","appBundleID":"com.example.probe","screens":[{"id":"progress","route":[{"tab":{"label":"Progress"}}],"states":[{"theme":"light"},{"theme":"dark"}]}]}"#.utf8).write(to: url)
            walkbook = url.path
            output = directory.url.appendingPathComponent("walked.\(CaptureBundleLayout.directoryExtension)")
            // The staged bundle is copied out before the stage goes.
            let staged = directory.url.appendingPathComponent("staged.\(CaptureBundleLayout.directoryExtension)")
            try FileManager.default.copyItem(at: bundle.url, to: staged)
            if unreadable == .firstPass {
                try FileManager.default.removeItem(at: CaptureBundle.manifestURL(in: staged))
            }
            var retryWrites: URL?
            if let retryAudits {
                let retryStage = try TemporaryDirectory()
                let url = directory.url.appendingPathComponent("retry.\(CaptureBundleLayout.directoryExtension)")
                try FileManager.default.copyItem(at: Self.progress(audits: retryAudits, refusingDark: false, alsoRecording: retryRecordsOtherScreens, in: retryStage).url, to: url)
                if unreadable == .retryRunnerCrashed {
                    try FileManager.default.removeItem(at: CaptureBundle.manifestURL(in: url))
                }
                retryWrites = url
            }
            script = try WalkCommandTests.WalkScript(
                appPath: WalkCommandTests.fakeApp(in: directory),
                runnerStatus: 0,
                writes: (staged, output),
                retryWrites: retryWrites,
                retryStatus: unreadable == .retryRunnerCrashed ? 65 : nil
            )
            leases = WalkCommandTests.leases(in: directory)
            self.restartReply = restartReply
        }

        /// Rewrites the manifest of the bundle at `url` to carry a nonce no walk passed, as another walk writing to the same output leaves it.
        private static func stampAnotherWalksNonce(in url: URL) throws {
            let manifestURL = CaptureBundle.manifestURL(in: url)
            guard var object = try JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any] else {
                throw CocoaError(.fileReadCorruptFile)
            }
            object["nonce"] = "another-walks-nonce"
            try JSONSerialization.data(withJSONObject: object).write(to: manifestURL)
        }

        /// The device each restart call found leased, in call order.
        var leasedAtRestart: [[String]] {
            recorder.leased
        }

        /// A bundle of `progress` whose captures carry `audits`, light first; with `refusingDark`, light alone, its dark state refused on appearance.
        private static func progress(audits: [AppleAuditRecord], refusingDark: Bool, alsoRecording: Bool = false, in stage: TemporaryDirectory) throws -> CaptureBundle {
            let captures = zip([Walkbook.Theme.light, .dark], audits).map { theme, audit in
                CaptureBundleFixture.Capture(screenID: "progress", state: Walkbook.CaptureState(theme: theme), tree: CaptureBundleFixture.plainScreen(), appleAudit: audit)
            }
            let refused = refusingDark ? [Walkbook.CaptureState(theme: .dark)] : []
            let spec = CaptureBundleFixture.ScreenSpec(id: "progress", outcome: refusingDark ? .stateNotApplied(reason: "the appearance did not apply") : .captured, captures: captures, refusedStates: refused, refusedOnAppearance: refused)
            var specs = [spec]
            if alsoRecording {
                specs.append(CaptureBundleFixture.ScreenSpec(id: "browse", outcome: .captured, captures: [CaptureBundleFixture.Capture(screenID: "browse", state: Walkbook.CaptureState(theme: .light), tree: CaptureBundleFixture.plainScreen())]))
            }
            return try CaptureBundleFixture.writeWalk(in: stage, screens: specs, appBundleID: "com.example.probe")
        }

        /// The walk on the script; `interruptedAtRunner` interrupts it as its runner starts, as a SIGINT or SIGTERM would.
        ///
        /// The cancel is raised on the walk's own thread, which cannot hand the device back while it waits, so the interruption waits for no handback (SimWalk#187).
        func run(interruptedAtRunner: Bool = false) throws -> WalkCommand.Outcome {
            let command = try WalkCommand.parse([walkbook, "--output", output.path, "--device", "UDID-1"])
            let interruption = interruptedAtRunner ? Cancellation() : nil
            let (script, leases, recorder, restartReply, output) = (script, leases, recorder, restartReply, output)
            let unreadable = unreadable
            let shell = Shell(script: { executable, arguments, environment in
                if arguments.contains("test-without-building") {
                    interruption?.cancel()
                    recorder.runners += 1
                    if unreadable == .afterRetry || unreadable == .afterRetryLeavingARecord, recorder.runners == 2 {
                        try FileManager.default.removeItem(at: CaptureBundle.manifestURL(in: output))
                    }
                    if unreadable == .afterRetryLeavingARecord, recorder.runners == 2 {
                        let record = CaptureBundleLayout.url(forRelativePath: CaptureBundleLayout.appleAuditPath(screenID: "progress", stateSlug: "dark"), in: output)
                        try FileManager.default.createDirectory(at: record.deletingLastPathComponent(), withIntermediateDirectories: true)
                        try JSONEncoder().encode(TestManagerRestartTests.timedOut).write(to: record)
                    }
                }
                guard arguments.contains("launchctl") else {
                    let result = try script.run(executable, arguments, environment)
                    if unreadable == .anotherWalks, arguments.contains("test-without-building") {
                        try Self.stampAnotherWalksNonce(in: output)
                    }
                    return result
                }
                recorder.leased.append(leases.all().map(\.udid))
                _ = try script.run(executable, arguments, environment)
                return restartReply
            })
            return try command.performWalk(shell: shell, pause: { _ in }, now: script.now, runner: { WalkCommandTests.runner }, builds: WalkCommandTests.builds(in: directory), leases: leases, interruption: interruption, handbackBound: 0, interruptionNote: { _ in })
        }
    }

    /// What the restart call saw, kept across the script's calls.
    final class Recorder: @unchecked Sendable {
        var leased: [[String]] = []
        /// How many runners the walk has started.
        var runners = 0
    }

    /// Where a `SerialWalk` leaves no manifest this walk can read.
    enum Unreadable {
        /// The first runner files its captures and audit records but never finalises the manifest, as a runner stopped or crashed late does.
        case firstPass
        /// The first runner's manifest is finalised under another walk's nonce, its audit records on disk beside it, as a second walk given the same output leaves it.
        case anotherWalks
        /// The first pass refuses `progress`'s dark state on appearance and its bundle reads; the appearance retry's runner leaves nothing and the first pass's manifest is gone by then.
        case afterRetry
        /// As ``afterRetry``, and the walk's bundle is left holding a timed-out audit record of `progress`'s dark state, as a fold stopped between filing the retry's captures and writing its manifest would leave it.
        case afterRetryLeavingARecord
        /// The first pass refuses `progress`'s dark state on appearance and its bundle reads; the appearance retry's runner files its captures and audit records into its scratch bundle, never finalises its manifest, and exits 65, as a runner that crashed late does.
        case retryRunnerCrashed
    }
}
