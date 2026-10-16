//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// The progress file's field names, pinned against the example `Docs/SIMWALK-PROGRESS.md` §2 publishes — the mod reads those names, so a renamed key is a broken mod.
struct WalkProgressCodingTests {
    /// The spec's example, verbatim: every key spelled, `null`s and `…` included.
    static var specExample: String {
        """
        {
          "schemaVersion": 1,
          "tool": "walk",
          "phase": "running",
          "pid": 4242,
          "startedAt": "2026-10-02T09:00:00.000Z",
          "updatedAt": "2026-10-02T09:00:41.250Z",
          "device": { "name": "iPhone 17", "udid": "…", "osVersion": "26.5" },
          "app": "com.example.App",
          "currentStep": { "index": 4, "total": 12, "action": "walk login", "screen": "login" },
          "matches": { "planned": 12, "passed": 3, "failed": 0, "pending": 9 },
          "lastScreenshotPath": "/abs/path/Out.simwalk/screens/home/light/screenshot.png",
          "summary": { "bootMs": 8200, "installMs": 900, "buildMs": 31000, "runMs": null },
          "logPath": "/Users/…/.simwalk/usage.jsonl",
          "resultPath": null,
          "error": null
        }
        """
    }

    static func exampleValue() -> WalkProgress {
        var progress = WalkProgress(tool: "walk", phase: .running, pid: 4242, startedAt: Date(timeIntervalSince1970: 1_790_931_600))
        progress.touch(at: Date(timeIntervalSince1970: 1_790_931_641.25))
        progress.device = WalkProgress.Device(name: "iPhone 17", udid: "…", osVersion: "26.5")
        progress.app = "com.example.App"
        progress.currentStep = WalkProgress.CurrentStep(index: 4, total: 12, action: "walk login", screen: "login")
        var matches = WalkProgress.Matches(planned: 12)
        for _ in 0 ..< 3 {
            matches.record(.captured)
        }
        progress.matches = matches
        progress.lastScreenshotPath = "/abs/path/Out.simwalk/screens/home/light/screenshot.png"
        progress.summary = PhaseTimings(bootMs: 8200, installMs: 900, buildMs: 31000)
        progress.logPath = "/Users/…/.simwalk/usage.jsonl"
        return progress
    }

    @Test
    func theSpecExampleDecodesToTheModel() throws {
        let decoded = try WalkProgress.decoder().decode(WalkProgress.self, from: Data(Self.specExample.utf8))

        #expect(decoded == Self.exampleValue())
    }

    /// Encoded, the model is the spec's example with its `null` keys left out — every name the same, nothing extra.
    @Test
    func theModelEncodesToTheSpecExampleWithoutItsNulls() throws {
        let encoded = try WalkProgress.encoder().encode(Self.exampleValue())
        let written = try #require(JSONSerialization.jsonObject(with: encoded) as? NSDictionary)
        let published = try #require(JSONSerialization.jsonObject(with: Data(Self.specExample.utf8)) as? [String: Any])

        #expect(written == NSDictionary(dictionary: Self.droppingNulls(published)))
    }

    @Test
    func theEncodingIsCompactSortedAndKeepsSlashes() throws {
        var progress = WalkProgress(tool: "session", phase: .booting, pid: 7, startedAt: Date(timeIntervalSince1970: 1_790_931_600.1234))
        progress.logPath = "/a/b"
        let text = try String(decoding: WalkProgress.encoder().encode(progress), as: UTF8.self)

        #expect(text == #"{"logPath":"/a/b","phase":"booting","pid":7,"schemaVersion":1,"startedAt":"2026-10-02T09:00:00.123Z","tool":"session","updatedAt":"2026-10-02T09:00:00.123Z"}"#)
    }

    @Test
    func aStateRoundTripsThroughItsOwnEncoding() throws {
        let progress = Self.exampleValue()
        let decoded = try WalkProgress.decoder().decode(WalkProgress.self, from: WalkProgress.encoder().encode(progress))

        #expect(decoded == progress)
    }

    /// `passed` is `captured` alone; every other outcome is `failed` (§2, `matches`).
    @Test
    func matchesCountCapturedAsPassedAndEveryOtherOutcomeAsFailed() {
        var matches = WalkProgress.Matches(planned: 7)
        let outcomes: [ScreenOutcome] = [
            .captured,
            .unreachable(routeTried: [.tap(label: "Power")]),
            .buildMismatch(expected: "a", found: "b"),
            .captureFailed(reason: "disk"),
            .stateNotApplied(reason: "dark"),
            .unexpectedScreen(expected: "login", found: ["welcome"]),
        ]
        for outcome in outcomes {
            matches.record(outcome)
        }

        #expect(matches == WalkProgress.Matches(planned: 7, passed: 1, failed: 5, pending: 1))
    }

    @Test
    func onlyDoneAndFailedAreTerminal() {
        let terminal = WalkProgress.Phase.allCases.filter(\.isTerminal)

        #expect(terminal == [.done, .failed])
        #expect(WalkProgress.Phase.allCases.count == 9)
    }

    private static func droppingNulls(_ object: [String: Any]) -> [String: Any] {
        object.reduce(into: [:]) { kept, entry in
            switch entry.value {
            case is NSNull:
                break
            case let nested as [String: Any]:
                kept[entry.key] = droppingNulls(nested)
            default:
                kept[entry.key] = entry.value
            }
        }
    }
}

private extension WalkProgress.Matches {
    init(planned: Int, passed: Int, failed: Int, pending: Int) {
        self.init(planned: planned)
        self.passed = passed
        self.failed = failed
        self.pending = pending
    }
}
