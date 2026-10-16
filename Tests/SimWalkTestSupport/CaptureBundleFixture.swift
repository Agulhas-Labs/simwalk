//
// Copyright © Agulhas Labs
//

import Foundation
import SimWalkCore

/// Writes a real capture bundle to a scratch directory: the manifest, the directories, and both artefacts per state.
///
/// A target rather than a copy per suite, for the reason `TemporaryDirectory` is one: the core's audit tests and the CLI's exit-code tests both need a bundle on disk, and a bundle built two ways is two answers to "what does a bundle look like" — the one thing every reader in this package agrees on. The trees are here too, because a chevron's geometry is taken from a real capture and a second, subtly different chevron would quietly test something else.
public struct CaptureBundleFixture {
    /// Writes one screen holding the given captures, plus any number of screens the walk never reached.
    public static func write(
        in directory: TemporaryDirectory,
        captures trees: [Capture],
        unreachable: [String] = [],
        outcome: ScreenOutcome = .captured,
        rawTreeBytes: String? = nil,
        formatVersion: Int = CaptureManifest.currentFormatVersion,
        buildHash: String = "a1b2c3d4",
        walkbookHash: String = "0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a69788796a5b4c3d2e1f0",
        nonce: String? = nil,
        appBuildProvenance: CaptureManifest.AppBuildProvenance? = nil
    ) throws -> CaptureBundle {
        precondition(!trees.isEmpty, "CaptureBundleFixture needs at least one tree — the manifest screen id comes from the first")
        let url = directory.url.appendingPathComponent("audit.\(CaptureBundleLayout.directoryExtension)")
        let writer = try CaptureBundleWriter(preparingAt: url)
        var captures: [CaptureManifest.StateCapture] = []
        for capture in trees {
            try writer.prepareDirectory(screenID: capture.screenID, state: capture.state)
            let record = CaptureManifest.StateCapture(
                screenID: capture.screenID,
                state: capture.state,
                axTreeSettled: capture.settled,
                axTreeHasContent: capture.hasContent
            )
            try Self.screenshot(width: capture.width, height: capture.height).write(to: CaptureBundleLayout.url(forRelativePath: record.screenshotPath, in: url))
            let bytes = try rawTreeBytes.map { Data($0.utf8) } ?? JSONEncoder().encode(capture.tree)
            try bytes.write(to: CaptureBundleLayout.url(forRelativePath: record.axTreePath, in: url))
            captures.append(record)
        }
        let screens = [
            CaptureManifest.ScreenRecord(
                id: trees[0].screenID,
                outcome: outcome,
                routeTaken: [.tab(label: "Progress")],
                captures: captures
            ),
        ] + unreachable.map {
            CaptureManifest.ScreenRecord(id: $0, outcome: .unreachable(routeTried: [.tap(label: "Power")]), routeTaken: [])
        }
        return try writer.finalise(CaptureManifest(
            formatVersion: formatVersion,
            walkName: "audit",
            appBundleID: "dev.simwalk.route-fixture",
            appBuildHash: buildHash,
            walkbookHash: walkbookHash,
            device: CaptureManifest.Device(name: "iPhone 17 Pro", udid: "9E7F0C2A-0000-4000-8000-000000000001", osVersion: "26.0"),
            startedAt: Date(timeIntervalSince1970: 1_786_867_200.125),
            finishedAt: Date(timeIntervalSince1970: 1_786_867_440.5),
            settleQuietMilliseconds: 250,
            nonce: nonce,
            appBuildProvenance: appBuildProvenance,
            screens: screens
        ))
    }

    /// Writes a walk of several distinct screens, each keyed by its own id — unlike `write(in:captures:…)`, which files every capture under its first tree's screen id.
    ///
    /// For a per-screen query over several screens, in walkbook order, rather than several states of one.
    public static func writeWalk(in directory: TemporaryDirectory, screens: [ScreenSpec], buildHash: String = "a1b2c3d4", walkbookHash: String = "0f1e2d3c4b5a69788796a5b4c3d2e1f00f1e2d3c4b5a69788796a5b4c3d2e1f0", nonce: String? = nil, appBuildProvenance: CaptureManifest.AppBuildProvenance? = nil, appBundleID: String = "dev.simwalk.route-fixture") throws -> CaptureBundle {
        precondition(!screens.isEmpty, "CaptureBundleFixture needs at least one screen")
        let url = directory.url.appendingPathComponent("walk.\(CaptureBundleLayout.directoryExtension)")
        let writer = try CaptureBundleWriter(preparingAt: url)
        var records: [CaptureManifest.ScreenRecord] = []
        for screen in screens {
            var captures: [CaptureManifest.StateCapture] = []
            for capture in screen.captures {
                try writer.prepareDirectory(screenID: capture.screenID, state: capture.state)
                let record = CaptureManifest.StateCapture(
                    screenID: capture.screenID,
                    state: capture.state,
                    axTreeSettled: capture.settled,
                    axTreeHasContent: capture.hasContent,
                    motion: capture.motion,
                    performance: capture.performance
                )
                try Self.screenshot(width: capture.width, height: capture.height).write(to: CaptureBundleLayout.url(forRelativePath: record.screenshotPath, in: url))
                try JSONEncoder().encode(capture.tree).write(to: CaptureBundleLayout.url(forRelativePath: record.axTreePath, in: url))
                captures.append(record)
            }
            records.append(CaptureManifest.ScreenRecord(
                id: screen.id,
                outcome: screen.outcome,
                routeTaken: screen.routeTaken,
                captures: captures,
                refusedStates: screen.refusedStates,
                refusedOnAppearance: screen.refusedOnAppearance
            ))
        }
        return try writer.finalise(CaptureManifest(
            walkName: "walk",
            appBundleID: appBundleID,
            appBuildHash: buildHash,
            walkbookHash: walkbookHash,
            device: CaptureManifest.Device(name: "iPhone 17 Pro", udid: "9E7F0C2A-0000-4000-8000-000000000001", osVersion: "26.0"),
            startedAt: Date(timeIntervalSince1970: 1_786_867_200.125),
            finishedAt: Date(timeIntervalSince1970: 1_786_867_440.5),
            settleQuietMilliseconds: 250,
            nonce: nonce,
            appBuildProvenance: appBuildProvenance,
            screens: records
        ))
    }

    /// A screenshot as far as anything that reads one here is concerned: the PNG signature and an IHDR chunk declaring the size.
    ///
    /// The dimensions are what a saving is priced from (`PNGSize` reads the header and nothing else), so a fixture writing three unreadable bytes would have made every bundle in the suite weigh its screenshots at nothing — the half of the measurement that matters most, silently absent from every test of it. No pixel data and no CRC: nothing in this package decodes one, and a file that has to be a *valid* image is a different fixture for a test that does not exist yet.
    public static func screenshot(width: Int, height: Int) -> Data {
        var bytes: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]
        bytes += [0x00, 0x00, 0x00, 0x0D] + Array("IHDR".utf8)
        bytes += Self.bigEndian(width) + Self.bigEndian(height)
        // Bit depth, colour type, compression, filter, interlace — the rest of IHDR, so the chunk is the
        // length it declares rather than four bytes short of it.
        bytes += [0x08, 0x06, 0x00, 0x00, 0x00]
        return Data(bytes)
    }

    /// Four bytes, most significant first — the byte order a PNG header is written in.
    private static func bigEndian(_ value: Int) -> [UInt8] {
        (0 ..< 4).reversed().map { UInt8((value >> ($0 * 8)) & 0xFF) }
    }

    /// A row whose trailing glyph sits where the real chevron does.
    public static func row(type: String, label: String, y: Double = 184) -> AXNode {
        AXNode(
            type: type,
            frame: AXNode.Frame(x: 14, y: y, width: 374, height: 55),
            label: label,
            children: [
                AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: y + 12, width: 90, height: 16), label: label),
                AXNode(type: "Other", frame: AXNode.Frame(x: 372.15, y: y + 20, width: 7.7, height: 13.7)),
            ]
        )
    }

    /// One screen with one chevron row of the given type.
    public static func screen(rowType: String) -> AXNode {
        AXNode(type: "Application", frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874), children: [row(type: rowType, label: "Log one meal")])
    }

    /// One chevron row typed as a control and one that is not — the inconsistency the audit reports.
    public static func mixedScreen() -> AXNode {
        AXNode(
            type: "Application",
            frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
            children: [row(type: "Button", label: "Heart"), row(type: "StaticText", label: "Log one meal", y: 260)]
        )
    }

    /// A range control: five pills drawn alike, one of them the active segment and one offered as unavailable.
    ///
    /// The specimen behind SimWalk#2 — the shape whose five members were byte-identical in a bundle while the app under it was exposing both traits correctly.
    public static func segmentedControl() -> AXNode {
        AXNode(
            type: "Application",
            frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
            children: ["D", "W", "M", "6M", "Y"].enumerated().map { index, label in
                AXNode(
                    type: "Button",
                    frame: AXNode.Frame(x: 16 + Double(index) * 74, y: 120, width: 70, height: 32),
                    label: label,
                    isSelected: label == "W",
                    isEnabled: label != "Y"
                )
            }
        )
    }

    /// A screen with no chevron on it at all.
    public static func plainScreen() -> AXNode {
        AXNode(
            type: "Application",
            frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
            children: [AXNode(type: "StaticText", frame: AXNode.Frame(x: 14, y: 184, width: 374, height: 55), label: "Nothing here opens")]
        )
    }

    /// A tab that has not populated: the app's name, a tab bar, and an unlabelled spinner carrying a value.
    ///
    /// The shape of the real specimen — an app's Browse tab captured at the default quiet period on 26 Aug 2026, filed as `captured` with `axTreeSettled: true`. The spinner's `value` is what makes it worth keeping as a fixture: a content check counting values rather than labels would read the loading indicator as the content it exists to notice was missing.
    public static func loadingScreen() -> AXNode {
        AXNode(
            type: "Application",
            frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
            label: "RouteFixture",
            children: [
                AXNode(
                    type: "Window",
                    frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
                    children: [
                        AXNode(type: "Type36", frame: AXNode.Frame(x: 191, y: 421, width: 20, height: 20), value: "1"),
                        tabBar(),
                    ]
                ),
            ]
        )
    }

    /// The same tab, populated — the tab bar unchanged and a screen underneath it.
    public static func populatedScreen() -> AXNode {
        AXNode(
            type: "Application",
            frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
            label: "RouteFixture",
            children: [
                AXNode(
                    type: "Window",
                    frame: AXNode.Frame(x: 0, y: 0, width: 402, height: 874),
                    children: [
                        AXNode(type: "StaticText", frame: AXNode.Frame(x: 22, y: 120, width: 200, height: 30), label: "Heart"),
                        tabBar(),
                    ]
                ),
            ]
        )
    }

    /// The four-tab bar both of the above are drawn inside, with Browse the selected one.
    public static func tabBar() -> AXNode {
        AXNode(
            type: "TabBar",
            frame: AXNode.Frame(x: 0, y: 791, width: 402, height: 83),
            label: "Tab Bar",
            children: ["Progress", "Workouts", "Browse", "You"].enumerated().map { index, label in
                AXNode(
                    type: "Button",
                    frame: AXNode.Frame(x: 25 + Double(index) * 90, y: 795, width: 85, height: 54),
                    label: label,
                    isSelected: label == "Browse"
                )
            }
        )
    }
}

public extension CaptureBundleFixture {
    /// One state of one screen: the tree it is written with, whether the runner had seen that tree hold still, whether it held a screen at all, and the size of the picture beside it.
    struct Capture {
        public let screenID: String
        public let state: Walkbook.CaptureState
        public let tree: AXNode
        public let settled: Bool
        public let hasContent: Bool
        /// The screenshot's dimensions, defaulting to the ones a real walk of an iPhone 17 produces — so a bundle written here weighs what a bundle written by the runner would.
        public let width: Int
        public let height: Int
        /// The capture's motion record, for a walk that asked for motion; `nil` as a walk that did not.
        public let motion: CaptureManifest.Motion?
        /// The capture's performance record, for a device walk that measured; `nil` as one that did not.
        public let performance: CaptureManifest.Performance?

        public init(
            screenID: String,
            state: Walkbook.CaptureState,
            tree: AXNode,
            settled: Bool = true,
            hasContent: Bool = true,
            width: Int = 1206,
            height: Int = 2622,
            motion: CaptureManifest.Motion? = nil,
            performance: CaptureManifest.Performance? = nil
        ) {
            self.motion = motion
            self.performance = performance
            self.screenID = screenID
            self.state = state
            self.tree = tree
            self.settled = settled
            self.hasContent = hasContent
            self.width = width
            self.height = height
        }
    }

    /// One screen of a multi-screen walk, for `writeWalk(in:screens:)`: its id, its outcome, the route it took, and its captures — each capture's own `screenID` should match `id`.
    struct ScreenSpec {
        public let id: String
        public let outcome: ScreenOutcome
        public let routeTaken: [Walkbook.RouteStep]
        public let captures: [Capture]
        /// States this screen's walk refused (`stateNotApplied`) rather than simply never asked for — what tells a caller's `--state` refusal apart from one naming a state this screen never planned.
        public let refusedStates: [Walkbook.CaptureState]
        /// Those of `refusedStates` the appearance check refused — what a walk settles its device for (SimWalk#26).
        public let refusedOnAppearance: [Walkbook.CaptureState]

        public init(
            id: String,
            outcome: ScreenOutcome = .captured,
            routeTaken: [Walkbook.RouteStep] = [.tab(label: "Progress")],
            captures: [Capture] = [],
            refusedStates: [Walkbook.CaptureState] = [],
            refusedOnAppearance: [Walkbook.CaptureState] = []
        ) {
            self.id = id
            self.outcome = outcome
            self.routeTaken = routeTaken
            self.captures = captures
            self.refusedStates = refusedStates
            self.refusedOnAppearance = refusedOnAppearance
        }
    }
}
