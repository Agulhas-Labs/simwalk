//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore
import SimWalkTestSupport
import Testing

/// The crop files a diff writes: how each is keyed, named and protected from being overwritten.
struct BundleDiffCropsTests {
    /// A flag carrying two crops on one side (overlapping sections) writes two files and reports both, each under its own key.
    @Test
    func aFlagWithTwoCropsOnOneSideKeepsBoth() throws {
        let (directory, other) = try (TemporaryDirectory(), TemporaryDirectory())
        let (reference, run) = try BundleDiffCommandTests.pair(in: directory, other, reference: [BundleDiffCommandTests.alpha], run: [BundleDiffCommandTests.alpha])
        let diff = Self.diff(run, states: [Self.state([Self.overlap(run)], run)])
        let target = directory.url.appendingPathComponent("crops")

        let crops = try BundleDiffCrops.write(diff, reference: reference, run: run, into: target)
        let lines = BundleDiffRendering.lines(of: diff, crops: crops)

        #expect(crops.outcomes.count == 2)
        #expect(crops.failedCount == 0)
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.path).sorted() == ["s__light__1.png", "s__light__2.png"])
        #expect(lines.contains { $0.contains("→ s__light__1.png") && $0.contains("→ s__light__2.png") })
    }

    /// The header names the crops directory once, and no flag line repeats it.
    @Test
    func theDirectoryIsNamedOnceAndFilesAreBare() throws {
        let (directory, other) = try (TemporaryDirectory(), TemporaryDirectory())
        let (reference, run) = try BundleDiffCommandTests.pair(in: directory, other, reference: [BundleDiffCommandTests.alpha], run: [BundleDiffCommandTests.alpha])
        let diff = Self.diff(run, states: [Self.state([Self.overlap(run)], run)])
        let target = directory.url.appendingPathComponent("crops")

        let crops = try BundleDiffCrops.write(diff, reference: reference, run: run, into: target)
        let text = BundleDiffRendering.lines(of: diff, crops: crops).joined(separator: "\n")

        #expect(text.components(separatedBy: target.path).count == 2)
        #expect(text.contains("crops in \(target.path)"))
    }

    /// A name that would land on an existing file leaves that file alone and is reported as not written.
    @Test
    func aCropNeverOverwritesAnExistingFile() throws {
        let (directory, other) = try (TemporaryDirectory(), TemporaryDirectory())
        let (reference, run) = try BundleDiffCommandTests.pair(in: directory, other, reference: [BundleDiffCommandTests.alpha], run: [BundleDiffCommandTests.alpha])
        let diff = Self.diff(run, states: [Self.state([Self.overlap(run)], run), Self.state([Self.overlap(run)], run)])
        let target = directory.url.appendingPathComponent("crops")

        let crops = try BundleDiffCrops.write(diff, reference: reference, run: run, into: target)

        #expect(crops.failedCount == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: target.path).count == 2)
    }

    static func path(_ bundle: CaptureBundle) -> String {
        bundle.manifest.screens[0].captures[0].screenshotPath
    }

    static func overlap(_ bundle: CaptureBundle) -> FormFlag {
        let path = path(bundle)
        return FormFlag(key: "A", finding: .overlappingSections(other: "B", alsoInReference: false), crops: [
            SectionCrop(side: .run, screenshotPath: path, rect: AXNode.Frame(x: 14, y: 60, width: 374, height: 44), visibility: .whole),
            SectionCrop(side: .run, screenshotPath: path, rect: AXNode.Frame(x: 14, y: 100, width: 374, height: 44), visibility: .whole),
        ])
    }

    static func state(_ flags: [FormFlag], _ bundle: CaptureBundle) -> StateDiff {
        let segmentation = StateDiff.Segmentation(screenshotPath: path(bundle), sectionCount: 1)
        return StateDiff(slug: "light", reference: segmentation, run: segmentation, flags: flags)
    }

    static func diff(_: CaptureBundle, states: [StateDiff]) -> BundleDiff {
        let build = BundleDiff.Build(walkName: "walk", appBundleID: "app", appBuildHash: "a1b2c3d4", walkbookHash: "w")
        let screen = ScreenDiff(id: "s", referenceOutcome: .captured, runOutcome: .captured, states: states, unpairedStates: [])
        return BundleDiff(reference: build, run: build, screens: [screen], unpairedScreens: [])
    }
}
