//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import Testing

/// The result file's field names, pinned against the example `Docs/SIMWALK-PROGRESS.md` §4 publishes — a results pane reads those names, so a renamed key is a broken pane.
struct WalkResultCodingTests {
    /// The spec's example, verbatim.
    static var specExample: String {
        """
        {
          "schemaVersion": 1,
          "tool": "walk",
          "verdict": "failed",
          "walkName": "…", "app": "com.example.App", "device": { "name": "…", "udid": "…", "osVersion": "…" },
          "bundlePath": "/abs/Out.simwalk",
          "logPath": "/abs/usage.jsonl",
          "timings": { "bootMs": 8200, "installMs": 900, "buildMs": 31000, "runMs": 52000, "totalMs": 95000 },
          "counts": { "planned": 12, "passed": 11, "failed": 1 },
          "steps": [
            { "index": 1, "screen": "home", "outcome": "passed", "screenshotPath": "/abs/…/screenshot.png" },
            { "index": 4, "screen": "login", "outcome": "failed", "kind": "unexpectedScreen", "reason": "…" }
          ],
          "failures": [
            { "index": 4, "screen": "login", "kind": "unexpectedScreen", "reason": "…",
              "expected": "login", "actual": ["welcome"], "screenshotPath": "/abs/…/screenshot.png" }
          ],
          "truncated": { "omittedSteps": 0, "clippedFailures": 0 }
        }
        """
    }

    static func exampleValue() -> WalkResult {
        WalkResult(
            schemaVersion: 1,
            tool: "walk",
            verdict: .failed,
            walkName: "…",
            app: "com.example.App",
            device: WalkProgress.Device(name: "…", udid: "…", osVersion: "…"),
            bundlePath: "/abs/Out.simwalk",
            logPath: "/abs/usage.jsonl",
            timings: PhaseTimings(bootMs: 8200, installMs: 900, buildMs: 31000, runMs: 52000, totalMs: 95000),
            counts: WalkResult.Counts(planned: 12, passed: 11, failed: 1),
            steps: [
                WalkResult.Step(index: 1, screen: "home", outcome: .passed, screenshotPath: "/abs/…/screenshot.png"),
                WalkResult.Step(index: 4, screen: "login", outcome: .failed, kind: "unexpectedScreen", reason: "…"),
            ],
            failures: [
                WalkResult.Failure(
                    index: 4,
                    screen: "login",
                    kind: "unexpectedScreen",
                    reason: "…",
                    expected: "login",
                    actual: ["welcome"],
                    screenshotPath: "/abs/…/screenshot.png"
                ),
            ],
            truncated: WalkResult.Truncated(omittedSteps: 0)
        )
    }

    @Test
    func theSpecExampleDecodesToTheModel() throws {
        let decoded = try WalkResult.decoder().decode(WalkResult.self, from: Data(Self.specExample.utf8))

        #expect(decoded == Self.exampleValue())
    }

    /// Encoded, the model is the spec's example — every name the same, nothing extra.
    @Test
    func theModelEncodesToTheSpecExample() throws {
        let encoded = try WalkResult.encoder().encode(Self.exampleValue())
        let written = try #require(JSONSerialization.jsonObject(with: encoded) as? NSDictionary)
        let published = try #require(JSONSerialization.jsonObject(with: Data(Self.specExample.utf8)) as? NSDictionary)

        #expect(written == published)
    }

    /// What the builder writes for a passed screen and a wrong one, byte for byte: compact, sorted keys, unescaped slashes, `null` inside `actual`.
    @Test
    func aBuiltResultEncodesToTheGolden() throws {
        let screens = [
            WalkResultBuilderTests.captured("home"),
            CaptureManifest.ScreenRecord(
                id: "login",
                outcome: .unexpectedScreen(expected: "login", found: ["welcome", nil]),
                routeTaken: [.tap(label: "Sign in")],
                captures: [WalkResultBuilderTests.capture("login", .light)]
            ),
        ]
        let result = WalkResultBuilder().build(
            manifest: WalkResultBuilderTests.manifest(screens),
            bundleURL: WalkResultBuilderTests.bundleURL,
            timings: PhaseTimings(bootMs: 8200, installMs: 900, buildMs: 31000, runMs: 52000, totalMs: 95000),
            logPath: "/abs/usage.jsonl"
        )
        let text = try String(decoding: WalkResult.encoder().encode(result), as: UTF8.self)

        #expect(text == Self.golden)
    }

    static var golden: String {
        #"{"app":"com.example.App","bundlePath":"/abs/Out.simwalk","counts":{"failed":1,"passed":1,"planned":2},"#
            + #""device":{"name":"iPhone 17","osVersion":"26.5","udid":"U-1"},"#
            + #""failures":[{"actual":["welcome",null],"expected":"login","index":2,"kind":"unexpectedScreen","#
            + #""reason":"not the screen its walkbook expected","screen":"login","#
            + #""screenshotPath":"/abs/Out.simwalk/screens/login/light/screen.png"}],"#
            + #""logPath":"/abs/usage.jsonl","schemaVersion":1,"#
            + #""steps":[{"index":1,"outcome":"passed","screen":"home","screenshotPath":"/abs/Out.simwalk/screens/home/light/screen.png"},"#
            + #"{"index":2,"kind":"unexpectedScreen","outcome":"failed","reason":"not the screen its walkbook expected","screen":"login"}],"#
            + #""timings":{"bootMs":8200,"buildMs":31000,"installMs":900,"runMs":52000,"totalMs":95000},"#
            + #""tool":"walk","truncated":{"clippedFailures":0,"omittedSteps":0},"verdict":"failed","walkName":"example"}"#
    }
}
