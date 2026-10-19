//
// Copyright © Agulhas Labs
//

import ArgumentParser
import CoreGraphics
import Foundation
import ImageIO
@testable import SimWalkCLI
import SimWalkCore
import SimWalkMCP
import SimWalkTestSupport
import Testing

/// `bundle diff` on both faces: the verdict and its exit code, the crops it writes, and that the CLI and the MCP tool are one answer.
struct BundleDiffCommandTests {
    /// Two headed sections against one: a presence flag with a crop in the screenshot, another below the fold with none, exit 2, and the crop is the section's pixels (points x 3, the PNG being 3x).
    @Test
    func aFlagIsQualifiedAndItsCropIsWrittenAtTheScreenshotsScale() throws {
        let (directory, other) = try (TemporaryDirectory(), TemporaryDirectory())
        let (reference, run) = try Self.pair(in: directory, other, reference: [Self.alpha, Self.beta], run: [Self.alpha, Self.gamma])
        let crops = directory.url.appendingPathComponent("crops")
        let recorder = StreamRecorder()

        let thrown = try #require(#expect(throws: ExitCode.self) {
            try BundleDiffCommand.parse([reference.url.path, run.url.path, "--crops", crops.path]).run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError)
        })
        let text = try #require(recorder.out.first)
        let written = try FileManager.default.contentsOfDirectory(atPath: crops.path)
        let size = try #require(PNGSize(contentsOf: crops.appendingPathComponent("s__light__1.png")))

        #expect(thrown == ExitCode(AnswerVerdict.qualifiedExitCode))
        #expect(text.contains("qualified — 2 flags raised"))
        #expect(text.contains("reference only · ref @14,200 374×44 → s__light__1.png"))
        #expect(text.contains("crops in \(crops.path)"))
        #expect(!text.contains("\(crops.path)/"))
        #expect(text.contains("run only · run @14,1000 374×44 not in screenshot"))
        #expect(written == ["s__light__1.png"])
        #expect(size == PNGSize(width: 374 * 3, height: 44 * 3))
    }

    /// A bundle against itself is clean and exits 0 without throwing.
    @Test
    func aBundleAgainstItselfExitsZero() throws {
        let (directory, other) = try (TemporaryDirectory(), TemporaryDirectory())
        let (reference, _) = try Self.pair(in: directory, other, reference: [Self.alpha, Self.beta], run: [Self.alpha, Self.beta])
        let recorder = StreamRecorder()

        try BundleDiffCommand.parse([reference.url.path, reference.url.path]).run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError)

        #expect(recorder.out.first?.contains("ok — 1 screen compared, 1 state") == true)
    }

    /// A bundle whose own sections cross, against itself (#74): the flag is on both sides, so it is reported apart and is no difference: exit 0, the flag still printed, on the CLI and the MCP face alike.
    @Test
    func aFlagBothSidesCarryIsReportedApartAndExitsZero() throws {
        let (directory, other) = try (TemporaryDirectory(), TemporaryDirectory())
        let crossing = [Section(heading: "Crossing", y: 60, proseOffset: 8)]
        let (reference, _) = try Self.pair(in: directory, other, reference: crossing, run: crossing)
        let recorder = StreamRecorder()

        try BundleDiffCommand.parse([reference.url.path, reference.url.path]).run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError)
        let text = try #require(recorder.out.first)
        let answer = try BundleDiffCommand.parse([reference.url.path, reference.url.path]).answer()

        #expect(text.contains("ok — "))
        #expect(text.contains("also in reference"))
        #expect(text.contains("also in the reference (not counted)"))
        #expect(answer.verdict.exitCode == 0)
    }

    /// The other half of #74: sections that overlap in the run and not in the reference are a difference.
    ///
    /// The flag is counted, none is inherited, and the verdict is qualified, exit 2.
    @Test
    func aFlagOnlyTheRunCarriesIsCountedAndExitsTwo() throws {
        let (directory, other) = try (TemporaryDirectory(), TemporaryDirectory())
        let (reference, run) = try Self.pair(
            in: directory, other,
            reference: [Self.alpha, Self.beta],
            run: [Self.alpha, Section(heading: "Beta", y: 90)]
        )

        let answer = try BundleDiffCommand.parse([reference.url.path, run.url.path]).answer()
        let diff = BundleDiff.compare(run: run, against: reference)

        let flags = diff.screens.flatMap(\.states).flatMap(\.flags)
        let overlap = flags.filter { $0.rule == "overlap" }

        #expect(overlap.count == 1)
        #expect(overlap.allSatisfy { !$0.isInherited })
        #expect(diff.flagCount == flags.count)
        #expect(diff.inheritedFlagCount == 0)
        #expect(answer.verdict.isQualified)
        #expect(answer.verdict.exitCode == 2)
        #expect(!answer.text.contains("also in reference"))
    }

    /// A crops directory that holds something is refused before anything is read, and nothing in it is touched.
    @Test
    func aCropsDirectoryThatIsNotEmptyIsRefused() throws {
        let directory = try TemporaryDirectory()
        let crops = directory.url.appendingPathComponent("crops")
        try FileManager.default.createDirectory(at: crops, withIntermediateDirectories: true)
        try Data("earlier".utf8).write(to: crops.appendingPathComponent("earlier.png"))
        let recorder = StreamRecorder()

        let thrown = try #require(#expect(throws: ExitCode.self) {
            try BundleDiffCommand.parse(["a.simwalk", "b.simwalk", "--crops", crops.path]).run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError)
        })

        #expect(thrown == ExitCode.failure)
        #expect(recorder.out.isEmpty)
        #expect(recorder.err.first?.contains("already holds 1 item") == true)
        #expect(try FileManager.default.contentsOfDirectory(atPath: crops.path) == ["earlier.png"])
    }

    /// A reference captured with animations on and a run captured with them off are refused with the reason, and no diff is printed (SimWalk#154).
    @Test
    func bundlesCapturedWithAnimationsInDifferentStatesAreRefused() throws {
        let (directory, other) = try (TemporaryDirectory(), TemporaryDirectory())
        let (reference, run) = try Self.pair(in: directory, other, reference: [Self.alpha], run: [Self.alpha])
        let manifestURL = CaptureBundle.manifestURL(in: run.url)
        var json = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any])
        json["animations"] = "off"
        try JSONSerialization.data(withJSONObject: json).write(to: manifestURL)
        let recorder = StreamRecorder()

        let thrown = try #require(#expect(throws: ExitCode.self) {
            try BundleDiffCommand.parse([reference.url.path, run.url.path]).run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError)
        })

        #expect(thrown == ExitCode.failure)
        #expect(recorder.out.isEmpty)
        #expect(recorder.err.first?.contains("bundle diff refused: the reference was captured with animations on (recorded before SimWalk recorded it) and the run with animations off") == true)
    }

    /// A bundle that cannot be read is a refusal, exit 1, with nothing on stdout.
    @Test
    func anUnreadableBundleRefuses() throws {
        let directory = try TemporaryDirectory()
        let recorder = StreamRecorder()

        let thrown = try #require(#expect(throws: ExitCode.self) {
            try BundleDiffCommand.parse([directory.url.appendingPathComponent("a.simwalk").path, directory.url.appendingPathComponent("b.simwalk").path]).run(log: Self.log(in: directory), emit: recorder.emit, emitError: recorder.emitError)
        })

        #expect(thrown == ExitCode.failure)
        #expect(recorder.out.isEmpty)
    }

    /// The MCP tool answers with the CLI command's own text, crops included, and its arguments become the command's vector.
    @Test
    func theMCPToolAnswersWhatTheCommandAnswers() throws {
        let (directory, other) = try (TemporaryDirectory(), TemporaryDirectory())
        let (reference, run) = try Self.pair(in: directory, other, reference: [Self.alpha, Self.beta], run: [Self.alpha, Self.gamma])
        let cli = try BundleDiffCommand.parse(["--crops", directory.url.appendingPathComponent("one").path, reference.url.path, run.url.path]).answer()
        let invocation = try MCPToolInvocation(tool: "diff", arguments: ["reference": reference.url.path, "run": run.url.path, "crops": directory.url.appendingPathComponent("two").path])
        let mcp = try MCPToolRunner.answer(tool: invocation.tool, arguments: invocation.argumentVector)

        #expect(invocation.logName == "bundle diff")
        #expect(mcp.text.replacingOccurrences(of: "/two", with: "/one") == cli.text)
        #expect(mcp.verdict == cli.verdict)
    }

    static let alpha = Section(heading: "Alpha", y: 60)
    static let beta = Section(heading: "Beta", y: 200)
    static let gamma = Section(heading: "Gamma", y: 1000)

    /// Two one-screen bundles whose trees hold the given headed sections, each with a real 3x screenshot.
    ///
    /// The run's directory is the caller's to keep alive: a `TemporaryDirectory` reaps what it holds when it goes.
    static func pair(in directory: TemporaryDirectory, _ other: TemporaryDirectory, reference: [Section], run: [Section]) throws -> (CaptureBundle, CaptureBundle) {
        try (bundle(in: directory, sections: reference), bundle(in: other, sections: run))
    }

    static func bundle(in directory: TemporaryDirectory, sections: [Section], sourceLocation: SourceLocation = #_sourceLocation) throws -> CaptureBundle {
        let state = Walkbook.CaptureState(theme: .light)
        let children = sections.flatMap { section in
            [
                AXNode(type: "StaticText", frame: AXNode.Frame(x: 14, y: section.y, width: 374, height: 20), label: section.heading),
                AXNode(type: "StaticText", frame: AXNode.Frame(x: 14, y: section.y + section.proseOffset, width: 374, height: 20), label: "A longer line of prose under \(section.heading) that is not a heading at all"),
            ]
        }
        let tree = AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874), children: children)
        let bundle = try CaptureBundleFixture.write(in: directory, captures: [CaptureBundleFixture.Capture(screenID: "s", state: state, tree: tree)])
        let capture = try #require(bundle.manifest.screens.first?.captures.first, sourceLocation: sourceLocation)
        try png(width: 402 * 3, height: 874 * 3, sourceLocation: sourceLocation).write(to: bundle.screenshotURL(for: capture))
        return bundle
    }

    static func png(width: Int, height: Int, sourceLocation: SourceLocation = #_sourceLocation) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue), sourceLocation: sourceLocation)
        context.setFillColor(CGColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let encoded = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(encoded, "public.png" as CFString, 1, nil), sourceLocation: sourceLocation)
        try CGImageDestinationAddImage(destination, #require(context.makeImage(), sourceLocation: sourceLocation), nil)
        #expect(CGImageDestinationFinalize(destination), sourceLocation: sourceLocation)
        return encoded as Data
    }

    private static func log(in directory: TemporaryDirectory) -> UsageLog {
        UsageLog(directory: directory.url, now: { Date(timeIntervalSince1970: 1_786_867_200) })
    }
}

extension BundleDiffCommandTests {
    struct Section {
        let heading: String
        let y: Double
        /// How far under the heading its prose starts; less than the heading is tall and the two runs cross.
        var proseOffset = 24.0
    }
}
