//
// Copyright © Agulhas Labs
//

import Foundation
@testable import SimWalkCore
import SimWalkTestSupport
import Testing

struct ShardBundleMergeTests {
    /// Settings-shaped: five screens of 3, 2, 1, 2 and 1 states, so three devices shard it `[root] [general account] [accessibility display]`.
    private static func book() throws -> Walkbook {
        let screens = [("root", 3), ("general", 2), ("accessibility", 1), ("display", 2), ("account", 1)].map { id, states in
            #"{"id": "\#(id)", "route": [], "states": [\#(Array(repeating: #"{"theme": "light"}"#, count: states).joined(separator: ", "))]}"#
        }
        let json = #"{"name": "settings", "appBundleID": "com.example.app", "screens": [\#(screens.joined(separator: ", "))]}"#
        return try JSONDecoder().decode(Walkbook.self, from: Data(json.utf8))
    }

    private static func device(_ index: Int) -> CaptureManifest.Device {
        CaptureManifest.Device(name: "iPhone \(index)", udid: "AAAAAAA\(index)-0000-4000-8000-000000000000", osVersion: "26.0")
    }

    /// Writes shard `index` as the walk would: a finalised bundle at its scratch path holding `screens`.
    private static func writeShard(
        in output: URL,
        index: Int,
        screens: [String],
        build: String = "build1",
        started: Double = 100,
        finished: Double = 200,
        setup: CaptureManifest.SetupRecord? = nil,
        settle: CaptureManifest.AppearanceSettle? = nil,
        refusing refused: Set<String> = [],
        extraFile: Bool = false
    ) throws {
        let url = CaptureBundleLayout.shardScratchDirectory(in: output, index: index)
        let writer = try CaptureBundleWriter(preparingAt: url)
        var records: [CaptureManifest.ScreenRecord] = []
        for id in screens {
            if refused.contains(id) {
                let dark = Walkbook.CaptureState(theme: .dark)
                records.append(CaptureManifest.ScreenRecord(id: id, outcome: .stateNotApplied(reason: "still light"), routeTaken: [], refusedStates: [dark], refusedOnAppearance: [dark]))
                continue
            }
            let state = Walkbook.CaptureState(theme: .light)
            try writer.prepareDirectory(screenID: id, state: state)
            let capture = CaptureManifest.StateCapture(screenID: id, state: state)
            try CaptureBundleFixture.screenshot(width: 10, height: 10).write(to: CaptureBundleLayout.url(forRelativePath: capture.screenshotPath, in: url))
            try JSONEncoder().encode(CaptureBundleFixture.plainScreen()).write(to: CaptureBundleLayout.url(forRelativePath: capture.axTreePath, in: url))
            records.append(CaptureManifest.ScreenRecord(id: id, outcome: .captured, routeTaken: [], captures: [capture]))
        }
        if extraFile {
            try Data("x".utf8).write(to: url.appendingPathComponent("stray.txt"))
        }
        var manifest = CaptureManifest(
            walkName: "settings",
            appBundleID: "com.example.app",
            appBuildHash: build,
            walkbookHash: "shard-hash",
            device: device(index),
            startedAt: Date(timeIntervalSince1970: started),
            finishedAt: Date(timeIntervalSince1970: finished),
            runnerCommit: "commit\(index)",
            appearanceSettle: settle,
            nonce: "nonce\(index)",
            screens: records
        )
        manifest.deviceSetup = setup
        try writer.finalise(manifest)
    }

    /// A screen walked again after a settle, for a first attempt that refused its dark state.
    private static func retry(_ id: String) -> CaptureManifest.AppearanceSettle.Retry {
        let dark = Walkbook.CaptureState(theme: .dark)
        return CaptureManifest.AppearanceSettle.Retry(id: id, firstOutcome: .stateNotApplied(reason: "still light"), firstRefusedStates: [dark], firstRefusedOnAppearance: [dark])
    }

    private static func merged(
        _ configure: (URL, ShardPlan) throws -> Void = { output, plan in
            for (index, screens) in plan.shards.enumerated() {
                try writeShard(in: output, index: index, screens: screens)
            }
        },
        book: Walkbook? = nil,
        check: (CaptureBundle, ShardBundleMerge.Result, URL) throws -> Void
    ) throws {
        let directory = try TemporaryDirectory()
        let output = directory.url.appendingPathComponent("walk.\(CaptureBundleLayout.directoryExtension)")
        let book = try book ?? Self.book()
        let plan = ShardPlan(book, devices: 3)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try configure(output, plan)
        let result = try ShardBundleMerge.merge(walkbook: book, plan: plan, into: output)
        try check(result.bundle, result, output)
    }

    @Test func screensAreInWalkbookOrderNotShardOrder() throws {
        try Self.merged { bundle, _, _ in
            #expect(bundle.manifest.screens.map(\.id) == ["root", "general", "accessibility", "display", "account"])
        }
    }

    @Test func eachScreenNamesTheDeviceItWasCapturedOn() throws {
        try Self.merged { bundle, _, _ in
            let devices = bundle.manifest.screens.map { $0.capturedOn?.udid.prefix(8) }
            #expect(devices == ["AAAAAAA0", "AAAAAAA1", "AAAAAAA2", "AAAAAAA2", "AAAAAAA1"])
            #expect(bundle.manifest.screens[1].capturedOn?.name == "iPhone 1")
        }
    }

    @Test func theWalkbookHashIsTheSerialSelectionsAndTheTimesTheEarliestAndLatest() throws {
        let book = try Self.book()
        let selection = try WalkbookSubset.narrow(book, to: ["general", "display", "account"])
        let directory = try TemporaryDirectory()
        let output = directory.url.appendingPathComponent("walk.\(CaptureBundleLayout.directoryExtension)")
        let plan = ShardPlan(selection, devices: 2)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (index, screens) in plan.shards.enumerated() {
            try Self.writeShard(in: output, index: index, screens: screens, started: index == 0 ? 150 : 100, finished: index == 0 ? 200 : 300)
        }

        let bundle = try ShardBundleMerge.merge(walkbook: selection, plan: plan, into: output).bundle

        #expect(try bundle.manifest.walkbookHash == (WalkbookIdentity.hash(of: selection)))
        #expect(try bundle.manifest.walkbookHash != (WalkbookIdentity.hash(of: book)))
        #expect(bundle.manifest.startedAt == Date(timeIntervalSince1970: 100))
        #expect(bundle.manifest.finishedAt == Date(timeIntervalSince1970: 300))
        #expect(bundle.manifest.nonce == "nonce0")
        #expect(bundle.manifest.runnerCommit == "commit0")
        #expect(bundle.manifest.device == Self.device(0))
    }

    @Test func theMergedBundleReadsBackAndHoldsTheMovedArtefacts() throws {
        try Self.merged { bundle, _, output in
            let read = try CaptureBundle.read(at: output)

            #expect(read.manifest == bundle.manifest)
            #expect(FileManager.default.fileExists(atPath: CaptureBundleLayout.url(forRelativePath: bundle.manifest.screens[0].captures[0].screenshotPath, in: output).path))
        }
    }

    @Test func shardsWalkedAgainstDifferentBuildsAreRefusedAndNothingMoves() throws {
        let directory = try TemporaryDirectory()
        let output = directory.url.appendingPathComponent("walk.\(CaptureBundleLayout.directoryExtension)")
        let book = try Self.book()
        let plan = ShardPlan(book, devices: 3)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (index, screens) in plan.shards.enumerated() {
            try Self.writeShard(in: output, index: index, screens: screens, build: index == 2 ? "build2" : "build1")
        }

        #expect(throws: ShardBundleMergeError.buildsDiffer(builds: ["build1", "build2"])) {
            try ShardBundleMerge.merge(walkbook: book, plan: plan, into: output)
        }
        #expect(!FileManager.default.fileExists(atPath: CaptureBundleLayout.url(forRelativePath: CaptureBundleLayout.screenDirectory(screenID: "root"), in: output).path))
    }

    @Test func aShardMissingAPlannedScreenIsRefused() throws {
        let directory = try TemporaryDirectory()
        let output = directory.url.appendingPathComponent("walk.\(CaptureBundleLayout.directoryExtension)")
        let book = try Self.book()
        let plan = ShardPlan(book, devices: 3)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (index, screens) in plan.shards.enumerated() {
            try Self.writeShard(in: output, index: index, screens: index == 1 ? ["general"] : screens)
        }

        #expect(throws: ShardBundleMergeError.screenMissing(shard: 1, screenID: "account")) {
            try ShardBundleMerge.merge(walkbook: book, plan: plan, into: output)
        }
    }

    @Test func deviceSetupEntriesNameTheDeviceThatMadeThemInShardOrder() throws {
        try Self.merged { output, plan in
            for (index, screens) in plan.shards.enumerated() {
                let setup = CaptureManifest.SetupRecord(made: ["privacy grant"], handedBack: ["status bar"], notHandedBack: index == 1 ? ["simctl x"] : [])
                try Self.writeShard(in: output, index: index, screens: screens, setup: index == 1 ? nil : setup)
            }
        } check: { bundle, _, _ in
            let setup = try #require(bundle.manifest.deviceSetup)
            #expect(setup.made == ["privacy grant (on AAAAAAA0)", "privacy grant (on AAAAAAA2)"])
            #expect(setup.handedBack == ["status bar (on AAAAAAA0)", "status bar (on AAAAAAA2)"])
            #expect(setup.notHandedBack.isEmpty)
        }
    }

    @Test func oneShardsAppearanceSettleIsKeptAsIs() throws {
        let settle = CaptureManifest.AppearanceSettle(appearance: .dark, found: .light, milliseconds: 900, retried: [Self.retry("display")])
        try Self.merged { output, plan in
            for (index, screens) in plan.shards.enumerated() {
                try Self.writeShard(in: output, index: index, screens: screens, settle: index == 2 ? settle : nil)
            }
        } check: { bundle, _, _ in
            #expect(bundle.manifest.appearanceSettle == settle)
        }
    }

    @Test func settlesThatFoldedSumTimeAndOrderRetriesByWalkbook() throws {
        try Self.merged { output, plan in
            let settles: [CaptureManifest.AppearanceSettle?] = [
                nil,
                CaptureManifest.AppearanceSettle(appearance: .dark, found: .light, milliseconds: 400, retried: [Self.retry("account"), Self.retry("general")]),
                CaptureManifest.AppearanceSettle(appearance: .dark, found: .light, milliseconds: 500, retried: [Self.retry("display")]),
            ]
            for (index, screens) in plan.shards.enumerated() {
                try Self.writeShard(in: output, index: index, screens: screens, settle: settles[index])
            }
        } check: { bundle, _, _ in
            let settle = try #require(bundle.manifest.appearanceSettle)
            #expect(settle.milliseconds == 900)
            #expect(settle.retried.map(\.id) == ["general", "display", "account"])
            #expect(settle.folded)
        }
    }

    @Test func aSettleThatFailedNamesItsDeviceAndKeepsOnlyTheRetriesThatKeptTheirFirstAttempt() throws {
        let retry = Self.retry
        try Self.merged { output, plan in
            let settles: [CaptureManifest.AppearanceSettle?] = [
                nil,
                CaptureManifest.AppearanceSettle(appearance: .dark, found: .light, milliseconds: 400, retried: [retry("account"), retry("general")], settleFailure: "boot failed"),
                CaptureManifest.AppearanceSettle(appearance: .dark, found: .light, milliseconds: 500, retried: [retry("display")]),
            ]
            for (index, screens) in plan.shards.enumerated() {
                try Self.writeShard(in: output, index: index, screens: screens, settle: settles[index], refusing: index == 1 ? ["general", "account"] : [])
            }
        } check: { bundle, _, _ in
            let settle = try #require(bundle.manifest.appearanceSettle)
            #expect(settle.milliseconds == 900)
            #expect(settle.retried.map(\.id) == ["general", "account"])
            #expect(settle.settleFailure == "iPhone 1 (AAAAAAA1): boot failed")
            #expect(settle.secondPassFailure == nil)
        }
    }

    @Test func aShardDirectoryHoldingOnlyEmptyDirectoriesIsRemovedAndOneWithAFileIsKeptAndReturned() throws {
        try Self.merged { output, plan in
            for (index, screens) in plan.shards.enumerated() {
                try Self.writeShard(in: output, index: index, screens: screens, extraFile: index == 1)
            }
        } check: { _, result, output in
            let kept = CaptureBundleLayout.shardScratchDirectory(in: output, index: 1)
            #expect(result.leftoverShardDirectories == [kept])
            #expect(FileManager.default.fileExists(atPath: kept.appendingPathComponent("stray.txt").path))
            #expect(!FileManager.default.fileExists(atPath: CaptureBundleLayout.shardScratchDirectory(in: output, index: 0).path))
            #expect(!FileManager.default.fileExists(atPath: CaptureBundleLayout.shardScratchDirectory(in: output, index: 2).path))
        }
    }

    @Test func aCleanMergeLeavesNoShardDirectory() throws {
        try Self.merged { _, result, output in
            #expect(result.leftoverShardDirectories.isEmpty)
            #expect(!FileManager.default.fileExists(atPath: CaptureBundleLayout.shardScratchDirectory(in: output, index: 0).path))
        }
    }
}
